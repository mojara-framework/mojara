"""Explicit SQLite schema modification helpers.

The helpers validate developer-supplied identifiers before creating indexes,
adding columns, or renaming schema objects."""

from sqlite import Database
from .orm import quoted_identifier


def _sql_type(name: String) raises -> String:
    if (
        name == "INTEGER"
        or name == "TEXT"
        or name == "REAL"
        or name == "BLOB"
        or name == "NUMERIC"
    ):
        return name.copy()
    raise Error("Unsupported SQLite column type")


def add_column(
    db: Database,
    table: String,
    column: String,
    sqlite_type: String,
) raises:
    """Add a nullable scalar column. Backfills and constraints are explicit SQL."""
    db.execute(
        "ALTER TABLE "
        + quoted_identifier(table)
        + " ADD COLUMN "
        + quoted_identifier(column)
        + " "
        + _sql_type(sqlite_type)
    )


def rename_column(
    db: Database,
    table: String,
    previous: String,
    replacement: String,
) raises:
    """Rename an existing SQLite column using validated identifiers."""
    db.execute(
        "ALTER TABLE "
        + quoted_identifier(table)
        + " RENAME COLUMN "
        + quoted_identifier(previous)
        + " TO "
        + quoted_identifier(replacement)
    )


def rename_table(db: Database, previous: String, replacement: String) raises:
    """Rename an SQLite table using validated identifiers."""
    db.execute(
        "ALTER TABLE "
        + quoted_identifier(previous)
        + " RENAME TO "
        + quoted_identifier(replacement)
    )


def create_index(
    db: Database,
    index_name: String,
    table: String,
    column: String,
    unique: Bool = False,
) raises:
    """Create a named index on validated table columns."""
    var prefix = (
        "CREATE UNIQUE INDEX IF NOT EXISTS " if unique else "CREATE INDEX IF NOT EXISTS "
    )
    db.execute(
        prefix
        + quoted_identifier(index_name)
        + " ON "
        + quoted_identifier(table)
        + " ("
        + quoted_identifier(column)
        + ")"
    )


def drop_index(db: Database, index_name: String) raises:
    """Drop a validated named SQLite index."""
    db.execute("DROP INDEX IF EXISTS " + quoted_identifier(index_name))
