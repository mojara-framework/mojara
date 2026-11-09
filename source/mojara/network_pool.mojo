"""Bounded read-only connection pools for MySQL and PostgreSQL.

Workers acquire exclusive native connections for single-column lookups.
For writes or multi-statement transactions, use the database client."""
from std.ffi import OwnedDLHandle, c_int
from .config import DatabaseSettings


@fieldwise_init
struct NetworkPoolStats(Copyable):
    """Snapshot of read-pool capacity, contention, queries and error counters."""

    var capacity: Int
    var in_use: Int
    var waiting: Int
    var peak_in_use: Int
    var closing: Bool
    var completed_queries: UInt64
    var wait_events: UInt64
    var wait_timeouts: UInt64
    var failed_queries: UInt64


struct NetworkReadPool(Movable):
    """Bounded PostgreSQL or MySQL read pool with connection leases and wait timeouts."""

    var _handle: Int
    var driver: String

    def __init__(
        out self, config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
    ) raises:
        """Initialize a bounded native PostgreSQL or MySQL read pool."""
        self._handle = 0
        self.driver = config.driver.copy()
        if config.driver != "postgres" and config.driver != "mysql":
            raise Error("Network read pooling requires PostgreSQL or MySQL")
        if connections < 1 or connections > 16 or wait_ms < 1 or wait_ms > 30000:
            raise Error("Invalid network read pool limits")
        var config_fields = List[String]()
        var native_driver = 1
        if config.driver == "postgres":
            config_fields.append(config.postgres_dsn.copy())
        else:
            native_driver = 2
            config_fields.append(config.mysql_host.copy())
            config_fields.append(String(config.mysql_port))
            config_fields.append(config.mysql_user.copy())
            config_fields.append(config.mysql_password.copy())
            config_fields.append(config.mysql_database.copy())
        var packed = List[UInt8]()
        for i in range(len(config_fields)):
            var field = config_fields[i].copy()
            for j in range(field.byte_length()):
                var byte = field.as_bytes()[j]
                if byte == 0:
                    raise Error("Database configuration contains a NUL byte")
                packed.append(byte)
            packed.append(0)
        if len(packed) > 8192:
            raise Error("Database pool configuration exceeds native limit")
        var lib = OwnedDLHandle("libmojara_networkpool.so")
        var open_fn = lib.get_function[Int]("mj_np_open")
        self._handle = open_fn(
            c_int(native_driver),
            packed.unsafe_ptr(),
            len(packed),
            c_int(connections),
            c_int(wait_ms),
        )
        if self._handle == 0:
            raise Error("Could not open native database read pool")

    def __deinit__(deinit self):
        if self._handle != 0:
            try:
                var lib = OwnedDLHandle("libmojara_networkpool.so")
                var close_fn = lib.get_function[NoneType]("mj_np_close")
                close_fn(self._handle)
            except:
                pass

    def begin_shutdown(self) raises:
        """Irreversibly stop accepting new leases; active operations finish."""
        if self._handle == 0:
            raise Error("Database read pool is closed")
        var lib = OwnedDLHandle("libmojara_networkpool.so")
        var shutdown_fn = lib.get_function[c_int]("mj_np_begin_shutdown")
        if shutdown_fn(self._handle) != 1:
            raise Error("Database pool shutdown failed")

    def stats(self) raises -> NetworkPoolStats:
        """Return capacity, active lease, wait, and failure counters."""
        if self._handle == 0:
            raise Error("Database read pool is closed")
        var totals = List[UInt64]()
        for _ in range(9):
            totals.append(0)
        var lib = OwnedDLHandle("libmojara_networkpool.so")
        var stats_fn = lib.get_function[c_int]("mj_np_stats")
        if stats_fn(self._handle, totals.unsafe_ptr(), c_int(len(totals))) != 1:
            raise Error("Database read pool statistics unavailable")
        return NetworkPoolStats(
            capacity=Int(totals[0]),
            in_use=Int(totals[1]),
            waiting=Int(totals[2]),
            peak_in_use=Int(totals[3]),
            closing=totals[4] != 0,
            completed_queries=totals[5],
            wait_events=totals[6],
            wait_timeouts=totals[7],
            failed_queries=totals[8],
        )

    def query_one_text(self, sql: String, param: String) raises -> Optional[String]:
        """Return one text column from the first row, or None for NULL/no row.

        SQL must be a developer-controlled single SELECT with one placeholder:
        PostgreSQL uses $1 and MySQL uses ?. The parameter is bound safely.
        """
        if self._handle == 0:
            raise Error("Database read pool is closed")
        if sql.byte_length() == 0 or sql.byte_length() > 16384:
            raise Error("Database pool SQL exceeds limit")
        if param.byte_length() > 65536:
            raise Error("Database pool parameter exceeds limit")
        var sql_owned = sql.copy()
        var param_owned = param.copy()
        for i in range(sql_owned.byte_length()):
            if sql_owned.as_bytes()[i] == 0:
                raise Error("Database pool SQL contains NUL byte")
        for i in range(param_owned.byte_length()):
            if param_owned.as_bytes()[i] == 0:
                raise Error("Database pool parameter contains NUL byte")
        var bytes = List[UInt8]()
        for _ in range(8192):
            bytes.append(0)
        var lib = OwnedDLHandle("libmojara_networkpool.so")
        var query_fn = lib.get_function[c_int]("mj_np_query_one_text")
        var status = query_fn(
            self._handle,
            sql_owned.as_c_string_span(),
            param_owned.as_c_string_span(),
            bytes.unsafe_ptr(),
            c_int(len(bytes)),
        )
        if status == 0 or status == 2:
            return None
        if status != 1:
            raise Error(
                "Database pooled SELECT failed (native code "
                + String(Int(status))
                + ")"
            )
        var address = Int(bytes.unsafe_ptr())
        var result = String(
            unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
                unsafe_from_address=address
            )
        )
        # Native memory stays owned until the copy has completed.
        if len(bytes) != 8192:
            raise Error("Pooled query result buffer was changed")
        return Optional[String](result)
