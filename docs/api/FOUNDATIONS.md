# Mojara API reference: application, authentication and database foundations

This reference lists the first-party public Mojo declarations in the Mojara framework. Signatures are taken directly from `source/mojara/`. See [API reference index](../API-REFERENCE.md).

## `mojara`

[Source](../../source/mojara/__init__.mojo)

### `Response`

Mojara response wrapper with constructors for common content types.

**`Response.__init__`**

```mojo
def __init__(out self, var wire: WireResponse):
```
Take ownership of a native HTTP response.

**`Response.text`**

```mojo
def text(body: String) raises -> Response:
```
Build a UTF-8 plain-text response with the proper content type.

**`Response.html`**

```mojo
def html(body: String) raises -> Response:
```
Build an HTML response with UTF-8 content type.

**`Response.json`**

```mojo
def json(body: String) -> Response:
```
Return pre-serialized JSON (prefer json_value for untrusted data).

**`Response.json_value`**

```mojo
def json_value(value: Value) raises -> Response:
```
Serialize a Mojo JSON Value, escaping string values correctly.

**`Response.created_json`**

```mojo
def created_json(body: String) -> Response:
```
Return pre-serialized JSON with HTTP status 201.

**`Response.created_value`**

```mojo
def created_value(value: Value) raises -> Response:
```
Serialize a JSON value and return HTTP status 201.

**`Response.redirect`**

```mojo
def redirect(location: String, permanent: Bool = False) raises -> Response:
```
Build an HTTP redirect; permanent selects HTTP 301.

**`Response.error`**

```mojo
def error(status: Int, message: String) raises -> Response:
```
Return an escaped JSON error body and the provided HTTP status.

**`Response.render`**

```mojo
def render(source: String, var context: TemplateContext) raises -> Response:
```
Compile and render HTML, escaping interpolated variables by default.

**`Response.render_file`**

```mojo
def render_file(path: String, var context: TemplateContext) raises -> Response:
```
Load trusted template path, render as HTML. Do not use user paths.

**`Response.set_header`**

```mojo
def set_header(mut self, name: String, value: String) raises:
```
Add or replace a validated HTTP response header.

**`Response.set_status`**

```mojo
def set_status(mut self, status: Int):
```
Set the status code of the pending HTTP response.

**`Response.into_wire`**

```mojo
def into_wire(deinit self) -> WireResponse:
```
Consume the wrapper, transferring its move-only Flare response.

**`Response.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Invoke a registered route function and return its wire response.

**`Response.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Execute request guards, dispatch, error handling, and response hooks.

### `AppConfig`

Configuration for the development server. Defaults are loopback-only.

**`AppConfig.__init__`**

```mojo
def __init__(out self):
```
Initialize listener and worker defaults.

### `App`

Routing, HTTP lifecycle and app server entrypoints.

**`App.__init__`**

```mojo
def __init__(out self):
```
Create an application router with empty middleware and configuration.

**`App.get`**

