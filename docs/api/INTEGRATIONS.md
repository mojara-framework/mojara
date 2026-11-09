# Mojara API reference: integrations, pools, web and security

This reference covers the first-party Mojo declarations for databases, runtime services, schemas, security, and web utilities. See the [API reference index](../API-REFERENCE.md) for all modules.

## `mojara.model_schema`

[Source](../../source/mojara/model_schema.mojo)

### `Column`

Portable SQL column definition with key, nullability, type and foreign-reference constraints.

**`Column.__init__`**

```mojo
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
```
Describe a typed SQL column and its portable constraints.

**`Column.__init__`**

```mojo
def __init__(out self, *, copy: Self):
```
Copy this value while preserving its resource ownership contract.

**`Column.sql`**

```mojo
def sql(self, db: DbClient) raises -> String:
```
Generate driver-specific SQL for this validated column definition.

### `Table`

Validated table definition that plans SQL schema changes for the selected database.

**`Table.__init__`**

```mojo
def __init__(out self, name: String) raises:
```
Create a table declaration with a validated identifier.

**`Table.__init__`**

```mojo
def __init__(out self, *, copy: Self):
```
Copy this value while preserving its resource ownership contract.

**`Table.add`**

```mojo
def add(mut self, column: Column) raises:
```
Add a column while rejecting duplicate names and primary keys.

**`Table.id`**

```mojo
def id(mut self, name: String = "id") raises:
```
Add an automatically generated integer primary key.

**`Table.string`**

```mojo
def string(
mut self,
name: String,
width: Int = 255,
required: Bool = False,
unique: Bool = False,
) raises:
```
Add a bounded string column with optional uniqueness.

**`Table.integer`**

```mojo
def integer(
mut self, name: String, required: Bool = False, unique: Bool = False
) raises:
```
Add an integer column with optional uniqueness.

**`Table.bigint`**

```mojo
def bigint(
mut self, name: String, required: Bool = False, unique: Bool = False
) raises:
```
Add a 64-bit integer column with optional uniqueness.

**`Table.text`**

```mojo
def text(mut self, name: String, required: Bool = False) raises:
```
Add a text column, optionally requiring a value.

**`Table.boolean`**

```mojo
def boolean(mut self, name: String, required: Bool = False) raises:
```
Add a Boolean column in the selected database representation.

**`Table.timestamp`**

```mojo
def timestamp(mut self, name: String, required: Bool = False) raises:
```
Add a timestamp column in the selected database representation.

**`Table.foreign_bigint`**

```mojo
def foreign_bigint(
mut self,
name: String,
target_table: String,
target_column: String = "id",
required: Bool = True,
on_delete: String = "RESTRICT",
) raises:
```
Add a foreign-key column with explicit delete behavior.

**`Table.create_sql`**

```mojo
def create_sql(self, db: DbClient) raises -> String:
```
Generate a CREATE TABLE IF NOT EXISTS statement.

**`Table.existing_columns`**

```mojo
def existing_columns(self, db: DbClient) raises -> List[String]:
```
Inspect the existing column names in database metadata.

**`Table.plan`**

```mojo
def plan(self, db: DbClient) raises -> List[String]:
```
Only additive operations; never drop columns or change existing types.

### `Schema`

Ordered collection of table definitions for planning and applying schema changes.

**`Schema.__init__`**

```mojo
def __init__(out self):
```
Create an empty sequence of table declarations.

**`Schema.add`**

```mojo
def add(mut self, table: Table) raises:
```
Add a table declaration and reject duplicate table names.

**`Schema.plan`**

```mojo
def plan(self, db: DbClient) raises -> List[String]:
```
Generate preview statements without changing the database.

**`Schema.sync`**

```mojo
def sync(self, db: DbClient) raises -> Int:
```
Apply additive create-table and add-column operations.

**`ensure_migration_history`**

```mojo
def ensure_migration_history(db: DbClient) raises:
```
Create the migration history table if it is absent.

**`migration_applied`**

```mojo
def migration_applied(db: DbClient, version: String) raises -> Bool:
```
Check whether a named SQL migration has already run.

**`manual_migration`**

