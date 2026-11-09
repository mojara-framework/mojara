"""Portable, additive schemas and versioned manual SQL migrations.

Table and Column define SQLite, MySQL and PostgreSQL structures. Schema.plan
previews supported changes; Schema.sync applies them. Use manual SQL for
destructive or constraint-changing alterations."""

from mojara.dbclient import DbClient
from mojara.orm import quoted_identifier
from std.pathlib import Path


struct Column(Copyable):
    """Portable SQL column definition with key, nullability, type and foreign-reference constraints."""

    var name: String
    var kind: String
    var width: Int
    var nullable: Bool
    var unique: Bool
    var primary: Bool
    var generated: Bool
    var foreign_table: String
    var foreign_column: String
    var delete_action: String

    def __init__(
        out self,
        name: String,
        kind: String,
        width: Int = 0,
        nullable: Bool = True,
        unique: Bool = False,
        primary: Bool = False,
        generated: Bool = False,
        foreign_table: String = "",
        foreign_column: String = "",
        delete_action: String = "RESTRICT",
    ) raises:
        """Describe a typed SQL column and its portable constraints."""
        _ = quoted_identifier(name)
        if (
            kind != "id"
            and kind != "integer"
            and kind != "bigint"
            and kind != "string"
            and kind != "text"
            and kind != "boolean"
            and kind != "timestamp"
        ):
            raise Error("Unsupported column kind: " + kind)
        if kind == "string" and (width < 1 or width > 16383):
            raise Error("String length must be between 1 and 16383")
        if generated and kind != "id":
            raise Error("Only id columns can be generated")
        if kind == "id" and not primary:
            raise Error("An id column must be a primary key")
        if foreign_table.byte_length() > 0:
            _ = quoted_identifier(foreign_table)
            _ = quoted_identifier(foreign_column)
        if (
            delete_action != "RESTRICT"
            and delete_action != "CASCADE"
            and delete_action != "SET NULL"
        ):
            raise Error("Invalid foreign key delete action")
        if delete_action == "SET NULL" and not nullable:
            raise Error("SET NULL foreign key must be nullable")
        if primary and nullable:
            raise Error("Primary key cannot be nullable")
        self.name = name
        self.kind = kind
        self.width = width
        self.nullable = nullable
        self.unique = unique
        self.primary = primary
        self.generated = generated
        self.foreign_table = foreign_table
        self.foreign_column = foreign_column
        self.delete_action = delete_action

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        self.name = copy.name
        self.kind = copy.kind
        self.width = copy.width
        self.nullable = copy.nullable
        self.unique = copy.unique
        self.primary = copy.primary
        self.generated = copy.generated
        self.foreign_table = copy.foreign_table
        self.foreign_column = copy.foreign_column
        self.delete_action = copy.delete_action

    def sql(self, db: DbClient) raises -> String:
        """Generate driver-specific SQL for this validated column definition."""
        var col = db.identifier(self.name)
        var datatype = String("")
        if self.kind == "id":
            if db.driver == "mysql":
                datatype = "BIGINT UNSIGNED AUTO_INCREMENT"
            elif db.driver == "postgres":
                datatype = "BIGSERIAL"
            else:
                datatype = "INTEGER"
        elif self.kind == "integer":
            datatype = "INTEGER"
        elif self.kind == "bigint":
            if db.driver == "mysql" and self.foreign_table.byte_length() > 0:
                datatype = "BIGINT UNSIGNED"
            else:
                datatype = "BIGINT"
        elif self.kind == "string":
            datatype = "VARCHAR(" + String(self.width) + ")"
        elif self.kind == "text":
            datatype = "TEXT"
        elif self.kind == "boolean":
            if db.driver == "mysql":
                datatype = "TINYINT(1)"
            elif db.driver == "postgres":
                datatype = "BOOLEAN"
            else:
                datatype = "INTEGER"
        elif self.kind == "timestamp":
            if db.driver == "postgres":
                datatype = "TIMESTAMPTZ"
            elif db.driver == "mysql":
                datatype = "DATETIME"
            else:
                datatype = "TEXT"
        var statement = col + " " + datatype
        if self.primary:
            if self.generated and db.driver == "sqlite":
                statement += " PRIMARY KEY AUTOINCREMENT"
            else:
                statement += " PRIMARY KEY"
        elif not self.nullable:
            statement += " NOT NULL"
        if self.unique:
            statement += " UNIQUE"
        if self.foreign_table.byte_length() > 0:
            statement += " REFERENCES " + db.identifier(self.foreign_table)
            statement += "(" + db.identifier(self.foreign_column) + ")"
            statement += " ON DELETE " + self.delete_action
        return statement^


