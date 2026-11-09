"""Portable SQL execution and transaction control.

DbClient supports SQLite, MySQL, and PostgreSQL with bound values and
driver-specific parameter placeholders. Read-only pool factories are optional."""

from mojara.txpool import PooledDatabase, DbLease, DbResult


from sqlite import Database
from .database import open_sqlite
from .config import DatabaseSettings
from .postgres import PgConnection, PgRows
from .mysql import MysqlConnection
from .orm import quoted_identifier
from .sqlite_pool import SqliteReadPool
from .network_pool import NetworkReadPool


struct DbClient(Movable):
    """Owned database connection that exposes portable operations for SQLite, PostgreSQL and MySQL."""

    var driver: String
    var _sqlite: Optional[Database]
    var _postgres: Optional[PgConnection]
    var _mysql: Optional[MysqlConnection]
    var in_transaction: Bool

    def __init__(out self, config: DatabaseSettings) raises:
        """Open and own a connection for the configured database driver."""
        self.driver = config.driver.copy()
        self._sqlite = None
        self._postgres = None
        self._mysql = None
        self.in_transaction = False
        if config.driver == "sqlite":
            self._sqlite = open_sqlite(config.sqlite_path)
        elif config.driver == "postgres":
            self._postgres = PgConnection(config.postgres_dsn)
        elif config.driver == "mysql":
            self._mysql = MysqlConnection(
                config.mysql_host,
                config.mysql_port,
                config.mysql_user,
                config.mysql_password,
                config.mysql_database,
            )
        else:
            raise Error("Unsupported database adapter")

    def execute(self, sql: String, params: List[String] = List[String]()) raises:
        """Execute trusted SQL with bound values and return any affected-row count."""
        if self.driver == "postgres":
            self._postgres.value().execute(sql, params)
            return
        if self.driver == "mysql":
            self._mysql.value().execute(sql, params)
            return
        ref db = self._sqlite.value()
        var stmt = db.prepare(sql)
        for i in range(len(params)):
            stmt.bind_text(i + 1, params[i])
        while Bool(stmt.step()):
            pass

    def query_text(
        self, sql: String, params: List[String] = List[String]()
    ) raises -> PgRows:
        """Retrieve materialized UTF-8 text and NULL SQL results."""
        if self.driver == "postgres":
            return self._postgres.value().query(sql, params)
        if self.driver == "mysql":
            return self._mysql.value().query(sql, params)
        ref db = self._sqlite.value()
        var stmt = db.prepare(sql)
        for i in range(len(params)):
            stmt.bind_text(i + 1, params[i])
        var columns = List[String]()
        var output = List[List[Optional[String]]]()
        var initialized_columns = False
        while True:
            var found = stmt.step()
            if not Bool(found):
                break
            ref row = found.value()
            if not initialized_columns:
                for column in range(row.num_cols()):
                    columns.append("column_" + String(column))
                initialized_columns = True
            var values = List[Optional[String]]()
            for column in range(row.num_cols()):
                if row.is_null(column):
                    values.append(None)
                else:
                    values.append(Optional[String](row.text_val(column)))
            output.append(values^)
        return PgRows(columns^, output^)

    def placeholder(self, index: Int) raises -> String:
        """Return a native bound placeholder; 1-indexed positions."""
        if index < 1 or index > 256:
            raise Error("Invalid bind parameter number")
        if self.driver == "postgres":
            return "$" + String(index)
        return "?"

    def identifier(self, value: String) raises -> String:
        """Conservative identifier quoting across all three engines."""
        var quoted = quoted_identifier(value)
        if self.driver == "mysql":
            return "`" + value + "`"
        return quoted

    def begin(mut self) raises:
        """Begin a transaction on the owned connection."""
        if self.in_transaction:
            raise Error("Nested transactions are not supported")
        if self.driver == "sqlite":
            self.execute("BEGIN")
        elif self.driver == "postgres":
            self.execute("BEGIN")
        else:
            self._mysql.value().transaction(1)
        self.in_transaction = True

    def commit(mut self) raises:
        """Commit the current transaction."""
        if not self.in_transaction:
            raise Error("No active transaction")
        if self.driver == "mysql":
            self._mysql.value().transaction(2)
        else:
            self.execute("COMMIT")
        self.in_transaction = False

    def rollback(mut self) raises:
        """Roll back the current transaction."""
        if not self.in_transaction:
            raise Error("No active transaction")
        if self.driver == "mysql":
            self._mysql.value().transaction(3)
        else:
            self.execute("ROLLBACK")
        self.in_transaction = False

    def savepoint(self, name: String) raises:
        """Create a named savepoint within the current transaction.

        The validated identifier is developer-controlled, not a SQL expression.
        Explicit savepoints do not change begin() nesting semantics.
        """
        if not self.in_transaction:
            raise Error("Savepoints require an active transaction")
        var safe_name = quoted_identifier(name)
        if self.driver == "mysql":
            safe_name = "`" + name + "`"
        self.execute("SAVEPOINT " + safe_name)

    def rollback_to(self, name: String) raises:
        """Undo changes since a savepoint while keeping the transaction open."""
        if not self.in_transaction:
            raise Error("Savepoints require an active transaction")
        var safe_name = quoted_identifier(name)
        if self.driver == "mysql":
            safe_name = "`" + name + "`"
        self.execute("ROLLBACK TO SAVEPOINT " + safe_name)

    def release_savepoint(self, name: String) raises:
        """Release an existing savepoint without committing the transaction."""
        if not self.in_transaction:
            raise Error("Savepoints require an active transaction")
        var safe_name = quoted_identifier(name)
        if self.driver == "mysql":
            safe_name = "`" + name + "`"
        self.execute("RELEASE SAVEPOINT " + safe_name)


def open_database(config: DatabaseSettings) raises -> DbClient:
    """Open a database client using validated connection settings."""
    return DbClient(config)


def open_read_pool(
    config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
) raises -> SqliteReadPool:
    """Opt-in bounded, read-only SQLite pool for single-value parameterized reads.

    This API complements DbClient; it does not share mutable DbClient or
    transaction state and is intentionally not available for MySQL/PostgreSQL.
    The owner must stop issuing queries and join user threads before cleanup.
    """
    if config.driver != "sqlite":
        raise Error("Read-only connection pooling currently supports SQLite only")
    return SqliteReadPool(config.sqlite_path, connections, wait_ms)


def open_network_read_pool(
    config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
) raises -> NetworkReadPool:
    """Opt-in, bounded PostgreSQL/MySQL read-only lookup pool.

    Does not share a DbClient connection or transaction state. Use an
    ordinary DbClient for writes and multi-statement transactions.
    """
    return NetworkReadPool(config, connections, wait_ms)