```mojo
def manual_migration(mut db: DbClient, version: String, sql: String) raises -> Bool:
```
Run trusted developer SQL once, with ledger tracking.

**`manual_migration_file`**

```mojo
def manual_migration_file(
mut db: DbClient,
version: String,
file_path: String,
) raises -> Bool:
```
Apply a one-statement .sql file; values must use bound parameters elsewhere.

## `mojara.mysql`

[Source](../../source/mojara/mysql.mojo)

### `MysqlConnection`

Owned MySQL connection backed by the native client bridge.

**`MysqlConnection.__init__`**

```mojo
def __init__(
out self,
host: String,
port: Int,
user: String,
password: String,
database: String,
) raises:
```
Open one MySQL connection and retain its native client library.

**`MysqlConnection.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`MysqlConnection.query`**

```mojo
def query(
self, sql: String, params: List[String] = List[String]()
) raises -> PgRows:
```
Execute a prepared query and detach text or NULL results.

**`MysqlConnection.execute`**

```mojo
def execute(self, sql: String, params: List[String] = List[String]()) raises:
```
Execute prepared SQL with bound parameter values.

**`MysqlConnection.transaction`**

```mojo
def transaction(self, action: Int) raises:
```
1 = begin, 2 = commit, 3 = rollback (native Connector/C API).

## `mojara.network_pool`

[Source](../../source/mojara/network_pool.mojo)

### `NetworkPoolStats`

Snapshot of read-pool capacity, contention, queries and error counters.

### `NetworkReadPool`

Bounded PostgreSQL or MySQL read pool with connection leases and wait timeouts.

**`NetworkReadPool.__init__`**

```mojo
def __init__(
out self, config: DatabaseSettings, connections: Int = 4, wait_ms: Int = 3000
) raises:
```
Initialize a bounded native PostgreSQL or MySQL read pool.

**`NetworkReadPool.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`NetworkReadPool.begin_shutdown`**

```mojo
def begin_shutdown(self) raises:
```
Irreversibly stop accepting new leases; active operations finish.

**`NetworkReadPool.stats`**

```mojo
def stats(self) raises -> NetworkPoolStats:
```
Return capacity, active lease, wait, and failure counters.

**`NetworkReadPool.query_one_text`**

```mojo
def query_one_text(self, sql: String, param: String) raises -> Optional[String]:
```
Return one text column from the first row, or None for NULL/no row.

## `mojara.orm`

[Source](../../source/mojara/orm.mojo)

**`quoted_identifier`**

```mojo
def quoted_identifier(name: String) raises -> String:
```
Validate an ASCII SQL identifier, then quote it for SQLite.

**`count_models`**

```mojo
def count_models(db: Database, table: String) raises -> Int:
```
Count rows in a table without loading model objects.

**`delete_by_id`**

```mojo
def delete_by_id(db: Database, table: String, id: Int) raises:
```
Delete a row via a bound integer key.

**`update_text_by_id`**

```mojo
def update_text_by_id(
db: Database, table: String, column: String, id: Int, value: String
) raises:
```
Safely update a text column; SQL identifiers and values are distinct.

### `QueryBuilder`

Typed, parameterized SQLite filtering and deterministic pagination.

**`QueryBuilder.__init__`**

```mojo
def __init__(out self, table: String) raises:
```
Create a query for a model table with an integer key.

**`QueryBuilder.where_int`**

```mojo
def where_int(mut self, column: String, number: Int, op: String = "=") raises:
```
Add a bound integer predicate.

**`QueryBuilder.where_text`**

```mojo
def where_text(mut self, column: String, value: String, op: String = "=") raises:
```
Add a bound text predicate.

**`QueryBuilder.where_null`**

```mojo
def where_null(mut self, column: String, is_not_null: Bool = False) raises:
```
Add a validated IS NULL predicate.

**`QueryBuilder.order_by`**

```mojo
def order_by(mut self, column: String, descending: Bool = False) raises:
```
Set a validated sort column and direction.

**`QueryBuilder.limit`**

```mojo
def limit(mut self, maximum: Int) raises:
```
Restrict the number of returned records.

**`QueryBuilder.offset`**

```mojo
def offset(mut self, skip: Int) raises:
```
Skip a validated number of records.

