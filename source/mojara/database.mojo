"""SQLite database connection construction.

Connections are independently owned; do not share a mutable connection
concurrently between unrelated request handlers or background threads."""

from sqlite import Database


def open_sqlite(path: String) raises -> Database:
    """Open SQLite with foreign keys and a small lock contention timeout."""
    var db = Database(path)
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA busy_timeout = 5000")
    return db^
