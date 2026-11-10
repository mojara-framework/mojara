"""SQLite model reflection, repositories and query builders.

Mojo model types map to SQLite tables. Identifiers are validated and values
are bound as prepared parameters. Relationships are defined explicitly."""

from morph.reflect import Morphable
from sqlite import Database, Statement
from sqlite.orm import create_table, insert, query


def quoted_identifier(name: String) raises -> String:
    """Validate an ASCII SQL identifier, then quote it for SQLite.

    Accepted: [A-Za-z_][A-Za-z0-9_]*. Reject periods, spaces, quotes,
    and other characters; callers must not supply SQL expressions.
    """
    var n = name.byte_length()
    if n == 0 or n > 63:
        raise Error("SQL identifier must contain 1-63 ASCII characters")
    for i in range(n):
        var c = Int(name.as_bytes()[i])
        var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
        var digit = c >= 48 and c <= 57
        if not (letter or c == 95 or (i > 0 and digit)):
            raise Error("Unsafe SQL identifier: " + name)
    return '"' + name + '"'


def create_model[T: Morphable](db: Database, table: String) raises:
    """Create a table using T's Mojo fields as SQLite columns."""
    create_table[T](db, quoted_identifier(table))


def insert_model[T: Morphable](db: Database, table: String, value: T) raises:
    """Insert a model using parameterized values, never string SQL data."""
    insert[T](db, quoted_identifier(table), value)


def all_models[T: Morphable & Copyable](db: Database, table: String) raises -> List[T]:
    """Read all model rows from a validated table name."""
    return query[T](db, quoted_identifier(table))


def find_by_id[
    T: Morphable & Copyable
](db: Database, table: String, id: Int) raises -> List[T]:
    """Read model rows with an integer `id` field; normally zero or one."""
    return query[T](db, quoted_identifier(table), '"id" = ' + String(id))


def count_models(db: Database, table: String) raises -> Int:
    """Count rows in a table without loading model objects."""
    var stmt = db.prepare("SELECT COUNT(*) FROM " + quoted_identifier(table))
    var maybe = stmt.step()
    if not Bool(maybe):
        return 0
    return maybe.value().int_val(0)


def delete_by_id(db: Database, table: String, id: Int) raises:
    """Delete a row via a bound integer key."""
    var stmt = db.prepare("DELETE FROM " + quoted_identifier(table) + ' WHERE "id" = ?')
    stmt.bind_int(1, id)
    _ = stmt.step()


def update_text_by_id(
    db: Database, table: String, column: String, id: Int, value: String
) raises:
    """Safely update a text column; SQL identifiers and values are distinct."""
    var stmt = db.prepare(
        "UPDATE "
        + quoted_identifier(table)
        + " SET "
        + quoted_identifier(column)
        + ' = ? WHERE "id" = ?'
    )
    stmt.bind_text(1, value)
    stmt.bind_int(2, id)
    _ = stmt.step()


# ---------------------------------------------------------------------------
# Prepared-query builder. All user data is bound, never interpolated into SQL.
# ---------------------------------------------------------------------------


struct _Predicate(Copyable):
    var column: String
    var operation: String
    var category: Int  # 0 -> integer, 1 -> text, 2 -> IS NULL, 3 -> IS NOT NULL
    var integer_value: Int
    var text_value: String

    def __init__(out self, column: String, op: String, number: Int):
        """Build a typed and validated SQL predicate."""
        self.column = column
        self.operation = op
        self.category = 0
        self.integer_value = number
        self.text_value = ""

    def __init__(out self, column: String, op: String, value: String):
        """Build a typed and validated SQL predicate."""
        self.column = column
        self.operation = op
        self.category = 1
        self.integer_value = 0
        self.text_value = value

    def __init__(out self, column: String, is_not_null: Bool):
        """Build a typed and validated SQL predicate."""
        self.column = column
        self.operation = ""
        self.category = 3 if is_not_null else 2
        self.integer_value = 0
        self.text_value = ""

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        self.column = copy.column
        self.operation = copy.operation
        self.category = copy.category
        self.integer_value = copy.integer_value
        self.text_value = copy.text_value