**`QueryBuilder.page`**

```mojo
def page(mut self, number: Int, page_size: Int = 25) raises:
```
Select records using validated page and page-size values.

**`QueryBuilder.count`**

```mojo
def count(self, db: Database) raises -> Int:
```
Count records matching the accumulated conditions.

**`QueryBuilder.exists`**

```mojo
def exists(self, db: Database) raises -> Bool:
```
Test whether any record matches the conditions.

**`QueryBuilder.ids`**

```mojo
def ids(self, db: Database) raises -> List[Int]:
```
Read the integer identifiers of matching records.

### `Repository`

A typed table facade over an explicitly supplied SQLite connection.

**`Repository.__init__`**

```mojo
def __init__(out self, table: String) raises:
```
Associate a typed model with a database and table.

**`Repository.query`**

```mojo
def query(self) raises -> QueryBuilder:
```
Start a safe, typed query for this repository.

**`Repository.create`**

```mojo
def create(self, db: Database) raises:
```
Create the reflected SQLite table for the model.

**`Repository.add`**

```mojo
def add(self, db: Database, value: Self.T) raises:
```
Insert a model using bound field values.

**`Repository.all`**

```mojo
def all(self, db: Database) raises -> List[Self.T]:
```
Load all model records from the repository table.

**`Repository.by_id`**

```mojo
def by_id(self, db: Database, id: Int) raises -> List[Self.T]:
```
Load one model record using its integer key.

**`Repository.count`**

```mojo
def count(self, db: Database) raises -> Int:
```
Return the number of records in the repository table.

**`Repository.delete_id`**

```mojo
def delete_id(self, db: Database, id: Int) raises:
```
Delete a record using its integer key.

**`Repository.update_text`**

```mojo
def update_text(self, db: Database, column: String, id: Int, value: String) raises:
```
Update a validated text column for one record.

## `mojara.portable`

[Source](../../source/mojara/portable.mojo)

### `PortableTable`

Portable accessor for an id/name table across supported SQL database drivers.

**`PortableTable.__init__`**

```mojo
def __init__(out self, name: String) raises:
```
Construct a portable accessor for a validated table.

**`PortableTable.create`**

```mojo
def create(self, db: DbClient) raises:
```
Create a compatible (id INTEGER, name VARCHAR(255)) schema.

**`PortableTable.insert`**

```mojo
def insert(self, db: DbClient, id: Int, name: String) raises:
```
Insert an integer identifier and text value using parameters.

**`PortableTable.update`**

```mojo
def update(self, db: DbClient, id: Int, name: String) raises:
```
Update a text value by its integer key.

**`PortableTable.delete`**

```mojo
def delete(self, db: DbClient, id: Int) raises:
```
Remove a record using its integer key.

**`PortableTable.by_id`**

```mojo
def by_id(self, db: DbClient, id: Int) raises -> PgRows:
```
Retrieve one text value by its integer key.

**`PortableTable.page`**

```mojo
def page(self, db: DbClient, number: Int, page_size: Int = 25) raises -> PgRows:
```
Fetch a bounded, ordered page of records.

## `mojara.postgres`

[Source](../../source/mojara/postgres.mojo)

### `PgRows`

Detached result values: valid after libpq's PGresult is released.

**`PgRows.__init__`**

```mojo
def __init__(
out self, var columns: List[String], var rows: List[List[Optional[String]]]
):
```
Take ownership of detached column names and result rows.

**`PgRows.row_count`**

```mojo
def row_count(self) -> Int:
```
Return the number of materialized rows.

**`PgRows.column_count`**

```mojo
def column_count(self) -> Int:
```
Return the number of result columns.

**`PgRows.cell`**

```mojo
def cell(self, row: Int, column: Int) raises -> Optional[String]:
```
Get a text or NULL cell after validating its indices.

### `PgConnection`

One PostgreSQL connection, with automatic PQfinish cleanup.

**`PgConnection.__init__`**

```mojo
def __init__(out self, conninfo: String) raises:
```
Open a PostgreSQL connection using a validated connection string.

