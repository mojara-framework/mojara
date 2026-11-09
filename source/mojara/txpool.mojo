"""Pooled transactions and thread-affine connection leases.

PooledDatabase owns native connections, DbLease controls one checked-out
connection, and DbResult holds detached results. Release each lease on its
acquiring thread and keep the pool alive until all leases return."""

from .platform import library_name
from std.ffi import OwnedDLHandle, c_char, c_int, c_uint, c_size_t


# Native pointer types are private to the transaction implementation.


struct DbResult:
    """Owns a materialized query result, independent of its connection lease."""

    var _lib: OwnedDLHandle
    var _ptr: Pointer[NoneType, MutUntrackedOrigin]

    def __init__(
        out self,
        pool: Pointer[NoneType, MutUntrackedOrigin],
        token: UInt64,
        var sql: String,
    ) raises:
        """Execute a query on a pool lease and own the materialized result."""
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var result: Optional[Pointer[NoneType, MutUntrackedOrigin]] = None
        var call = self._lib.get_function[c_int]("mjx_query0")
        var rc = call(pool, token, sql.as_c_string_span(), Pointer(to=result))
        if rc != 0:
            raise Error(t"Mojara query failed (native code {rc})")
        if not result:
            raise Error("Native database query returned no result")
        self._ptr = result.value()

    def __init__(
        out self,
        pool: Pointer[NoneType, MutUntrackedOrigin],
        token: UInt64,
        var sql: String,
        var a: String,
    ) raises:
        """Execute a query on a pool lease and own the materialized result."""
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var result: Optional[Pointer[NoneType, MutUntrackedOrigin]] = None
        var call = self._lib.get_function[c_int]("mjx_query1")
        var rc = call(
            pool,
            token,
            sql.as_c_string_span(),
            a.as_c_string_span(),
            Pointer(to=result),
        )
        if rc != 0:
            raise Error(t"Mojara parameterized query failed (native code {rc})")
        if not result:
            raise Error("Native database query returned no result")
        self._ptr = result.value()

    def __init__(
        out self,
        pool: Pointer[NoneType, MutUntrackedOrigin],
        token: UInt64,
        var sql: String,
        var a: String,
        var b: String,
    ) raises:
        """Execute a query on a pool lease and own the materialized result."""
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var result: Optional[Pointer[NoneType, MutUntrackedOrigin]] = None
        var call = self._lib.get_function[c_int]("mjx_query2")
        var rc = call(
            pool,
            token,
            sql.as_c_string_span(),
            a.as_c_string_span(),
            b.as_c_string_span(),
            Pointer(to=result),
        )
        if rc != 0:
            raise Error(t"Mojara parameterized query failed (native code {rc})")
        if not result:
            raise Error("Native database query returned no result")
        self._ptr = result.value()

    def __init__(
        out self,
        pool: Pointer[NoneType, MutUntrackedOrigin],
        token: UInt64,
        var sql: String,
        var a: String,
        var b: String,
        var c: String,
    ) raises:
        """Execute a query on a pool lease and own the materialized result."""
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var result: Optional[Pointer[NoneType, MutUntrackedOrigin]] = None
        var call = self._lib.get_function[c_int]("mjx_query3")
        var rc = call(
            pool,
            token,
            sql.as_c_string_span(),
            a.as_c_string_span(),
            b.as_c_string_span(),
            c.as_c_string_span(),
            Pointer(to=result),
        )
        if rc != 0:
            raise Error(t"Mojara parameterized query failed (native code {rc})")
        if not result:
            raise Error("Native database query returned no result")
        self._ptr = result.value()

    def __deinit__(deinit self):
        self._lib.call["mjx_result_free"](self._ptr)

    def rows(self) -> Int:
        """Return the number of query-result rows."""
        return Int(self._lib.call["mjx_rows", c_size_t](self._ptr))

    def columns(self) -> Int:
        """Return the number of query-result columns."""
        return Int(self._lib.call["mjx_columns", c_size_t](self._ptr))

    def affected(self) -> UInt64:
        """Report the affected-row count when supported."""
        return self._lib.call["mjx_affected", UInt64](self._ptr)

    def is_null(self, row: Int, col: Int) raises -> Bool:
        """Test whether the selected SQL cell is NULL."""
        var code = self._lib.call["mjx_is_null", c_int](
            self._ptr, c_size_t(row), c_size_t(col)
        )
        if code < 0:
            raise Error("Invalid result coordinates")
        return code == 1

    def cell(self, row: Int, col: Int) raises -> String:
        """Read a text cell from the materialized result."""
        if self.is_null(row, col):
            raise Error("SQL NULL: check is_null() before cell()")
        var ptr = self._lib.call[
            "mjx_cell", Optional[Pointer[c_char, MutUntrackedOrigin]]
        ](self._ptr, c_size_t(row), c_size_t(col))
        if not ptr:
            raise Error("Invalid result cell")
        return String(unsafe_from_utf8_ptr=ptr.value())

    def column_name(self, col: Int) raises -> String:
        """Return the result column name at a valid index."""
        if col < 0:
            raise Error("Invalid column")
        var ptr = self._lib.call[
            "mjx_column_name", Optional[Pointer[c_char, MutUntrackedOrigin]]
        ](self._ptr, c_size_t(col))
        if not ptr:
            raise Error("Invalid column")
        return String(unsafe_from_utf8_ptr=ptr.value())