struct Table(Copyable):
    """Validated table definition that plans SQL schema changes for the selected database."""

    var name: String
    var columns: List[Column]

    def __init__(out self, name: String) raises:
        """Create a table declaration with a validated identifier."""
        _ = quoted_identifier(name)
        self.name = name
        self.columns = List[Column]()

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        self.name = copy.name
        self.columns = copy.columns.copy()

    def add(mut self, column: Column) raises:
        """Add a column while rejecting duplicate names and primary keys."""
        for previous in self.columns:
            if previous.name == column.name:
                raise Error("Duplicate schema column: " + column.name)
            if previous.primary and column.primary:
                raise Error("Multiple primary keys: " + self.name)
        self.columns.append(column.copy())

    def id(mut self, name: String = "id") raises:
        """Add an automatically generated integer primary key."""
        self.add(Column(name, "id", nullable=False, primary=True, generated=True))

    def string(
        mut self,
        name: String,
        width: Int = 255,
        required: Bool = False,
        unique: Bool = False,
    ) raises:
        """Add a bounded string column with optional uniqueness."""
        self.add(Column(name, "string", width, nullable=not required, unique=unique))

    def integer(
        mut self, name: String, required: Bool = False, unique: Bool = False
    ) raises:
        """Add an integer column with optional uniqueness."""
        self.add(Column(name, "integer", nullable=not required, unique=unique))

    def bigint(
        mut self, name: String, required: Bool = False, unique: Bool = False
    ) raises:
        """Add a 64-bit integer column with optional uniqueness."""
        self.add(Column(name, "bigint", nullable=not required, unique=unique))

    def text(mut self, name: String, required: Bool = False) raises:
        """Add a text column, optionally requiring a value."""
        self.add(Column(name, "text", nullable=not required))

    def boolean(mut self, name: String, required: Bool = False) raises:
        """Add a Boolean column in the selected database representation."""
        self.add(Column(name, "boolean", nullable=not required))

    def timestamp(mut self, name: String, required: Bool = False) raises:
        """Add a timestamp column in the selected database representation."""
        self.add(Column(name, "timestamp", nullable=not required))

    def foreign_bigint(
        mut self,
        name: String,
        target_table: String,
        target_column: String = "id",
        required: Bool = True,
        on_delete: String = "RESTRICT",
    ) raises:
        """Add a foreign-key column with explicit delete behavior."""
        self.add(
            Column(
                name,
                "bigint",
                nullable=not required,
                foreign_table=target_table,
                foreign_column=target_column,
                delete_action=on_delete,
            )
        )

    def create_sql(self, db: DbClient) raises -> String:
        """Generate a CREATE TABLE IF NOT EXISTS statement."""
        if len(self.columns) == 0:
            raise Error("Cannot create table without columns: " + self.name)
        var sql = "CREATE TABLE IF NOT EXISTS " + db.identifier(self.name) + " ("
        for i in range(len(self.columns)):
            if i > 0:
                sql += ", "
            sql += self.columns[i].sql(db)
        sql += ")"
        return sql^

    def existing_columns(self, db: DbClient) raises -> List[String]:
        """Inspect the existing column names in database metadata."""
        var result = List[String]()
        if db.driver == "sqlite":
            var rows = db.query_text(
                "PRAGMA table_info(" + db.identifier(self.name) + ")"
            )
            for i in range(rows.row_count()):
                var column = rows.cell(i, 1)
                if column:
                    result.append(column.value())
        elif db.driver == "postgres":
            var args = List[String]()
            args.append(self.name)
            var rows = db.query_text(
                (
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema = current_schema() AND table_name = $1 "
                    "ORDER BY ordinal_position"
                ),
                args,
            )
            for i in range(rows.row_count()):
                var column = rows.cell(i, 0)
                if column:
                    result.append(column.value())
        else:
            var args = List[String]()
            args.append(self.name)
            var rows = db.query_text(
                (
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_schema = DATABASE() AND table_name = ? "
                    "ORDER BY ordinal_position"
                ),
                args,
            )
            for i in range(rows.row_count()):
                var column = rows.cell(i, 0)
                if column:
                    result.append(column.value())
        return result^

    def plan(self, db: DbClient) raises -> List[String]:
        """Only additive operations; never drop columns or change existing types."""
        var statements = List[String]()
        var existing = self.existing_columns(db)
        if len(existing) == 0:
            statements.append(self.create_sql(db))
            return statements^
        for column in self.columns:
            var found = False
            for known in existing:
                if known == column.name:
                    found = True
                    break
            if not found:
                if column.primary or column.generated or column.unique:
                    raise Error(
                        "New primary/unique column requires an explicit SQL migration: "
                        + column.name
                    )
                if column.foreign_table.byte_length() > 0:
                    raise Error(
                        "New foreign-key column requires an explicit SQL migration: "
                        + column.name
                    )
                statements.append(
                    "ALTER TABLE "
                    + db.identifier(self.name)
                    + " ADD COLUMN "
                    + column.sql(db)
                )
        return statements^