**`PgConnection.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`PgConnection.query`**

```mojo
def query(
self, sql: String, params: List[String] = List[String]()
) raises -> PgRows:
```
Execute trusted SQL using libpq parameter binding for all data.

**`PgConnection.execute`**

```mojo
def execute(self, sql: String, params: List[String] = List[String]()) raises:
```
Execute trusted SQL and dispose of any returned rows.

**`open_postgres`**

```mojo
def open_postgres(conninfo: String) raises -> PgConnection:
```
Open a new connection; callers own it until it goes out of scope.

## `mojara.relations`

[Source](../../source/mojara/relations.mojo)

**`create_join_table`**

```mojo
def create_join_table(
db: Database,
junction: String,
left_table: String,
left_key: String,
right_table: String,
right_key: String,
) raises:
```
Create an explicit many-to-many table with restrictive names and FKs.

**`link`**

```mojo
def link(
db: Database,
junction: String,
left_key: String,
right_key: String,
left_id: Int,
right_id: Int,
) raises:
```
Attach a pair; repeated attachments are harmless with the join table PK.

**`unlink`**

```mojo
def unlink(
db: Database,
junction: String,
left_key: String,
right_key: String,
left_id: Int,
right_id: Int,
) raises:
```
Detach a pair without deleting either related model.

**`related_ids`**

```mojo
def related_ids(
db: Database,
junction: String,
from_key: String,
to_key: String,
source_id: Int,
) raises -> List[Int]:
```
Return associated IDs ordered ascending, with bound relationship key.

**`children`**

```mojo
def children(table: String, foreign_key: String, parent_id: Int) raises -> QueryBuilder:
```
One-to-many: query child models by the parent's integer primary key.

**`parent_id`**

```mojo
def parent_id(
db: Database,
child_table: String,
foreign_key: String,
child_id: Int,
) raises -> Optional[Int]:
```
Many-to-one: find the referenced parent's ID for a given child.

**`create_unique_relation_index`**

```mojo
def create_unique_relation_index(
db: Database,
index_name: String,
child_table: String,
foreign_key: String,
) raises:
```
Enforce one-to-one cardinality for non-NULL foreign keys.

## `mojara.runtime`

[Source](../../source/mojara/runtime.mojo)

**`parse_runtime_number`**

```mojo
def parse_runtime_number(
text: String, label: String, minimum: Int, maximum: Int
) raises -> Int:
```
Parse bounded positive decimal settings without permissive coercions.

### `RuntimeSettings`

Validated network listener and Flare worker settings.

**`RuntimeSettings.__init__`**

```mojo
def __init__(out self, host: String, port: UInt16, workers: Int) raises:
```
Initialize or copy HTTP listener and worker settings.

**`RuntimeSettings.__init__`**

```mojo
def __init__(out self, *, copy: Self):
```
Copy this value while preserving its resource ownership contract.

**`load_runtime_settings`**

```mojo
def load_runtime_settings(
host: String = "127.0.0.1", port: UInt16 = 8000, workers: Int = 1
) raises -> RuntimeSettings:
```
Read process env overrides, preserving AppConfig values as defaults.

## `mojara.schema`

[Source](../../source/mojara/schema.mojo)

**`add_column`**

```mojo
def add_column(
db: Database,
table: String,
column: String,
sqlite_type: String,
) raises:
```
Add a nullable scalar column. Backfills and constraints are explicit SQL.

**`rename_column`**

```mojo
def rename_column(
db: Database,
table: String,
previous: String,
replacement: String,
) raises:
```
Rename an existing SQLite column using validated identifiers.

**`rename_table`**

```mojo
def rename_table(db: Database, previous: String, replacement: String) raises:
```
Rename an SQLite table using validated identifiers.

**`create_index`**

```mojo
def create_index(
db: Database,
index_name: String,
table: String,
column: String,
unique: Bool = False,
) raises:
```
Create a named index on validated table columns.

**`drop_index`**

```mojo
def drop_index(db: Database, index_name: String) raises:
```
Drop a validated named SQLite index.

## `mojara.security`

[Source](../../source/mojara/security.mojo)

**`json_body`**

```mojo
def json_body(req: Request) raises -> Value:
```
Parse JSON, rejecting non-JSON content types and malformed bodies.

**`required_string`**

```mojo
def required_string(obj: Value, key: String) raises -> String:
```
Retrieve a required string field, rejecting absent/non-string fields.

**`bearer_token`**

```mojo
def bearer_token(req: Request) -> String:
```
Extract a Bearer token; credentials must be checked by the app.

**`require_bearer`**

```mojo
def require_bearer(req: Request, expected: String) raises -> Response:
```
Example fixed-token authentication; use verified identity in production.

## `mojara.sqlite_pool`

[Source](../../source/mojara/sqlite_pool.mojo)

### `SqlitePoolStats`

Atomic snapshot under the native pool mutex, valid until close.

### `SqliteReadPool`

Bounded, file-backed SQLite read pool with timed connection acquisition.

**`SqliteReadPool.__init__`**

```mojo
def __init__(
out self, path: String, connections: Int = 4, wait_ms: Int = 3000
) raises:
```
Open bounded read-only connections to an existing SQLite file.

**`SqliteReadPool.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`SqliteReadPool.begin_shutdown`**