struct DbLease:
    """A thread-affine, move-only transaction lease with rollback on destruction."""

    var _lib: OwnedDLHandle
    var _pool: Pointer[NoneType, MutUntrackedOrigin]
    var _token: UInt64

    def __init__(
        out self,
        pool: Pointer[NoneType, MutUntrackedOrigin],
        timeout_ms: Int,
    ) raises:
        """Bind a checked-out connection to its pool and acquiring thread."""
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        self._pool = pool
        self._token = 0
        var token: UInt64 = 0
        var acquire = self._lib.get_function[c_int]("mjx_acquire")
        var rc = acquire(pool, c_int(timeout_ms), Pointer(to=token))
        if rc != 0:
            raise Error(t"Mojara pool acquire failed (native code {rc})")
        self._token = token

    def __deinit__(deinit self):
        if self._token != 0:
            _ = self._lib.call["mjx_release", c_int](self._pool, self._token)

    def release(mut self) raises:
        """Return the connection to the pool; roll back unfinished work."""
        if self._token == 0:
            raise Error("Database lease already released")
        var rc = self._lib.call["mjx_release", c_int](self._pool, self._token)
        if rc != 0:
            raise Error(t"Mojara release failed (native code {rc})")
        self._token = 0

    def begin(self) raises:
        """Begin a transaction using the checked-out connection."""
        if self._token == 0:
            raise Error("Database lease already released")
        var rc = self._lib.call["mjx_begin", c_int](self._pool, self._token)
        if rc != 0:
            raise Error(t"Mojara BEGIN failed (native code {rc})")

    def commit(self) raises:
        """Commit the lease transaction."""
        if self._token == 0:
            raise Error("Database lease already released")
        var rc = self._lib.call["mjx_commit", c_int](self._pool, self._token)
        if rc != 0:
            raise Error(t"Mojara COMMIT failed (native code {rc})")

    def rollback(self) raises:
        """Roll back the lease transaction."""
        if self._token == 0:
            raise Error("Database lease already released")
        var rc = self._lib.call["mjx_rollback", c_int](self._pool, self._token)
        if rc != 0:
            raise Error(t"Mojara ROLLBACK failed (native code {rc})")

    def query(self, sql: String) raises -> DbResult:
        """Execute developer-controlled SQL without bound values."""
        if self._token == 0:
            raise Error("Database lease already released")
        return DbResult(self._pool, self._token, sql)

    def query1(self, sql: String, a: String) raises -> DbResult:
        """Execute SQL with one bound text parameter."""
        if self._token == 0:
            raise Error("Database lease already released")
        return DbResult(self._pool, self._token, sql, a)

    def query2(self, sql: String, a: String, b: String) raises -> DbResult:
        """Execute SQL with two bound text parameters."""
        if self._token == 0:
            raise Error("Database lease already released")
        return DbResult(self._pool, self._token, sql, a, b)

    def query3(
        self,
        sql: String,
        a: String,
        b: String,
        c: String,
    ) raises -> DbResult:
        """Execute SQL with three bound text parameters."""
        if self._token == 0:
            raise Error("Database lease already released")
        return DbResult(self._pool, self._token, sql, a, b, c)


