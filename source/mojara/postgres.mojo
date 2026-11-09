"""Native PostgreSQL connection and materialized result ownership.

PgConnection executes developer-controlled SQL with positional parameters.
PgRows stores detached text and NULL results after native result cleanup."""

from std.ffi import OwnedDLHandle, c_int


def _read_cstring(address: Int) -> String:
    """Copy a non-null libpq-owned, NUL-terminated UTF-8 string."""
    return String(
        unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
            unsafe_from_address=address
        )
    )


struct PgRows(Movable):
    """Detached result values: valid after libpq's PGresult is released."""

    var columns: List[String]
    var rows: List[List[Optional[String]]]

    def __init__(
        out self, var columns: List[String], var rows: List[List[Optional[String]]]
    ):
        """Take ownership of detached column names and result rows."""
        self.columns = columns^
        self.rows = rows^

    def row_count(self) -> Int:
        """Return the number of materialized rows."""
        return len(self.rows)

    def column_count(self) -> Int:
        """Return the number of result columns."""
        return len(self.columns)

    def cell(self, row: Int, column: Int) raises -> Optional[String]:
        """Get a text or NULL cell after validating its indices."""
        if row < 0 or row >= len(self.rows):
            raise Error("PostgreSQL result row out of range")
        if column < 0 or column >= len(self.columns):
            raise Error("PostgreSQL result column out of range")
        return self.rows[row][column].copy()