struct Schema:
    """Ordered collection of table definitions for planning and applying schema changes."""

    var tables: List[Table]

    def __init__(out self):
        """Create an empty sequence of table declarations."""
        self.tables = List[Table]()

    def add(mut self, table: Table) raises:
        """Add a table declaration and reject duplicate table names."""
        for previous in self.tables:
            if previous.name == table.name:
                raise Error("Duplicate schema table: " + table.name)
        self.tables.append(table.copy())

    def plan(self, db: DbClient) raises -> List[String]:
        """Generate preview statements without changing the database."""
        var statements = List[String]()
        for table in self.tables:
            var pending = table.plan(db)
            for sql in pending:
                statements.append(sql)
        return statements^

    def sync(self, db: DbClient) raises -> Int:
        """Apply additive create-table and add-column operations."""
        var pending = self.plan(db)
        for sql in pending:
            db.execute(sql)
        return len(pending)


def _valid_migration_name(name: String) raises:
    var n = name.byte_length()
    if n < 1 or n > 80:
        raise Error("Migration identifier must contain 1-80 characters")
    for i in range(n):
        var c = Int(name.as_bytes()[i])
        var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
        var digit = c >= 48 and c <= 57
        if not letter and not digit and c != 95 and c != 45:
            raise Error("Invalid migration identifier")


def ensure_migration_history(db: DbClient) raises:
    """Create the migration history table if it is absent."""
    db.execute(
        "CREATE TABLE IF NOT EXISTS _mojara_db_migrations ("
        "version VARCHAR(80) PRIMARY KEY, "
        "applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
    )


def migration_applied(db: DbClient, version: String) raises -> Bool:
    """Check whether a named SQL migration has already run."""
    _valid_migration_name(version)
    ensure_migration_history(db)
    var values = List[String]()
    values.append(version)
    var rows = db.query_text(
        "SELECT version FROM _mojara_db_migrations WHERE version = "
        + db.placeholder(1),
        values,
    )
    return rows.row_count() > 0


def manual_migration(mut db: DbClient, version: String, sql: String) raises -> Bool:
    """Run trusted developer SQL once, with ledger tracking.

    MySQL DDL is not transactional. Each migration SQL is ONE statement;
    represent a multi-step migration with multiple versioned migration calls.
    """
    _valid_migration_name(version)
    if sql.byte_length() == 0:
        raise Error("Migration SQL must not be empty")
    if migration_applied(db, version):
        return False
    var args = List[String]()
    args.append(version)
    var transactional = db.driver != "mysql"
    if transactional:
        db.begin()
    try:
        db.execute(sql)
        db.execute(
            "INSERT INTO _mojara_db_migrations(version) VALUES ("
            + db.placeholder(1)
            + ")",
            args,
        )
        if transactional:
            db.commit()
    except e:
        if transactional:
            try:
                db.rollback()
            except:
                pass
        raise Error("Migration " + version + " failed: " + String(e))
    return True


def manual_migration_file(
    mut db: DbClient,
    version: String,
    file_path: String,
) raises -> Bool:
    """Apply a one-statement .sql file; values must use bound parameters elsewhere."""
    if not file_path.endswith(".sql"):
        raise Error("Manual migration files must have a .sql extension")
    var sql = Path(file_path).read_text()
    return manual_migration(db, version, sql)
