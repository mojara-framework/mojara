"""Validated environment-based database configuration.

DatabaseSettings holds connection information for SQLite, MySQL and
PostgreSQL. Database credentials are read from the process environment."""

from std.os import getenv


struct DatabaseSettings(Copyable):
    var driver: String
    var sqlite_path: String
    var postgres_dsn: String
    var log_level: String
    var mysql_host: String
    var mysql_port: Int
    var mysql_user: String
    var mysql_password: String
    var mysql_database: String

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
        """Initialize a database configuration or copy an existing one."""
        if driver != "sqlite" and driver != "postgres" and driver != "mysql":
            raise Error("MOJARA_DB_DRIVER must be sqlite, postgres or mysql")
        if driver == "sqlite" and sqlite_path.byte_length() == 0:
            raise Error("MOJARA_SQLITE_PATH is required")
        if driver == "postgres" and postgres_dsn.byte_length() == 0:
            raise Error("MOJARA_POSTGRES_DSN is required")
        if driver == "mysql":
            if mysql_port < 1 or mysql_port > 65535:
                raise Error("MySQL port must be between 1 and 65535")
            if (
                mysql_host.byte_length() == 0
                or mysql_user.byte_length() == 0
                or mysql_database.byte_length() == 0
            ):
                raise Error("MOJARA_MYSQL_HOST, USER and DATABASE are required")
        if (
            log_level != "debug"
            and log_level != "info"
            and log_level != "warn"
            and log_level != "error"
        ):
            raise Error("MOJARA_LOG_LEVEL must be debug, info, warn or error")
        self.driver = driver
        self.sqlite_path = sqlite_path
        self.postgres_dsn = postgres_dsn
        self.log_level = log_level
        self.mysql_host = mysql_host
        self.mysql_port = mysql_port
        self.mysql_user = mysql_user
        self.mysql_password = mysql_password
        self.mysql_database = mysql_database

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        self.driver = copy.driver
        self.sqlite_path = copy.sqlite_path
        self.postgres_dsn = copy.postgres_dsn
        self.log_level = copy.log_level
        self.mysql_host = copy.mysql_host
        self.mysql_port = copy.mysql_port
        self.mysql_user = copy.mysql_user
        self.mysql_password = copy.mysql_password
        self.mysql_database = copy.mysql_database


def _mysql_port(text: String) raises -> Int:
    if text.byte_length() == 0 or text.byte_length() > 5:
        raise Error("Invalid MOJARA_MYSQL_PORT")
    var number = 0
    for i in range(text.byte_length()):
        var digit = Int(text.as_bytes()[i]) - 48
        if digit < 0 or digit > 9:
            raise Error("Invalid MOJARA_MYSQL_PORT")
        number = number * 10 + digit
    if number < 1 or number > 65535:
        raise Error("Invalid MOJARA_MYSQL_PORT")
    return number


def load_database_settings() raises -> DatabaseSettings:
    """Read database settings at application startup, never log the DSN."""
    var driver = getenv("MOJARA_DB_DRIVER", "sqlite")
    var port = 3306
    if driver == "mysql":
        port = _mysql_port(getenv("MOJARA_MYSQL_PORT", "3306"))
    return DatabaseSettings(
        driver,
        getenv("MOJARA_SQLITE_PATH", "app.db"),
        getenv("MOJARA_POSTGRES_DSN", ""),
        getenv("MOJARA_LOG_LEVEL", "info"),
        getenv("MOJARA_MYSQL_HOST", "127.0.0.1"),
        port,
        getenv("MOJARA_MYSQL_USER", ""),
        getenv("MOJARA_MYSQL_PASSWORD", ""),
        getenv("MOJARA_MYSQL_DATABASE", ""),
    )
