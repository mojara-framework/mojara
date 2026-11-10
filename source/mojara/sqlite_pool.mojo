"""Bounded read-only SQLite connection pooling.

SqliteReadPool owns native connections to an existing database file, exposes
read-only parameterized lookups and reports lease utilization."""
from .platform import library_name
from std.ffi import OwnedDLHandle, c_int


def _text_from_c_address(address: Int) -> String:
    return String(
        unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
            unsafe_from_address=address
        )
    )


@fieldwise_init
struct SqlitePoolStats(Copyable):
    """Atomic snapshot under the native pool mutex, valid until close."""

    var capacity: Int
    var in_use: Int
    var waiting: Int
    var peak_in_use: Int
    var closing: Bool
    var completed_queries: UInt64
    var wait_events: UInt64
    var wait_timeouts: UInt64


struct SqliteReadPool(Movable):
    """Bounded, file-backed SQLite read pool with timed connection acquisition."""

    var _handle: Int

    def __init__(
        out self, path: String, connections: Int = 4, wait_ms: Int = 3000
    ) raises:
        """Open bounded read-only connections to an existing SQLite file."""
        self._handle = 0
        if path.byte_length() == 0 or path == ":memory:":
            raise Error("SQLite read pool requires an existing file-backed database")
        if path.byte_length() > 4096 or connections < 1 or connections > 32:
            raise Error("Invalid SQLite read pool configuration")
        if wait_ms < 1 or wait_ms > 30000:
            raise Error("SQLite pool wait timeout must be 1..30000 milliseconds")
        var owned = path.copy()
        var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
        var open_pool = lib.get_function[Int]("mj_sp_open")
        self._handle = open_pool(
            owned.as_c_string_span(), c_int(connections), c_int(wait_ms)
        )
        if self._handle == 0:
            raise Error("Could not open the SQLite read pool")

    def __deinit__(deinit self):
        if self._handle != 0:
            try:
                var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
                var close_pool = lib.get_function[NoneType]("mj_sp_close")
                close_pool(self._handle)
            except:
                pass

    def begin_shutdown(self) raises:
        """Prevent new leases. Existing queries can finish before pool cleanup."""
        if self._handle == 0:
            raise Error("SQLite read pool is already closed")
        var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
        var shutdown_fn = lib.get_function[c_int]("mj_sp_begin_shutdown")
        if shutdown_fn(self._handle) != 1:
            raise Error("Could not begin SQLite read pool shutdown")

    def stats(self) raises -> SqlitePoolStats:
        """Read pool occupancy, contention and lifetime-query statistics."""
        if self._handle == 0:
            raise Error("SQLite read pool is already closed")
        var scalar = List[Int32]()
        for _ in range(5):
            scalar.append(0)
        var totals = List[UInt64]()
        for _ in range(3):
            totals.append(0)
        var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
        var stats_fn = lib.get_function[c_int]("mj_sp_stats_extended")
        var ok = stats_fn(
            self._handle,
            Int(scalar.unsafe_ptr()),
            Int(scalar.unsafe_ptr()) + 4,
            Int(scalar.unsafe_ptr()) + 8,
            Int(scalar.unsafe_ptr()) + 12,
            Int(scalar.unsafe_ptr()) + 16,
            Int(totals.unsafe_ptr()),
            Int(totals.unsafe_ptr()) + 8,
            Int(totals.unsafe_ptr()) + 16,
        )
        if ok != 1 or len(scalar) != 5 or len(totals) != 3:
            raise Error("SQLite read pool statistics unavailable")
        return SqlitePoolStats(
            capacity=Int(scalar[0]),
            in_use=Int(scalar[1]),
            waiting=Int(scalar[2]),
            peak_in_use=Int(scalar[3]),
            closing=scalar[4] != 0,
            completed_queries=totals[0],
            wait_events=totals[1],
            wait_timeouts=totals[2],
        )

    def query_one_text(self, sql: String, param: String) raises -> Optional[String]:
        """Return first TEXT field; NULL/no row becomes None. Read only."""
        if self._handle == 0:
            raise Error("SQLite read pool is already closed")
        if sql.byte_length() == 0 or sql.byte_length() > 16384:
            raise Error("SQLite pool query exceeds SQL size limit")
        if param.byte_length() > 65536:
            raise Error("SQLite pool parameter exceeds size limit")
        var sql_owned = sql.copy()
        var param_owned = param.copy()
        var buffer = List[UInt8]()
        for _ in range(8192):
            buffer.append(0)
        var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
        var query_fn = lib.get_function[c_int]("mj_sp_query_one_text")
        var result = query_fn(
            self._handle,
            sql_owned.as_c_string_span(),
            param_owned.as_c_string_span(),
            Int(buffer.unsafe_ptr()),
            c_int(len(buffer)),
        )
        if result == 0 or result == 2:
            return None
        if result != 1:
            raise Error(
                "SQLite read pool query failed (native code "
                + String(Int(result))
                + ")"
            )
        var address = Int(buffer.unsafe_ptr())
        var value = _text_from_c_address(address)
        # Keep native output allocation live during the String copy.
        if len(buffer) != 8192:
            raise Error("SQLite pool output buffer changed unexpectedly")
        return Optional[String](value)


def pooled_benchmark_lookup(path: String, connections: Int = 4) raises -> String:
    """Benchmark-only process-lifetime reuse; never accepts paths from requests."""
    if path.byte_length() == 0 or path.byte_length() > 4096:
        raise Error("Invalid benchmark SQLite pool path")
    var owned = path.copy()
    var sql = String("SELECT name FROM mojara_benchmark_items WHERE id = ?")
    var bound = String("1")
    var bytes = List[UInt8]()
    for _ in range(256):
        bytes.append(0)
    var lib = OwnedDLHandle(library_name("libmojara_sqlitepool.so", "libmojara_sqlitepool.dylib"))
    var fn_query = lib.get_function[c_int]("mj_sp_benchmark_lookup")
    var status = fn_query(
        owned.as_c_string_span(),
        c_int(connections),
        sql.as_c_string_span(),
        bound.as_c_string_span(),
        Int(bytes.unsafe_ptr()),
        c_int(len(bytes)),
    )
    if status != 1:
        raise Error(
            "Pooled benchmark lookup failed (native code " + String(Int(status)) + ")"
        )
    var value = _text_from_c_address(Int(bytes.unsafe_ptr()))
    if len(bytes) != 256:
        raise Error("SQLite pool output buffer changed unexpectedly")
    return value
