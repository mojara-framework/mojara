"""Native MySQL connections and prepared SQL statements.

Each MysqlConnection owns a native client handle. Bind user values using
prepared parameters, and do not execute concurrent work on one connection."""

from std.ffi import OwnedDLHandle, c_int
from .postgres import PgRows


def _mysql_cstring(address: Int) -> String:
    return String(
        unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
            unsafe_from_address=address
        )
    )


def _validate_mysql_config_text(value: String) raises:
    if value.byte_length() > 4096:
        raise Error("MySQL connection setting is too large")
    for i in range(value.byte_length()):
        if value.as_bytes()[i] == 0:
            raise Error("MySQL connection setting contains a NUL byte")


struct MysqlConnection(Movable):
    var _handle: Int
    var _bridge: OwnedDLHandle

    def __init__(
        out self,
        host: String,
        port: Int,
        user: String,
        password: String,
        database: String,
    ) raises:
        """Open one MySQL connection and retain its native client library."""
        self._handle = 0
        # Keep the client library open for the lifetime of the connection.
        self._bridge = OwnedDLHandle("libmojara_mysql.so")
        if port < 1 or port > 65535:
            raise Error("Invalid MySQL TCP port")
        if (
            host.byte_length() == 0
            or user.byte_length() == 0
            or database.byte_length() == 0
        ):
            raise Error("MySQL host, username and database are required")
        _validate_mysql_config_text(host)
        _validate_mysql_config_text(user)
        _validate_mysql_config_text(password)
        _validate_mysql_config_text(database)
        var open_connection = self._bridge.get_function[Int]("mj_mysql_open")
        var host_buf = host.copy()
        var user_buf = user.copy()
        var pass_buf = password.copy()
        var db_buf = database.copy()
        var ptr = open_connection(
            host_buf.as_c_string_span(),
            c_int(port),
            user_buf.as_c_string_span(),
            pass_buf.as_c_string_span(),
            db_buf.as_c_string_span(),
        )
        if ptr == 0:
            raise Error("MySQL connection failed; check server and credentials")
        self._handle = ptr

    def __deinit__(deinit self):
        if self._handle != 0:
            try:
                var close_connection = self._bridge.get_function[NoneType](
                    "mj_mysql_close"
                )
                close_connection(self._handle)
            except:
                pass

    def query(
        self, sql: String, params: List[String] = List[String]()
    ) raises -> PgRows:
        """Execute a prepared query and detach text or NULL results."""
        if sql.byte_length() == 0 or sql.byte_length() > 1048576:
            raise Error("MySQL statement must contain 1-1048576 bytes")
        if len(params) > 256:
            raise Error("Too many MySQL parameters")
        for i in range(sql.byte_length()):
            if sql.as_bytes()[i] == 0:
                raise Error("MySQL SQL text cannot contain NUL bytes")
        var sql_buf = sql.copy()
        # Keep all UTF-8 parameters in a single allocation until the
        # synchronous native bridge returns.
        var param_bytes = List[UInt8]()
        for i in range(len(params)):
            var param = params[i].copy()
            for j in range(param.byte_length()):
                var byte = param.as_bytes()[j]
                if byte == 0:
                    raise Error("MySQL text parameters cannot contain NUL bytes")
                param_bytes.append(byte)
            param_bytes.append(0)
        # A single packed byte buffer crosses the FFI boundary. Native C
        # reconstructs the pointer array; no Mojo List[Int] pointer escapes.
        if len(param_bytes) > 67108864:
            raise Error("MySQL packed parameters exceed the size limit")
        var packed_ptr = Int(0)
        if len(params) > 0:
            packed_ptr = Int(param_bytes.unsafe_ptr())
        var native_flat_query = self._bridge.get_function[Int]("mj_mysql_query_flat")
        var result = native_flat_query(
            self._handle,
            sql_buf.as_c_string_span(),
            packed_ptr,
            len(param_bytes),
            c_int(len(params)),
        )
        # Force the backing allocation to remain live across the FFI call.
        if len(params) > 0 and param_bytes[len(param_bytes) - 1] != 0:
            raise Error("MySQL parameter buffer sentinel was lost")
        if result == 0:
            var failure_stage = self._bridge.get_function[c_int](
                "mj_mysql_failure_stage"
            )
            var failure_code = self._bridge.get_function[c_int]("mj_mysql_failure_code")
            var failure_detail = self._bridge.get_function[Int](
                "mj_mysql_failure_detail"
            )
            var detail = _mysql_cstring(failure_detail())
            raise Error(
                "MySQL prepared statement failed (stage "
                + String(Int(failure_stage()))
                + ", native code "
                + String(Int(failure_code()))
                + ", detail: "
                + detail
                + ")"
            )
        var rows_fn = self._bridge.get_function[Int]("mj_mysql_rows")
        var cols_fn = self._bridge.get_function[Int]("mj_mysql_cols")
        var col_fn = self._bridge.get_function[Int]("mj_mysql_col")
        var null_fn = self._bridge.get_function[c_int]("mj_mysql_is_null")
        var cell_fn = self._bridge.get_function[Int]("mj_mysql_cell")
        var free_fn = self._bridge.get_function[NoneType]("mj_mysql_free")
        var nrows = rows_fn(result)
        var ncols = cols_fn(result)
        var columns = List[String]()
        var values = List[List[Optional[String]]]()
        for col in range(ncols):
            var addr = col_fn(result, col)
            if addr == 0:
                free_fn(result)
                raise Error("MySQL returned invalid column name")
            columns.append(_mysql_cstring(addr))
        for row in range(nrows):
            var fields = List[Optional[String]]()
            for col in range(ncols):
                if null_fn(result, row, col) != 0:
                    fields.append(None)
                else:
                    var addr = cell_fn(result, row, col)
                    if addr == 0:
                        free_fn(result)
                        raise Error("MySQL returned invalid cell")
                    fields.append(Optional[String](_mysql_cstring(addr)))
            values.append(fields^)
        free_fn(result)
        return PgRows(columns^, values^)

    def execute(self, sql: String, params: List[String] = List[String]()) raises:
        """Execute prepared SQL with bound parameter values."""
        _ = self.query(sql, params)

    def transaction(self, action: Int) raises:
        """1 = begin, 2 = commit, 3 = rollback (native Connector/C API)."""
        var control = self._bridge.get_function[c_int]("mj_mysql_tx")
        if control(self._handle, c_int(action)) != 1:
            raise Error("MySQL transaction operation failed")
