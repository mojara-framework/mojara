"""Transactional, versioned SQLite schema migrations.

Apply trusted migration SQL and track completed versions. Reverse operations
require an explicit developer-supplied rollback statement."""

from sqlite import Database


def ensure_migrations(db: Database) raises:
    """Create the migration ledger if missing."""
    db.execute(
        "CREATE TABLE IF NOT EXISTS _mojara_migrations ("
        "version INTEGER PRIMARY KEY, "
        "applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    )


def is_applied(db: Database, version: Int) raises -> Bool:
    """Check whether a positive migration version was committed."""
    if version <= 0:
        raise Error("Migration version must be positive")
    ensure_migrations(db)
    var stmt = db.prepare("SELECT 1 FROM _mojara_migrations WHERE version = ?")
    stmt.bind_int(1, version)
    var result = stmt.step()
    return Bool(result)


def applied_versions(db: Database) raises -> List[Int]:
    """List committed migrations in ascending version order."""
    ensure_migrations(db)
    var stmt = db.prepare("SELECT version FROM _mojara_migrations ORDER BY version")
    var versions = List[Int]()
    while True:
        var maybe = stmt.step()
        if not Bool(maybe):
            break
        versions.append(maybe.value().int_val(0))
    return versions^


def migrate(db: Database, version: Int, up_sql: String) raises -> Bool:
    """Apply trusted SQL once, atomically registering its version.

    Returns True when newly applied; False when already applied.
    A failure rolls back both SQL and ledger via the transaction guard.
    """
    if version <= 0:
        raise Error("Migration version must be positive")
    if up_sql.byte_length() == 0:
        raise Error("Migration SQL must not be empty")
    ensure_migrations(db)
    var tx = db.transaction()
    if is_applied(db, version):
        tx.commit()
        return False
    db.execute(up_sql)
    var stmt = db.prepare("INSERT INTO _mojara_migrations(version) VALUES (?)")
    stmt.bind_int(1, version)
    _ = stmt.step()
    tx.commit()
    return True


def rollback_migration(db: Database, version: Int, down_sql: String) raises -> Bool:
    """Apply explicit trusted reverse SQL and remove one migration record."""
    if version <= 0:
        raise Error("Migration version must be positive")
    if down_sql.byte_length() == 0:
        raise Error("Rollback SQL must not be empty")
    ensure_migrations(db)
    var tx = db.transaction()
    if not is_applied(db, version):
        tx.commit()
        return False
    db.execute(down_sql)
    var stmt = db.prepare("DELETE FROM _mojara_migrations WHERE version = ?")
    stmt.bind_int(1, version)
    _ = stmt.step()
    tx.commit()
    return True