```mojo
def get(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP GET.

**`App.post`**

```mojo
def post(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP POST.

**`App.put`**

```mojo
def put(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP PUT.

**`App.patch`**

```mojo
def patch(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP PATCH.

**`App.delete`**

```mojo
def delete(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP DELETE.

**`App.head`**

```mojo
def head(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP HEAD.

**`App.options`**

```mojo
def options(
mut self, path: String, handler: def(Request) raises thin -> Response
) raises:
```
Register a function handler for HTTP OPTIONS.

**`App.mount`**

```mojo
def mount(mut self, prefix: String, sub: App) raises:
```
Mount sub-app routes. Sub-app middleware does not propagate.

**`App.cors`**

```mojo
def cors(
mut self,
origin: String,
methods: String = "GET,POST,OPTIONS",
headers: String = "Content-Type,Authorization",
credentials: Bool = False,
) raises:
```
Enable CORS for an exact trusted Origin, or * without credentials.

**`App.before_request`**

```mojo
def before_request(mut self, hook: def(Request) raises thin -> Bool):
```
Register a guard: False rejects with HTTP 403, True continues.

**`App.after_request`**

```mojo
def after_request(
mut self,
hook: def(Request, var WireResponse) raises thin -> WireResponse,
):
```
Register a response hook for every response, including 403/404.

**`App.errorhandler`**

```mojo
def errorhandler(
mut self, status: Int, callback: def(Request) raises thin -> Response
) raises:
```
Replace 404 or 405 responses; other statuses are unsupported.

**`App.handle`**

```mojo
def handle(self, req: Request) raises -> WireResponse:
```
Dispatch in-process, including middleware, without opening TCP.

**`App.run`**

```mojo
def run(
mut self,
host: String = "127.0.0.1",
port: UInt16 = 8000,
workers: Int = 1,
) raises:
```
Blocking native server; binds loopback unless configured otherwise.

**`App.run_configured`**

```mojo
def run_configured(mut self) raises:
```
Honor MOJARA_HOST, MOJARA_PORT and MOJARA_WORKERS if configured.

## `mojara.api`

[Source](../../source/mojara/api.mojo)

### `FieldRule`

A JSON object field with its expected type and requiredness.

**`FieldRule.__init__`**

```mojo
def __init__(
out self,
name: String,
kind: String,
required: Bool = True,
min_length: Int = 0,
):
```
Describe one JSON field and its validation constraints.

### `Schema`

Declarative flat JSON object schema with field-level errors.

**`Schema.__init__`**

```mojo
def __init__(out self):
```
Create an empty JSON object validation schema.

**`Schema.string`**

```mojo
def string(
mut self, name: String, required: Bool = True, min_length: Int = 0
) raises:
```
Declare a string field with required and minimum-length options.

**`Schema.integer`**

```mojo
def integer(mut self, name: String, required: Bool = True) raises:
```
Declare an integer field, optionally required.

**`Schema.boolean`**

```mojo
def boolean(mut self, name: String, required: Bool = True) raises:
```
Declare a Boolean field, optionally required.

**`Schema.errors`**

```mojo
def errors(self, payload: Value) raises -> Value:
```
Return a JSON array of violations; an empty array means valid.

**`Schema.openapi_schema`**

```mojo
def openapi_schema(self) raises -> Value:
```
Translate field rules into an OpenAPI-compatible JSON schema.

**`Schema.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Validate the JSON request before invoking the route.

**`Schema.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Return the generated OpenAPI JSON document.

**`Schema.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Return the interactive API documentation.

### `Operation`

Metadata for a registered endpoint, including its route, validation schema and authentication policy.

**`Operation.__init__`**

```mojo
def __init__(
out self,
method: String,
path: String,
summary: String,
schema: Schema = Schema(),
has_body: Bool = False,
secured: Bool = False,
):
```
Record the route operation metadata used for OpenAPI.

### `Api`

API-first wrapper over Mojara App with registered-route documentation.

**`Api.__init__`**

```mojo
def __init__(out self, title: String = "Mojara API", version: String = "0.1.0"):
```
Create an API router with a title and document version.

**`Api.get`**

```mojo
def get(
mut self,
path: String,
callback: def(Request) raises thin -> Response,
summary: String = "",
) raises:
```
Register a documented GET route.

**`Api.post`**

```mojo
def post(
mut self,
path: String,
callback: def(Request) raises thin -> Response,
summary: String = "",
) raises:
```
Register a documented POST route.

**`Api.post_validated`**

```mojo
def post_validated(
mut self,
path: String,
callback: def(Request, Value) raises thin -> Response,
schema: Schema,
summary: String = "",
max_body_bytes: Int = 1048576,
) raises:
```
Register a POST route that validates its JSON request body.

**`Api.put_validated`**

```mojo
def put_validated(
mut self,
path: String,
callback: def(Request, Value) raises thin -> Response,
schema: Schema,
summary: String = "",
max_body_bytes: Int = 1048576,
) raises:
```
Register a PUT route that validates its JSON request body.

**`Api.patch_validated`**

```mojo
def patch_validated(
mut self,
path: String,
callback: def(Request, Value) raises thin -> Response,
schema: Schema,
summary: String = "",
max_body_bytes: Int = 1048576,
) raises:
```
Register a PATCH route that validates its JSON request body.

**`Api.secure_get`**

```mojo
def secure_get(
mut self,
path: String,
callback: def(Request, Principal) raises thin -> Response,
auth: AuthStore,
summary: String = "",
role: String = "",
) raises:
```
Authenticated GET, optionally requiring an exact account role.

**`Api.secure_post`**

```mojo
def secure_post(
mut self,
path: String,
callback: def(Request, Principal) raises thin -> Response,
auth: AuthStore,
summary: String = "",
role: String = "",
) raises:
```
Authenticated POST, optionally requiring an exact account role.

**`Api.openapi_document`**

```mojo
def openapi_document(self) raises -> Value:
```
Generate OpenAPI 3.1 documentation from registered API operations.

**`Api.install_docs`**

```mojo
def install_docs(mut self) raises:
```
Register /openapi.json, /docs and /redoc after API routes are set.

**`Api.handle`**

```mojo
def handle(self, req: Request) raises -> WireResponse:
```
Dispatch an HTTP request through the API router.

**`Api.run_configured`**

```mojo
def run_configured(mut self) raises:
```
Start the API using validated listener configuration.

## `mojara.auth`

[Source](../../source/mojara/auth.mojo)

### `Principal`

Identity resolved from a valid bearer token.

### `AuthStore`

Stateless facade: each call uses its own SQLite database connection.

**`AuthStore.__init__`**

```mojo
def __init__(out self, path: String) raises:
```
Select the authentication database path.

**`AuthStore.install`**

```mojo
def install(self) raises:
```
Idempotent setup of authorization tables (run before serving).

**`AuthStore.register`**

```mojo
def register(self, email: String, password: String) raises -> Int:
```
Register a regular user. Role cannot be chosen by the caller.

**`AuthStore.login`**

```mojo
def login(
self, email: String, password: String, ttl_seconds: Int = 3600
) raises -> String:
```
Verify credentials; enforce max 5 tries/email/15min; issue token.

**`AuthStore.authenticate`**

```mojo
def authenticate(self, req: Request) raises -> Optional[Principal]:
```
Return resolved identity or None; expired/revoked tokens fail shut.

**`AuthStore.logout`**

```mojo
def logout(self, req: Request) raises:
```
Immediately revoke the supplied bearer token.

**`AuthStore.revoke_user`**

```mojo
def revoke_user(self, id: Int) raises:
```
Revoke every token belonging to a user (trusted admin operation).

**`AuthStore.set_role`**

```mojo
def set_role(self, id: Int, role: String) raises:
```
Trusted administrative operation; never bind directly to signup.

**`AuthStore.disable`**

```mojo
def disable(self, id: Int) raises:
```
Disable user and invalidate outstanding bearer tokens.

**`AuthStore.clear_expired_tokens`**

```mojo
def clear_expired_tokens(self) raises:
```
Delete expired token records.

### `ProtectedRoute`

Per-route authentication and role enforcement; no global state.

**`ProtectedRoute.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Authenticate the request, check its required role and dispatch.

## `mojara.asyncdb`

[Source](../../source/mojara/asyncdb.mojo)

### `AsyncDbPool`

Bounded connection-owning worker pool.

**`AsyncDbPool.__init__`**

```mojo
def __init__(
out self,
config: DatabaseSettings,
workers: Int = 4,
max_outstanding: Int = 128,
) raises:
```
Create a bounded pool with dedicated background database connections.

**`AsyncDbPool.__init__`**

```mojo
def __init__(out self, *, copy: Self):
```
Copy this value while preserving its resource ownership contract.

**`AsyncDbPool.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`AsyncDbPool.submit`**

```mojo
def submit(
self, sql: String, params: List[String] = List[String]()
) raises -> UInt64:
```
Submit SQL without waiting, returning an opaque job identifier.

**`AsyncDbPool.status`**

```mojo
def status(self, id: UInt64) raises -> Int:
```
0 pending, 1 completed, 2 failed, -1 unknown/expired.

**`AsyncDbPool.take`**

```mojo
def take(self, id: UInt64) raises -> Optional[String]:
```
Non-blocking read: None if pending, JSON result if complete.

**`AsyncDbPool.discard`**

```mojo
def discard(self, id: UInt64) raises -> Bool:
```
Release a completed result without reading it; pending jobs are retained.

**`open_async_database`**

```mojo
def open_async_database(
config: DatabaseSettings,
workers: Int = 4,
max_outstanding: Int = 128,
) raises -> AsyncDbPool:
```
Create an async DB worker pool. Keep a copy in each registered handler.

## `mojara.config`

[Source](../../source/mojara/config.mojo)

### `DatabaseSettings`

Validated database connection and logging configuration shared by Mojara's SQL clients.

**`DatabaseSettings.__init__`**

```mojo
def __init__(
out self,
driver: String,
sqlite_path: String,
postgres_dsn: String,
log_level: String,
mysql_host: String = "127.0.0.1",
mysql_port: Int = 3306,
mysql_user: String = "",
mysql_password: String = "",
mysql_database: String = "",
) raises:
```
Initialize a database configuration or copy an existing one.

**`DatabaseSettings.__init__`**

```mojo
def __init__(out self, *, copy: Self):
```
Copy this value while preserving its resource ownership contract.

**`load_database_settings`**

```mojo
def load_database_settings() raises -> DatabaseSettings:
```
Read database settings at application startup, never log the DSN.

## `mojara.crypto`

[Source](../../source/mojara/crypto.mojo)

**`ensure_crypto`**

```mojo
def ensure_crypto() raises:
```
Check that the required native cryptography backend is available.

**`hash_password`**

```mojo
def hash_password(password: String) raises -> String:
```
Hash password with libsodium's Argon2id (3 ops, 64 MiB).

**`verify_password`**

```mojo
def verify_password(password: String, encoded_hash: String) raises -> Bool:
```
Verify a password without exposing the password hash to users.

**`new_token`**

```mojo
def new_token() raises -> String:
```
Generate a 256-bit cryptographically random, lowercase hex token.

**`token_digest`**

```mojo
def token_digest(token: String) raises -> String:
```
SHA-256 digest for database token lookup; raw token is never stored.

## `mojara.database`

[Source](../../source/mojara/database.mojo)

**`open_sqlite`**

```mojo
def open_sqlite(path: String) raises -> Database:
```
Open SQLite with foreign keys and a small lock contention timeout.

## `mojara.dbclient`

[Source](../../source/mojara/dbclient.mojo)

### `DbClient`

Owned database connection that exposes portable operations for SQLite, PostgreSQL and MySQL.

**`DbClient.__init__`**

```mojo
def __init__(out self, config: DatabaseSettings) raises:
```
Open and own a connection for the configured database driver.

**`DbClient.execute`**

```mojo
def execute(self, sql: String, params: List[String] = List[String]()) raises:
```
Execute trusted SQL with bound values and return any affected-row count.

**`DbClient.query`**

```mojo
def query(
    self, sql: String, params: List[String] = List[String]()
) raises -> PgRows:
```
Execute a parameterized SQL query and return rows. Use `placeholder(index)`
to generate database-specific bind parameters.

**`DbClient.fetch_all`**

```mojo
def fetch_all(
    self, sql: String, params: List[String] = List[String]()
) raises -> PgRows:
```
Return all rows from a parameterized query as a result collection.

**`DbClient.fetch_one`**

```mojo
def fetch_one(
    self, sql: String, params: List[String] = List[String]()
) raises -> Optional[List[Optional[String]]]:
```
Return the first result row, or `None` if none exists. Returned values
are nullable text strings. Add `LIMIT 1` for large results.

**`DbClient.insert`**

```mojo
def insert(
    self, table: String, columns: List[String], values: List[String]
) raises:
```
Insert a record using validated SQL identifiers and bound values.

**`DbClient.update`**

```mojo
def update(
    self,
    table: String,
    columns: List[String],
    values: List[String],
    where_column: String,
    where_value: String,
) raises:
```
Update rows matching a mandatory equality predicate with bound values.

**`DbClient.delete`**

```mojo
def delete(
    self, table: String, where_column: String, where_value: String
) raises:
```
Delete rows matching a mandatory equality predicate. Unrestricted deletion
is not supported by this helper.

**`DbClient.query_text`**

```mojo
def query_text(
self, sql: String, params: List[String] = List[String]()
) raises -> PgRows:
```
Compatibility alias returning UTF-8 text and SQL NULL results; prefer `query()`.

**`DbClient.placeholder`**

```mojo
def placeholder(self, index: Int) raises -> String:
```
Return a native bound placeholder; 1-indexed positions.

**`DbClient.identifier`**

```mojo
def identifier(self, value: String) raises -> String:
```
Conservative identifier quoting across all three engines.

**`DbClient.begin`**

```mojo
def begin(mut self) raises:
```
Begin a transaction on the owned connection.

**`DbClient.commit`**

```mojo
def commit(mut self) raises:
```
Commit the current transaction.

**`DbClient.rollback`**

```mojo
def rollback(mut self) raises:
```
Roll back the current transaction.

**`DbClient.savepoint`**

```mojo
def savepoint(self, name: String) raises:
```
Create a named savepoint within the current transaction.

**`DbClient.rollback_to`**

```mojo
def rollback_to(self, name: String) raises:
```
Undo changes since a savepoint while keeping the transaction open.

**`DbClient.release_savepoint`**

```mojo
def release_savepoint(self, name: String) raises:
```
Release an existing savepoint without committing the transaction.

**`open_database`**

```mojo
def open_database(config: DatabaseSettings) raises -> DbClient:
```
Open a database client using validated connection settings.

**`open_read_pool`**

```mojo
def open_read_pool(
config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
) raises -> SqliteReadPool:
```
Opt-in bounded, read-only SQLite pool for single-value parameterized reads.

**`open_network_read_pool`**

```mojo
def open_network_read_pool(
config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
) raises -> NetworkReadPool:
```
Opt-in, bounded PostgreSQL/MySQL read-only lookup pool.

## `mojara.forms`

[Source](../../source/mojara/forms.mojo)

### `FormFields`

Parsed key/value pairs; get_first returns None when a key is absent.

**`FormFields.__init__`**

```mojo
def __init__(out self):
```
Initialize a collection of decoded form fields.

**`FormFields.count`**

```mojo
def count(self) -> Int:
```
Return the total number of decoded fields.

**`FormFields.get_first`**

```mojo
def get_first(self, key: String) -> Optional[String]:
```
Return the first value for a field or None if absent.

**`parse_form_encoded`**

```mojo
def parse_form_encoded(
body: String, max_bytes: Int = 65536, max_fields: Int = 64
) raises -> FormFields:
```
Decode and validate a bounded URL-encoded form body.

**`parse_form`**

```mojo
def parse_form(
    req: Request, max_bytes: Int = 65536, max_fields: Int = 64
) raises -> FormFields:
```
Parse an HTTP URL-encoded form with defaults of 64 KiB and 64 fields.
Use keyword parameters to override limits when necessary.

**`parse_request_form`**

```mojo
def parse_request_form(
req: Request, max_bytes: Int = 65536, max_fields: Int = 64
) raises -> FormFields:
```
Compatibility alias for `parse_form()`.

## `mojara.lifecycle`

[Source](../../source/mojara/lifecycle.mojo)

**`begin_http_drain`**

```mojo
def begin_http_drain() raises:
```
Mark this process unready until its next restart.

**`is_http_draining`**

```mojo
def is_http_draining() raises -> Bool:
```
Report whether the current process is draining HTTP requests.

**`handler_in_flight`**

```mojo
def handler_in_flight() raises -> UInt64:
```
Includes the request reading this value when metrics are enabled.

## `mojara.logging`

[Source](../../source/mojara/logging.mojo)

**`log`**

```mojo
def log(
level: String, event: String, message: String = "", request_id: String = ""
) raises:
```
Write one JSON object to stdout with a stable field structure.

## `mojara.migrations`

[Source](../../source/mojara/migrations.mojo)

**`ensure_migrations`**

```mojo
def ensure_migrations(db: Database) raises:
```
Create the migration ledger if missing.

**`is_applied`**

```mojo
def is_applied(db: Database, version: Int) raises -> Bool:
```
Check whether a positive migration version was committed.

**`applied_versions`**

```mojo
def applied_versions(db: Database) raises -> List[Int]:
```
List committed migrations in ascending version order.

**`migrate`**

```mojo
def migrate(db: Database, version: Int, up_sql: String) raises -> Bool:
```
Apply trusted SQL once, atomically registering its version.

**`rollback_migration`**

```mojo
def rollback_migration(db: Database, version: Int, down_sql: String) raises -> Bool:
```
Apply explicit trusted reverse SQL and remove one migration record.