struct PooledDatabase:
    """Owns a bounded PostgreSQL or MySQL connection pool.

    Keep it alive until all DbLease values have been released. A failed close
    leaves the pool open rather than risking use-after-free.
    """

    var _lib: OwnedDLHandle
    var _pool: Optional[Pointer[NoneType, MutUntrackedOrigin]]

    def __init__(out self, var postgres_dsn: String, capacity: Int = 4) raises:
        """Initialize a bounded native database transaction pool."""
        if capacity < 1 or capacity > 16:
            raise Error("Mojara pool size must be between 1 and 16")
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var create = self._lib.get_function[
            Optional[Pointer[NoneType, MutUntrackedOrigin]]
        ]("mjx_postgres")
        self._pool = create(postgres_dsn.as_c_string_span(), c_uint(capacity))
        if not self._pool:
            raise Error("Could not initialize PostgreSQL pool")

    def __init__(
        out self,
        var mysql_host: String,
        mysql_port: Int,
        var mysql_user: String,
        var mysql_password: String,
        var mysql_database: String,
        capacity: Int = 4,
    ) raises:
        """Initialize a bounded native database transaction pool."""
        if capacity < 1 or capacity > 16:
            raise Error("Mojara pool size must be between 1 and 16")
        if mysql_port < 1 or mysql_port > 65535:
            raise Error("Invalid MySQL TCP port")
        self._lib = OwnedDLHandle(
            library_name("extensions/txpool_v0131/build/native/libmojara_txpool_mojo.so", "extensions/txpool_v0131/build/native/libmojara_txpool_mojo.dylib")
        )
        var create = self._lib.get_function[
            Optional[Pointer[NoneType, MutUntrackedOrigin]]
        ]("mjx_mysql")
        self._pool = create(
            mysql_host.as_c_string_span(),
            c_uint(mysql_port),
            mysql_user.as_c_string_span(),
            mysql_password.as_c_string_span(),
            mysql_database.as_c_string_span(),
            c_uint(capacity),
        )
        if not self._pool:
            raise Error("Could not initialize MySQL pool")

    def __deinit__(deinit self):
        # Native close refuses BUSY, so outstanding leases cannot be freed.
        if self._pool:
            _ = self._lib.call["mjx_close", c_int](self._pool.value())

    def acquire(self, timeout_ms: Int = 3000) raises -> DbLease:
        """Borrow a connection, waiting up to the configured timeout."""
        if timeout_ms < 0:
            raise Error("Negative connection acquire timeout")
        if not self._pool:
            raise Error("Database pool is closed")
        return DbLease(self._pool.value(), timeout_ms)

    def capacity(self) raises -> Int:
        """Return the configured connection capacity."""
        if not self._pool:
            raise Error("Database pool is closed")
        return Int(self._lib.call["mjx_capacity", c_uint](self._pool.value()))

    def active_leases(self) raises -> Int:
        """Return the number of currently checked-out connections."""
        if not self._pool:
            raise Error("Database pool is closed")
        return Int(self._lib.call["mjx_active", c_uint](self._pool.value()))

    def close(mut self) raises:
        """Close the pool after every lease has returned."""
        if not self._pool:
            raise Error("Database pool already closed")
        var rc = self._lib.call["mjx_close", c_int](self._pool.value())
        if rc != 0:
            raise Error(t"Cannot close database pool (native code {rc})")
        self._pool = None