```mojo
def begin_shutdown(self) raises:
```
Prevent new leases. Existing queries can finish before pool cleanup.

**`SqliteReadPool.stats`**

```mojo
def stats(self) raises -> SqlitePoolStats:
```
Read pool occupancy, contention and lifetime-query statistics.

**`SqliteReadPool.query_one_text`**

```mojo
def query_one_text(self, sql: String, param: String) raises -> Optional[String]:
```
Return first TEXT field; NULL/no row becomes None. Read only.

**`pooled_benchmark_lookup`**

```mojo
def pooled_benchmark_lookup(path: String, connections: Int = 4) raises -> String:
```
Benchmark-only process-lifetime reuse; never accepts paths from requests.

## `mojara.telemetry`

[Source](../../source/mojara/telemetry.mojo)

**`metrics_snapshot_json`**

```mojo
def metrics_snapshot_json() raises -> String:
```
Return atomic-counter snapshot (non-transactional across fields).

## `mojara.txpool`

[Source](../../source/mojara/txpool.mojo)

### `DbResult`

Owns a materialized query result, independent of its connection lease.

**`DbResult.__init__`**

```mojo
def __init__(
out self,
pool: Pointer[NoneType, MutUntrackedOrigin],
token: UInt64,
var sql: String,
) raises:
```
Execute a query on a pool lease and own the materialized result.

**`DbResult.__init__`**

```mojo
def __init__(
out self,
pool: Pointer[NoneType, MutUntrackedOrigin],
token: UInt64,
var sql: String,
var a: String,
) raises:
```
Execute a query on a pool lease and own the materialized result.

**`DbResult.__init__`**

```mojo
def __init__(
out self,
pool: Pointer[NoneType, MutUntrackedOrigin],
token: UInt64,
var sql: String,
var a: String,
var b: String,
) raises:
```
Execute a query on a pool lease and own the materialized result.

**`DbResult.__init__`**

```mojo
def __init__(
out self,
pool: Pointer[NoneType, MutUntrackedOrigin],
token: UInt64,
var sql: String,
var a: String,
var b: String,
var c: String,
) raises:
```
Execute a query on a pool lease and own the materialized result.

**`DbResult.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`DbResult.rows`**

```mojo
def rows(self) -> Int:
```
Return the number of query-result rows.

**`DbResult.columns`**

```mojo
def columns(self) -> Int:
```
Return the number of query-result columns.

**`DbResult.affected`**

```mojo
def affected(self) -> UInt64:
```
Report the affected-row count when supported.

**`DbResult.is_null`**

```mojo
def is_null(self, row: Int, col: Int) raises -> Bool:
```
Test whether the selected SQL cell is NULL.

**`DbResult.cell`**

```mojo
def cell(self, row: Int, col: Int) raises -> String:
```
Read a text cell from the materialized result.

**`DbResult.column_name`**

```mojo
def column_name(self, col: Int) raises -> String:
```
Return the result column name at a valid index.

### `DbLease`

A thread-affine, move-only transaction lease with rollback on destruction.

**`DbLease.__init__`**

```mojo
def __init__(
out self,
pool: Pointer[NoneType, MutUntrackedOrigin],
timeout_ms: Int,
) raises:
```
Bind a checked-out connection to its pool and acquiring thread.

**`DbLease.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`DbLease.release`**

