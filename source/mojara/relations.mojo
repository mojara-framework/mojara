"""Explicit SQLite parent-child and many-to-many relationships.

Relationship helpers validate SQL identifiers and bind runtime values rather
than concatenating untrusted data into SQL text."""

from sqlite import Database
from .orm import QueryBuilder, quoted_identifier


def create_join_table(
    db: Database,
    junction: String,
    left_table: String,
    left_key: String,
    right_table: String,
    right_key: String,
) raises:
    """Create an explicit many-to-many table with restrictive names and FKs."""
    if left_key == right_key:
        raise Error("Junction foreign-key columns must differ")
    var j = quoted_identifier(junction)
    var lt = quoted_identifier(left_table)
    var rt = quoted_identifier(right_table)
    var lk = quoted_identifier(left_key)
    var rk = quoted_identifier(right_key)
    db.execute(
        "CREATE TABLE IF NOT EXISTS "
        + j
        + " ("
        + lk
        + " INTEGER NOT NULL REFERENCES "
        + lt
        + '("id") ON DELETE CASCADE, '
        + rk
        + " INTEGER NOT NULL REFERENCES "
        + rt
        + '("id") ON DELETE CASCADE, '
        + "PRIMARY KEY ("
        + lk
        + ", "
        + rk
        + "))"
    )


def link(
    db: Database,
    junction: String,
    left_key: String,
    right_key: String,
    left_id: Int,
    right_id: Int,
) raises:
    """Attach a pair; repeated attachments are harmless with the join table PK."""
    var stmt = db.prepare(
        "INSERT OR IGNORE INTO "
        + quoted_identifier(junction)
        + " ("
        + quoted_identifier(left_key)
        + ", "
        + quoted_identifier(right_key)
        + ") VALUES (?, ?)"
    )
    stmt.bind_int(1, left_id)
    stmt.bind_int(2, right_id)
    _ = stmt.step()


def unlink(
    db: Database,
    junction: String,
    left_key: String,
    right_key: String,
    left_id: Int,
    right_id: Int,
) raises:
    """Detach a pair without deleting either related model."""
    var stmt = db.prepare(
        "DELETE FROM "
        + quoted_identifier(junction)
        + " WHERE "
        + quoted_identifier(left_key)
        + " = ? AND "
        + quoted_identifier(right_key)
        + " = ?"
    )
    stmt.bind_int(1, left_id)
    stmt.bind_int(2, right_id)
    _ = stmt.step()


def related_ids(
    db: Database,
    junction: String,
    from_key: String,
    to_key: String,
    source_id: Int,
) raises -> List[Int]:
    """Return associated IDs ordered ascending, with bound relationship key."""
    var stmt = db.prepare(
        "SELECT "
        + quoted_identifier(to_key)
        + " FROM "
        + quoted_identifier(junction)
        + " WHERE "
        + quoted_identifier(from_key)
        + " = ? ORDER BY "
        + quoted_identifier(to_key)
        + " ASC"
    )
    stmt.bind_int(1, source_id)
    var found = List[Int]()
    while True:
        var row = stmt.step()
        if not Bool(row):
            break
        found.append(row.value().int_val(0))
    return found^


def children(table: String, foreign_key: String, parent_id: Int) raises -> QueryBuilder:
    """One-to-many: query child models by the parent's integer primary key."""
    var result = QueryBuilder(table)
    result.where_int(foreign_key, parent_id)
    return result^


def parent_id(
    db: Database,
    child_table: String,
    foreign_key: String,
    child_id: Int,
) raises -> Optional[Int]:
    """Many-to-one: find the referenced parent's ID for a given child."""
    var stmt = db.prepare(
        "SELECT "
        + quoted_identifier(foreign_key)
        + " FROM "
        + quoted_identifier(child_table)
        + ' WHERE "id" = ? LIMIT 1'
    )
    stmt.bind_int(1, child_id)
    var row = stmt.step()
    if not Bool(row):
        return None
    if row.value().is_null(0):
        return None
    return Optional[Int](row.value().int_val(0))


def create_unique_relation_index(
    db: Database,
    index_name: String,
    child_table: String,
    foreign_key: String,
) raises:
    """Enforce one-to-one cardinality for non-NULL foreign keys."""
    db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS "
        + quoted_identifier(index_name)
        + " ON "
        + quoted_identifier(child_table)
        + " ("
        + quoted_identifier(foreign_key)
        + ")"
    )