def _numeric_operator(op: String) raises:
    if (
        op != "="
        and op != "!="
        and op != "<"
        and op != "<="
        and op != ">"
        and op != ">="
    ):
        raise Error("Unsupported integer comparison operator")


def _text_operator(op: String) raises:
    if op != "=" and op != "!=" and op != "LIKE":
        raise Error("Unsupported text comparison operator")


struct QueryBuilder:
    """Typed, parameterized SQLite filtering and deterministic pagination.

    The model must expose a unique INTEGER `id` column. `fetch[T]` executes
    one prepared ID query, then maps rows via the upstream SQLite ORM using
    batches of verified numeric IDs; it preserves the requested sort order.
    Calls to count() and exists() ignore pagination deliberately.
    """

    var table: String
    var predicates: List[_Predicate]
    var sort_column: String
    var sort_descending: Bool
    var max_rows: Int
    var skip_rows: Int

    def __init__(out self, table: String) raises:
        """Create a query for a model table with an integer key."""
        _ = quoted_identifier(table)
        self.table = table
        self.predicates = List[_Predicate]()
        self.sort_column = "id"
        self.sort_descending = False
        self.max_rows = 0
        self.skip_rows = 0

    def where_int(mut self, column: String, number: Int, op: String = "=") raises:
        """Add a bound integer predicate."""
        _ = quoted_identifier(column)
        _numeric_operator(op)
        self.predicates.append(_Predicate(column, op, number))

    def where_text(mut self, column: String, value: String, op: String = "=") raises:
        """Add a bound text predicate."""
        _ = quoted_identifier(column)
        _text_operator(op)
        self.predicates.append(_Predicate(column, op, value))

    def where_null(mut self, column: String, is_not_null: Bool = False) raises:
        """Add a validated IS NULL predicate."""
        _ = quoted_identifier(column)
        self.predicates.append(_Predicate(column, is_not_null))

    def order_by(mut self, column: String, descending: Bool = False) raises:
        """Set a validated sort column and direction."""
        _ = quoted_identifier(column)
        self.sort_column = column
        self.sort_descending = descending

    def limit(mut self, maximum: Int) raises:
        """Restrict the number of returned records."""
        if maximum < 1 or maximum > 500:
            raise Error("Query limit must be between 1 and 500")
        self.max_rows = maximum

    def offset(mut self, skip: Int) raises:
        """Skip a validated number of records."""
        if skip < 0 or skip > 100000000:
            raise Error("Query offset must be between 0 and 100000000")
        self.skip_rows = skip

    def page(mut self, number: Int, page_size: Int = 25) raises:
        """Select records using validated page and page-size values."""
        if number < 1 or number > 1000000:
            raise Error("Page number must be between 1 and 1000000")
        if page_size < 1 or page_size > 500:
            raise Error("Page size must be between 1 and 500")
        self.max_rows = page_size
        self.skip_rows = (number - 1) * page_size

    def _where(self) raises -> String:
        var result = String("")
        for i in range(len(self.predicates)):
            if i == 0:
                result += " WHERE "
            else:
                result += " AND "
            ref pred = self.predicates[i]
            result += quoted_identifier(pred.column)
            if pred.category == 2:
                result += " IS NULL"
            elif pred.category == 3:
                result += " IS NOT NULL"
            else:
                result += " " + pred.operation + " ?"
        return result

    def _bind(self, stmt: Statement) raises:
        var position = 1
        for i in range(len(self.predicates)):
            ref pred = self.predicates[i]
            if pred.category == 0:
                stmt.bind_int(position, pred.integer_value)
                position += 1
            elif pred.category == 1:
                stmt.bind_text(position, pred.text_value)
                position += 1

    def count(self, db: Database) raises -> Int:
        """Count records matching the accumulated conditions."""
        var stmt = db.prepare(
            "SELECT COUNT(*) FROM " + quoted_identifier(self.table) + self._where()
        )
        self._bind(stmt)
        var result = stmt.step()
        if not Bool(result):
            return 0
        return result.value().int_val(0)

    def exists(self, db: Database) raises -> Bool:
        """Test whether any record matches the conditions."""
        var stmt = db.prepare(
            "SELECT 1 FROM "
            + quoted_identifier(self.table)
            + self._where()
            + " LIMIT 1"
        )
        self._bind(stmt)
        var result = stmt.step()
        return Bool(result)

    def ids(self, db: Database) raises -> List[Int]:
        """Read the integer identifiers of matching records."""
        var sql = 'SELECT "id" FROM ' + quoted_identifier(self.table) + self._where()
        sql += " ORDER BY " + quoted_identifier(self.sort_column)
        if self.sort_descending:
            sql += " DESC"
        else:
            sql += " ASC"
        if self.sort_column != "id":
            sql += ', "id" ASC'
        if self.max_rows > 0:
            sql += " LIMIT " + String(self.max_rows)
        elif self.skip_rows > 0:
            sql += " LIMIT -1"
        if self.skip_rows > 0:
            sql += " OFFSET " + String(self.skip_rows)
        var stmt = db.prepare(sql)
        self._bind(stmt)
        var found = List[Int]()
        while True:
            var maybe = stmt.step()
            if not Bool(maybe):
                break
            found.append(maybe.value().int_val(0))
        return found^

    def fetch[T: Morphable & Copyable](self, db: Database) raises -> List[T]:
        """Load ordered typed rows. Always bind filter values first.

        `sqlite.orm.query` currently does not accept bound WHERE arguments.
        Consequently Mojara selects IDs using prepared statements, and only
        interpolates numeric IDs returned by SQLite into a second query.
        Results are fetched in 100-row batches, not one query per row.
        """
        var selected = self.ids(db)
        var results = List[T]()
        var start = 0
        while start < len(selected):
            var stop = start + 100
            if stop > len(selected):
                stop = len(selected)
            var condition = String('"id" IN (')
            var ordering = String(' ORDER BY CASE "id"')
            for i in range(start, stop):
                if i > start:
                    condition += ", "
                condition += String(selected[i])
                ordering += (
                    " WHEN " + String(selected[i]) + " THEN " + String(i - start)
                )
            condition += ")" + ordering + " ELSE " + String(stop - start) + " END"
            var batch = query[T](db, quoted_identifier(self.table), condition)
            for j in range(len(batch)):
                results.append(batch[j].copy())
            start = stop
        return results^


