"""Mojara database integration: live PostgreSQL and MariaDB service tests."""

from std.os import getenv
from mojara.postgres import PgConnection
from mojara.mysql import MysqlConnection


def main() raises:
    var pg_dsn = getenv("MOJARA_CI_PG_DSN", "")
    var mysql_host = getenv("MOJARA_CI_MYSQL_HOST", "127.0.0.1")
    var mysql_password = getenv("MOJARA_CI_MYSQL_PASSWORD", "")
    if pg_dsn == "" or mysql_password == "":
        raise Error("CI database environment variables missing")

    var pg = PgConnection(pg_dsn)
    var pg_params = List[String]()
    pg_params.append("O'Brien")
    var pg_rows = pg.query("SELECT $1::text AS bound_text", pg_params^)
    if pg_rows.row_count() != 1 or pg_rows.column_count() != 1:
        raise Error("PostgreSQL prepared query returned unexpected dimensions")
    var pg_cell = pg_rows.cell(0, 0)
    if not pg_cell or pg_cell.value() != "O'Brien":
        raise Error("PostgreSQL prepared parameter round-trip failed")
    pg.execute("BEGIN")
    pg.execute("ROLLBACK")
    print("POSTGRESQL_MOJO_INTEGRATION_PASS")

    var mysql = MysqlConnection(
        mysql_host, 3306, "mojara", mysql_password, "mojara"
    )
    var mysql_params = List[String]()
    mysql_params.append("O'Brien")
    var mysql_rows = mysql.query("SELECT ? AS bound_text", mysql_params^)
    if mysql_rows.row_count() != 1 or mysql_rows.column_count() != 1:
        raise Error("MariaDB prepared query returned unexpected dimensions")
    var mysql_cell = mysql_rows.cell(0, 0)
    if not mysql_cell or mysql_cell.value() != "O'Brien":
        raise Error("MariaDB prepared parameter round-trip failed")
    mysql.transaction(1)
    mysql.transaction(3)
    print("MARIADB_MOJO_INTEGRATION_PASS")
