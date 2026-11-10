"""Native Mojo test of the concise, portable SQL API on all three engines."""
from std.os import getenv
from mojara.config import DatabaseSettings
from mojara.dbclient import open_database


def expect(ok: Bool, description: String) raises:
    if not ok:
        raise Error("Clean DbClient API test failed: " + description)


def main() raises:
    var driver = getenv("MOJARA_CLEAN_DRIVER", "sqlite")
    var config = DatabaseSettings(
        driver,
        getenv("MOJARA_CLEAN_SQLITE", "/tmp/mojara-clean-api-test.sqlite3"),
        getenv("MOJARA_CLEAN_PG_DSN", ""),
        "info",
        getenv("MOJARA_CLEAN_MYSQL_HOST", "127.0.0.1"),
        Int(getenv("MOJARA_CLEAN_MYSQL_PORT", "3306")),
        getenv("MOJARA_CLEAN_MYSQL_USER", ""),
        getenv("MOJARA_CLEAN_MYSQL_PASSWORD", ""),
        getenv("MOJARA_CLEAN_MYSQL_DATABASE", ""),
    )
    var db = open_database(config)
    db.execute(
        "CREATE TABLE mojara_clean_api_test ("
        "id VARCHAR(64) PRIMARY KEY, name VARCHAR(128) NOT NULL, note TEXT)"
    )

    var columns = List[String]()
    columns.append("id")
    columns.append("name")
    columns.append("note")
    var values = List[String]()
    values.append("1")
    values.append("First")
    values.append("O'Brien")
    db.insert("mojara_clean_api_test", columns, values)

    var params = List[String]()
    params.append("1")
    var where_sql = "SELECT name, note FROM mojara_clean_api_test WHERE id = "
        + db.placeholder(1)
    var result = db.query(where_sql, params)
    expect(result.row_count() == 1, "query() result count")
    expect(result.cell(0, 1).value() == "O'Brien", "quoted bound value")
    var legacy_result = db.query_text(where_sql, params)
    expect(legacy_result.row_count() == 1, "query_text() compatibility")

    var all_rows = db.fetch_all("SELECT name FROM mojara_clean_api_test")
    expect(all_rows.row_count() == 1, "fetch_all() returns all records")
    var first = db.fetch_one(where_sql, params)
    expect(Bool(first), "fetch_one() should return a row")
    expect(len(first.value()) == 2, "fetch_one() column count")
    expect(first.value()[0].value() == "First", "fetch_one() row content")

    var missing_args = List[String]()
    missing_args.append("not-present")
    var missing = db.fetch_one(where_sql, missing_args)
    expect(not Bool(missing), "fetch_one() returns None for no matches")

    var fields = List[String]()
    fields.append("name")
    var updates = List[String]()
    updates.append("Updated")
    db.update("mojara_clean_api_test", fields, updates, "id", "1")
    var changed = db.fetch_one(where_sql, params)
    expect(changed.value()[0].value() == "Updated", "update() changed name")

    var malicious_identifier_refused = False
    try:
        db.delete("mojara_clean_api_test; DROP TABLE users", "id", "1")
    except:
        malicious_identifier_refused = True
    expect(malicious_identifier_refused, "unsafe identifier rejected")

    db.delete("mojara_clean_api_test", "id", "1")
    var empty = db.fetch_all("SELECT id FROM mojara_clean_api_test")
    expect(empty.row_count() == 0, "delete() removed row")

    db.execute("DROP TABLE mojara_clean_api_test")
    print("PASS Mojo Clean SQL API:", driver)