```mojo
def release(mut self) raises:
```
Return the connection to the pool; roll back unfinished work.

**`DbLease.begin`**

```mojo
def begin(self) raises:
```
Begin a transaction using the checked-out connection.

**`DbLease.commit`**

```mojo
def commit(self) raises:
```
Commit the lease transaction.

**`DbLease.rollback`**

```mojo
def rollback(self) raises:
```
Roll back the lease transaction.

**`DbLease.query`**

```mojo
def query(self, sql: String) raises -> DbResult:
```
Execute developer-controlled SQL without bound values.

**`DbLease.query1`**

```mojo
def query1(self, sql: String, a: String) raises -> DbResult:
```
Execute SQL with one bound text parameter.

**`DbLease.query2`**

```mojo
def query2(self, sql: String, a: String, b: String) raises -> DbResult:
```
Execute SQL with two bound text parameters.

**`DbLease.query3`**

```mojo
def query3(
self,
sql: String,
a: String,
b: String,
c: String,
) raises -> DbResult:
```
Execute SQL with three bound text parameters.

### `PooledDatabase`

Owns a bounded PostgreSQL or MySQL connection pool.

**`PooledDatabase.__init__`**

```mojo
def __init__(out self, var postgres_dsn: String, capacity: Int = 4) raises:
```
Initialize a bounded native database transaction pool.

**`PooledDatabase.__init__`**

```mojo
def __init__(
out self,
var mysql_host: String,
mysql_port: Int,
var mysql_user: String,
var mysql_password: String,
var mysql_database: String,
capacity: Int = 4,
) raises:
```
Initialize a bounded native database transaction pool.

**`PooledDatabase.__deinit__`**

```mojo
def __deinit__(deinit self):
```
**`PooledDatabase.acquire`**

```mojo
def acquire(self, timeout_ms: Int = 3000) raises -> DbLease:
```
Borrow a connection, waiting up to the configured timeout.

**`PooledDatabase.capacity`**

```mojo
def capacity(self) raises -> Int:
```
Return the configured connection capacity.

**`PooledDatabase.active_leases`**

```mojo
def active_leases(self) raises -> Int:
```
Return the number of currently checked-out connections.

**`PooledDatabase.close`**

```mojo
def close(mut self) raises:
```
Close the pool after every lease has returned.

## `mojara.web`

[Source](../../source/mojara/web.mojo)

### `Templates`

HTML template loader restricted to a configured trusted directory.

**`Templates.__init__`**

```mojo
def __init__(out self, directory: String = "templates") raises:
```
Choose the trusted template source directory.

**`Templates.render`**

```mojo
def render(self, filename: String, var context: TemplateContext) raises -> Response:
```
Render a validated HTML template with the provided context.

### `StaticFile`

Serve files by a single router parameter named `name`. No traversal.

**`StaticFile.__init__`**

```mojo
def __init__(out self, root: String, max_bytes: Int = 2 * 1024 * 1024):
```
Configure a static-file handler rooted at a trusted directory.

**`StaticFile.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Serve a validated filename from the configured static directory.

### `UploadFile`

Private single-file multipart endpoint. Server generates the filename.

**`UploadFile.__init__`**

```mojo
def __init__(
out self,
directory: String,
max_bytes: Int = 2 * 1024 * 1024,
required_token: String = "",
):
```
Configure a bounded single-file upload handler.

**`UploadFile.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Validate and persist one multipart file.

### `UploadFiles`

Atomic multi-file multipart endpoint with private generated filenames.

**`UploadFiles.__init__`**

```mojo
def __init__(
out self,
directory: String,
max_file_bytes: Int = 2 * 1024 * 1024,
max_total_bytes: Int = 8 * 1024 * 1024,
max_files: Int = 5,
required_token: String = "",
allowed_mime_types: String = "",
) raises:
```
Configure limits for a multi-file upload handler.

**`UploadFiles.serve`**

```mojo
def serve(self, req: Request) raises -> WireResponse:
```
Validate and persist a bounded multipart file collection.