struct PgConnection(Movable):
    """One PostgreSQL connection, with automatic PQfinish cleanup.

    The native FFI handles are represented as Int: this module specifically
    targets the project's Linux x86_64 platform with 64-bit pointers.
    """

    var _handle: Int

    def __init__(out self, conninfo: String) raises:
        """Open a PostgreSQL connection using a validated connection string."""
        self._handle = 0
        if conninfo.byte_length() == 0:
            raise Error("PostgreSQL connection string is missing")
        var lib = OwnedDLHandle("libpq.so.5")
        var connect = lib.get_function[Int]("PQconnectdb")
        var dsn = conninfo.copy()
        var connection = connect(dsn.as_c_string_span())
        if connection == 0:
            raise Error("PostgreSQL connection allocation failed")
        var status = lib.get_function[c_int]("PQstatus")
        if status(connection) != 0:
            var finish = lib.get_function[NoneType]("PQfinish")
            finish(connection)
            # Never include conninfo or libpq's error message (may contain
            # database credentials, private hosts, or SQL parameters).
            raise Error("PostgreSQL connection failed; check server and credentials")
        var set_encoding = lib.get_function[c_int]("PQsetClientEncoding")
        var encoding = String("UTF8")
        if set_encoding(connection, encoding.as_c_string_span()) != 0:
            var finish = lib.get_function[NoneType]("PQfinish")
            finish(connection)
            raise Error("PostgreSQL requires UTF-8 client encoding")
        self._handle = connection

    def __deinit__(deinit self):
        if self._handle != 0:
            try:
                var lib = OwnedDLHandle("libpq.so.5")
                var finish = lib.get_function[NoneType]("PQfinish")
                finish(self._handle)
            except:
                pass

    def query(
        self, sql: String, params: List[String] = List[String]()
    ) raises -> PgRows:
        """Execute trusted SQL using libpq parameter binding for all data.

        Parameters bind as UTF-8 text; use an explicit SQL cast where
        PostgreSQL expects a different type. This interface does not bind
        SQL NULL parameter values or decode binary/bytea results.
        """
        if sql.byte_length() == 0 or sql.byte_length() > 1048576:
            raise Error("SQL statement is empty or too large")
        if len(params) > 256:
            raise Error("Too many PostgreSQL parameters")
        var lib = OwnedDLHandle("libpq.so.5")
        var query_owned = sql.copy()
        var result_ptr: Int
        if len(params) == 0:
            var execute = lib.get_function[Int]("PQexec")
            result_ptr = execute(self._handle, query_owned.as_c_string_span())
        else:
            # Use a single stable buffer for all text parameters. Nested
            # List buffers and their raw pointers can become invalid when
            # Mojo ends a value's lifetime before the foreign function call.
            var param_bytes = List[UInt8]()
            var offsets = List[Int]()
            for i in range(len(params)):
                offsets.append(len(param_bytes))
                var item = params[i].copy()
                for j in range(item.byte_length()):
                    var byte = item.as_bytes()[j]
                    if byte == 0:
                        raise Error(
                            "PostgreSQL text parameters cannot contain NUL bytes"
                        )
                    param_bytes.append(byte)
                param_bytes.append(0)
            var base_address = Int(param_bytes.unsafe_ptr())
            var pointers = List[Int]()
            for i in range(len(offsets)):
                pointers.append(base_address + offsets[i])
            var execute_params = lib.get_function[Int]("PQexecParams")
            result_ptr = execute_params(
                self._handle,
                query_owned.as_c_string_span(),
                c_int(len(params)),
                Int(0),
                pointers.unsafe_ptr(),
                Int(0),
                Int(0),
                c_int(0),
            )
            # Keep the backing allocation live until PQexecParams returns.
            if param_bytes[len(param_bytes) - 1] != 0:
                raise Error("PostgreSQL parameter buffer sentinel was lost")
        if result_ptr == 0:
            raise Error("PostgreSQL operation failed without a result")
        var result_status = lib.get_function[c_int]("PQresultStatus")
        var status = Int(result_status(result_ptr))
        var clear = lib.get_function[NoneType]("PQclear")
        # PGRES_COMMAND_OK=1; PGRES_TUPLES_OK=2. Reject COPY and stream states.
        if status != 1 and status != 2:
            var error_field = lib.get_function[Int]("PQresultErrorField")
            var code_ptr = error_field(result_ptr, c_int(67))
            var sqlstate = String("unknown")
            if code_ptr != 0:
                sqlstate = _read_cstring(code_ptr)
            clear(result_ptr)
            raise Error(
                "PostgreSQL operation failed (SQLSTATE "
                + sqlstate
                + ", status "
                + String(status)
                + ")"
            )
        var num_fields = lib.get_function[c_int]("PQnfields")
        var num_tuples = lib.get_function[c_int]("PQntuples")
        var get_name = lib.get_function[Int]("PQfname")
        var get_value = lib.get_function[Int]("PQgetvalue")
        var get_null = lib.get_function[c_int]("PQgetisnull")
        var ncols = Int(num_fields(result_ptr))
        var nrows = Int(num_tuples(result_ptr))
        if ncols > 256 or nrows > 100000:
            clear(result_ptr)
            raise Error("PostgreSQL result exceeds configured safety limits")
        var names = List[String]()
        var result_rows = List[List[Optional[String]]]()
        for col in range(ncols):
            var name_ptr = get_name(result_ptr, c_int(col))
            if name_ptr == 0:
                clear(result_ptr)
                raise Error("PostgreSQL result has an invalid column name")
            names.append(_read_cstring(name_ptr))
        for row in range(nrows):
            var values = List[Optional[String]]()
            for col in range(ncols):
                if get_null(result_ptr, c_int(row), c_int(col)) != 0:
                    values.append(None)
                else:
                    var val_ptr = get_value(result_ptr, c_int(row), c_int(col))
                    if val_ptr == 0:
                        clear(result_ptr)
                        raise Error("PostgreSQL returned an invalid column value")
                    values.append(Optional[String](_read_cstring(val_ptr)))
            result_rows.append(values^)
        clear(result_ptr)
        return PgRows(names^, result_rows^)

    def execute(self, sql: String, params: List[String] = List[String]()) raises:
        """Execute trusted SQL and dispose of any returned rows."""
        _ = self.query(sql, params)


def open_postgres(conninfo: String) raises -> PgConnection:
    """Open a new connection; callers own it until it goes out of scope."""
    return PgConnection(conninfo)
