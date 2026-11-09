"""Portable, bound-parameter CRUD for a fixed table layout.

PortableTable manages integer-ID and text-name tables consistently on SQLite,
MySQL and PostgreSQL. Other layouts use the lower-level database client."""

from .dbclient import DbClient
from .postgres import PgRows
from .orm import quoted_identifier


struct PortableTable:
    """Portable accessor for an id/name table across supported SQL database drivers."""

    var name: String

    def __init__(out self, name: String) raises:
        """Construct a portable accessor for a validated table."""
        _ = quoted_identifier(name)
        self.name = name

    def create(self, db: DbClient) raises:
        """Create a compatible (id INTEGER, name VARCHAR(255)) schema.

        On MySQL, DDL commits implicitly. Do not run DDL in a user transaction.
        """
        var q = db.identifier(self.name)
        db.execute(
            "CREATE TABLE IF NOT EXISTS "
            + q
            + " (id INTEGER PRIMARY KEY, name VARCHAR(255) NOT NULL)"
        )

    def insert(self, db: DbClient, id: Int, name: String) raises:
        """Insert an integer identifier and text value using parameters."""
        var params = List[String]()
        params.append(String(id))
        params.append(name)
        db.execute(
            "INSERT INTO "
            + db.identifier(self.name)
            + " (id, name) VALUES ("
            + db.placeholder(1)
            + ", "
            + db.placeholder(2)
            + ")",
            params,
        )

    def update(self, db: DbClient, id: Int, name: String) raises:
        """Update a text value by its integer key."""
        var params = List[String]()
        params.append(name)
        params.append(String(id))
        db.execute(
            "UPDATE "
            + db.identifier(self.name)
            + " SET name = "
            + db.placeholder(1)
            + " WHERE id = "
            + db.placeholder(2),
            params,
        )

    def delete(self, db: DbClient, id: Int) raises:
        """Remove a record using its integer key."""
        var params = List[String]()
        params.append(String(id))
        db.execute(
            "DELETE FROM "
            + db.identifier(self.name)
            + " WHERE id = "
            + db.placeholder(1),
            params,
        )

    def by_id(self, db: DbClient, id: Int) raises -> PgRows:
        """Retrieve one text value by its integer key."""
        var params = List[String]()
        params.append(String(id))
        return db.query_text(
            "SELECT name FROM "
            + db.identifier(self.name)
            + " WHERE id = "
            + db.placeholder(1),
            params,
        )

    def page(self, db: DbClient, number: Int, page_size: Int = 25) raises -> PgRows:
        """Fetch a bounded, ordered page of records."""
        if number < 1 or number > 1000000 or page_size < 1 or page_size > 500:
            raise Error("Invalid pagination size or page number")
        var skip = (number - 1) * page_size
        # pagination integers have already been range checked; no user text SQL.
        return db.query_text(
            "SELECT name FROM "
            + db.identifier(self.name)
            + " ORDER BY id ASC LIMIT "
            + String(page_size)
            + " OFFSET "
            + String(skip)
        )