struct Repository[T: Morphable & Copyable]:
    """A typed table facade over an explicitly supplied SQLite connection.

    Repository does NOT own a shared connection. Create a connection per
    request/worker with open_sqlite; pass it to repository methods.
    """

    var table: String

    def __init__(out self, table: String) raises:
        """Associate a typed model with a database and table."""
        _ = quoted_identifier(table)
        self.table = table

    def query(self) raises -> QueryBuilder:
        """Start a safe, typed query for this repository."""
        return QueryBuilder(self.table)

    def create(self, db: Database) raises:
        """Create the reflected SQLite table for the model."""
        create_model[Self.T](db, self.table)

    def add(self, db: Database, value: Self.T) raises:
        """Insert a model using bound field values."""
        insert_model[Self.T](db, self.table, value)

    def all(self, db: Database) raises -> List[Self.T]:
        """Load all model records from the repository table."""
        return all_models[Self.T](db, self.table)

    def by_id(self, db: Database, id: Int) raises -> List[Self.T]:
        """Load one model record using its integer key."""
        return find_by_id[Self.T](db, self.table, id)

    def count(self, db: Database) raises -> Int:
        """Return the number of records in the repository table."""
        return count_models(db, self.table)

    def delete_id(self, db: Database, id: Int) raises:
        """Delete a record using its integer key."""
        delete_by_id(db, self.table, id)

    def update_text(self, db: Database, column: String, id: Int, value: String) raises:
        """Update a validated text column for one record."""
        update_text_by_id(db, self.table, column, id, value)
