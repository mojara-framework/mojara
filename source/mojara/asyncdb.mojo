"""Bounded asynchronous SQL jobs for SQLite, MySQL, and PostgreSQL.

AsyncDbPool executes parameterized queries on dedicated database workers.
Handlers submit jobs without blocking and collect results from later requests
using opaque identifiers. This is not a coroutine-suspension API."""

from .platform import library_name
from std.ffi import OwnedDLHandle, c_int
from .config import DatabaseSettings


struct AsyncDbPool(Copyable):
    """Bounded connection-owning worker pool.

    A maximum of max_outstanding requests may be queued, running, or awaiting
    consumption. Completed results expire after 120 seconds. Pool copies share
    one refcounted native state. Last-owner destruction waits for workers.
    SQL must be developer-supplied; pass request data using bound params.
    """

    var _lib: Optional[OwnedDLHandle]
    var _handle: Int
    var driver: String

    def __init__(
        out self,
        config: DatabaseSettings,
        workers: Int = 4,
        max_outstanding: Int = 128,
    ) raises:
        """Create a bounded pool with dedicated background database connections."""
        self._lib = None
        self._handle = 0
        self.driver = config.driver.copy()
        self._lib = OwnedDLHandle(library_name("libmojara_asyncdb.so", "libmojara_asyncdb.dylib"))
        if workers < 1 or workers > 16:
            raise Error("Async database workers must be between 1 and 16")
        if max_outstanding < workers or max_outstanding > 512:
            raise Error(
                "Async database max_outstanding must be between workers and 512"
            )
        var fields = List[String]()
        var native_driver: Int
        if config.driver == "sqlite":
            native_driver = 1
            fields.append(config.sqlite_path.copy())
        elif config.driver == "postgres":
            native_driver = 2
            fields.append(config.postgres_dsn.copy())
        elif config.driver == "mysql":
            native_driver = 3
            fields.append(config.mysql_host.copy())
            fields.append(String(config.mysql_port))
            fields.append(config.mysql_user.copy())
            fields.append(config.mysql_password.copy())
            fields.append(config.mysql_database.copy())
        else:
            raise Error("Async DB driver must be mysql, postgres or sqlite")
        var config_bytes = List[UInt8]()
        for field in fields:
            if field.byte_length() == 0:
                raise Error("Async database connection settings cannot be empty")
            for i in range(field.byte_length()):
                var ch = field.as_bytes()[i]
                if ch == 0:
                    raise Error("Database connection settings cannot include NUL")
                config_bytes.append(ch)
            config_bytes.append(0)
        if len(config_bytes) > 8192:
            raise Error("Async database connection settings too long")
        var open_fn = self._lib.value().get_function[Int]("mj_asyncdb_open")
        self._handle = open_fn(
            c_int(native_driver),
            config_bytes.unsafe_ptr(),
            len(config_bytes),
            c_int(workers),
            c_int(max_outstanding),
        )
        if self._handle == 0:
            raise Error("Could not initialize async database worker pool")

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        # Copyable's constructor cannot raise in Mojo 1.2. If dlopen fails,
        # leave this reference invalid; a subsequent operation raises.
        self._lib = None
        self._handle = 0
        self.driver = copy.driver.copy()
        try:
            var lib = OwnedDLHandle(library_name("libmojara_asyncdb.so", "libmojara_asyncdb.dylib"))
            var retain = lib.get_function[c_int]("mj_asyncdb_retain")
            if retain(copy._handle) == 1:
                self._handle = copy._handle
                self._lib = lib^
        except:
            pass

    def __deinit__(deinit self):
        if self._handle != 0:
            try:
                var release = self._lib.value().get_function[NoneType](
                    "mj_asyncdb_release"
                )
                release(self._handle)
            except:
                pass

    def submit(
        self, sql: String, params: List[String] = List[String]()
    ) raises -> UInt64:
        """Submit SQL without waiting, returning an opaque job identifier.

        Submit runs no database I/O. A worker thread executes the SQL later.
        Raises on queue saturation (bounded backpressure).
        """
        if self._handle == 0 or not self._lib:
            raise Error("Async DB pool is closed")
        if sql.byte_length() == 0 or sql.byte_length() > 16384:
            raise Error("Async database SQL must contain 1-16384 bytes")
        if len(params) > 32:
            raise Error("Async database accepts at most 32 bound parameters")
        var sql_owned = sql.copy()
        for i in range(sql_owned.byte_length()):
            if sql_owned.as_bytes()[i] == 0:
                raise Error("Async database SQL contains NUL")
        var encoded = List[UInt8]()
        for param in params:
            for i in range(param.byte_length()):
                var c = param.as_bytes()[i]
                if c == 0:
                    raise Error("Async database parameters cannot contain NUL")
                encoded.append(c)
            encoded.append(0)
        if len(encoded) > 65536:
            raise Error("Async database parameters exceed 64 KiB")
        # Pass the List's typed pointer directly. Converting it to Int
        # discards borrow provenance and may permit temporary reuse in Mojo.
        var submit_fn = self._lib.value().get_function[UInt64]("mj_asyncdb_submit")
        var id = submit_fn(
            self._handle,
            sql_owned.as_c_string_span(),
            encoded.unsafe_ptr(),
            len(encoded),
            c_int(len(params)),
        )
        if id == 0:
            raise Error("Async database queue full or invalid request")
        return id

    def status(self, id: UInt64) raises -> Int:
        """0 pending, 1 completed, 2 failed, -1 unknown/expired."""
        if id == 0:
            raise Error("Invalid async database job ID")
        if self._handle == 0 or not self._lib:
            raise Error("Async database pool reference is closed")
        var call = self._lib.value().get_function[c_int]("mj_asyncdb_status")
        return Int(call(self._handle, id))

    def take(self, id: UInt64) raises -> Optional[String]:
        """Non-blocking read: None if pending, JSON result if complete.

        The completed job is consumed exactly once. Errors raise without
        disclosing SQL or connection secrets. Callers must not busy-loop.
        """
        if id == 0:
            raise Error("Invalid async database job ID")
        if self._handle == 0 or not self._lib:
            raise Error("Async database pool reference is closed")
        var call = self._lib.value().get_function[c_int]("mj_asyncdb_take")
        var size: UInt64 = 0
        var state = Int(call(self._handle, id, Int(0), 0, Pointer(to=size)))
        if state == 0:
            return None
        if state == -1:
            raise Error("Async database job is unknown or expired")
        if state == 2:
            raise Error("Async database query failed")
        if state != -2 or size > 262144:
            raise Error("Async database result could not be retrieved")
        var bytes = List[UInt8]()
        for _ in range(Int(size) + 1):
            bytes.append(0)
        var second_size: UInt64 = 0
        state = Int(
            call(
                self._handle,
                id,
                bytes.unsafe_ptr(),
                len(bytes),
                Pointer(to=second_size),
            )
        )
        if state != 1 or second_size != size:
            raise Error("Async database result changed while retrieving")
        var result = String(unsafe_from_utf8_ptr=bytes.unsafe_ptr())
        return Optional[String](result)

    def discard(self, id: UInt64) raises -> Bool:
        """Release a completed result without reading it; pending jobs are retained."""
        if self._handle == 0 or not self._lib:
            raise Error("Async database pool reference is closed")
        var call = self._lib.value().get_function[c_int]("mj_asyncdb_discard")
        var state = Int(call(self._handle, id))
        if state < 0:
            raise Error("Async database job not found")
        return state == 1


def open_async_database(
    config: DatabaseSettings,
    workers: Int = 4,
    max_outstanding: Int = 128,
) raises -> AsyncDbPool:
    """Create an async DB worker pool. Keep a copy in each registered handler."""
    return AsyncDbPool(config, workers=workers, max_outstanding=max_outstanding)
