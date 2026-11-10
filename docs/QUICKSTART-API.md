# Forms and Database Queries

## Parse Form Data

```mojo
from mojara.forms import parse_form

def submit(req: Request) raises -> Response:
    var fields = parse_form(req)
    var email = fields.get_first("email")
    if not email:
        return Response.error(400, "Email Is Required")
    return Response.text("Received")
```

The default limit is 64 KiB of encoded form data and 64 fields. Override
the limits when necessary:

```mojo
var fields = parse_form(req, max_bytes=131072, max_fields=100)
```

## Query the Database

```mojo
var records = db.query("SELECT id, name FROM users")
var one = db.fetch_one(
    "SELECT id, name FROM users WHERE id = " + db.placeholder(1),
    ["12"],
)
var all_records = db.fetch_all("SELECT id, name FROM users")
```

For SQLite and MySQL, placeholders are `?`. PostgreSQL uses `$1`,
`$2`, etc. `db.placeholder(index)` generates the correct placeholder.

## Insert, Update and Delete

```mojo
db.insert("users", ["id", "name"], ["12", "Muhammad"])
db.update("users", ["name"], ["Muhammad Goni"], "id", "12")
db.delete("users", "id", "12")
```

These methods validate identifiers and bind values. Update and delete
require a matching column and bound value. Use `db.execute(sql, params)`
for complex SQL predicates.

The old names `parse_request_form()` and `query_text()` remain available
for existing Mojara applications.

## Serve Static Assets

```mojo
app.get_handler("/static/bootstrap/:name", StaticFile("static/bootstrap"))
```

`StaticFile` defaults to 2 MiB per file; override `max_bytes` only
when necessary.
