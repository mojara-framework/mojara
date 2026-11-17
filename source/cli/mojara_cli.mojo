"""Mojara native CLI. Mojo 1.2.0; portable CLI build.
Builds apps using the installed Mojara SDK and watches edits using watchexec.
"""

from std.os import getenv, setenv, mkdir
from std.os.path import exists, dirname, realpath, isdir, islink
from std.os.process import Process
from std.pathlib import Path
from std.sys import argv
from std.sys.info import CompilationTarget


def _home() -> String:
    var provided = getenv("MOJARA_HOME", "")
    if provided.byte_length() > 0:
        return provided^
    var prefix = getenv("CONDA_PREFIX", "")
    if prefix.byte_length() > 0:
        var candidate = prefix + "/opt/mojara"
        if exists(candidate + "/lib/mojo/mojara.mojoc"):
            return candidate^
    return "/opt/mojara"


def _valid_name(name: String) -> Bool:
    if name.byte_length() == 0 or name.byte_length() > 64:
        return False
    for i in range(name.byte_length()):
        var c = Int(name.as_bytes()[i])
        var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
        var digit = c >= 48 and c <= 57
        if i == 0 and not letter:
            return False
        if not letter and not digit and c != 45 and c != 95:
            return False
    return True


def _stdlib_dir() raises -> String:
    var override = getenv("MOJO_STDLIB", "")
    if override.byte_length() > 0 and exists(override + "/std.mojoc"):
        return override^
    for entry in getenv("PATH", "").split(":"):
        var directory = String(entry)
        if directory.byte_length() == 0:
            continue
        var executable = directory + "/mojo"
        if not exists(executable):
            continue
        var resolved = realpath(executable)
        var library = dirname(dirname(resolved)) + "/lib/mojo"
        if exists(library + "/std.mojoc"):
            return library^
    raise Error("Mojo standard library not found. Set MOJO_STDLIB.")


def _setup_compile_env() raises:
    var home = _home()
    if getenv("MODULAR_HOME", "").byte_length() == 0:
        var compiler = dirname(dirname(_stdlib_dir()))
        _ = setenv("MODULAR_HOME", compiler + "/share/max")
    var name = "DYLD_LIBRARY_PATH" if CompilationTarget.is_macos() else "LD_LIBRARY_PATH"
    var old = getenv(name, "")
    if old.byte_length() > 0:
        _ = setenv(name, home + "/lib:" + old)
    else:
        _ = setenv(name, home + "/lib")
    # IMPORTANT: preserve Pixi/Conda's real CONDA_PREFIX for the compiler.
    # Overwriting it makes Mojo 1.2 fail to import the precompiled Mojara library.


def _setup_runtime_env() raises:
    _setup_compile_env()
    var home = _home()
    _ = setenv("MOJARA_HOME", home)
    # The JSON native dependency also probes CONDA_PREFIX/lib when running.
    _ = setenv("CONDA_PREFIX", home)


def _run(program: String, args: List[String]) raises:
    var process = Process.run(program, args)
    var result = process.wait()
    if not Bool(result.exit_code) or result.exit_code.value() != 0:
        raise Error("Command failed: " + program)


def _hello_app() -> String:
    return (
        '"""A native Mojo + Mojara web application."""\n\n'
        "from mojara import App, Request, Response, TemplateContext\n"
        "from mojara.web import StaticFile\n\n\n"
        "def home(req: Request) raises -> Response:\n"
        "    var context = TemplateContext()\n"
        '    context.set("title", "Hello from Mojara")\n'
        '    return Response.render_file("templates/index.html", context^)\n\n\n'
        "def health(req: Request) raises -> Response:\n"
        '    return Response.json(\'{"status":"ok","framework":"Mojara"}\')\n\n\n'
        "def main() raises:\n"
        "    var app = App()\n"
        '    app.get("/", home)\n'
        '    app.get("/health", health)\n'
        '    app.get_handler("/static/:name", StaticFile("static"))\n'
        "    app.run_configured()\n"
    )


def _api_app() -> String:
    return (
        '"""Mojara OpenAPI starter application."""\n\n'
        "from mojara import Request, Response\n"
        "from mojara.api import Api\n\n\n"
        "def health(req: Request) raises -> Response:\n"
        '    return Response.json(\'{"status":"ok","framework":"Mojara"}\')\n\n\n'
        "def main() raises:\n"
        '    var api = Api("Mojara Starter API", "1.2.10")\n'
        '    api.get("/", health, "Root")\n'
        '    api.get("/health", health, "Health")\n'
        "    api.install_docs()\n"
        "    api.run_configured()\n"
    )


def _db_template() -> String:
    return (
        '"""Database schema and migrations. Run: mojara db plan / migrate."""\nfrom'
        " mojara.model_schema import Schema, Table, manual_migration_file\nfrom"
        " mojara.dbclient import open_database\nfrom mojara.config import"
        " load_database_settings\nfrom std.os import getenv\nfrom std.sys import"
        ' argv\n\n\ndef main() raises:\n    if getenv("MOJARA_DB_DRIVER",'
        ' "").byte_length() == 0:\n        raise Error("Set MOJARA_DB_DRIVER to mysql,'
        ' postgres or sqlite")\n    var db = open_database(load_database_settings())\n '
        "   var schema = Schema()\n\n    # CODE-FIRST: define tables in Mojo, then add"
        ' them to schema.\n    # var users = Table("users")\n    # users.id()\n    #'
        ' users.string("username", 100, required=True, unique=True)\n    #'
        " schema.add(users)\n\n    var args = argv()\n    if len(args) > 1 and"
        ' String(args[1]) == "--plan":\n        var pending = schema.plan(db)\n       '
        ' print("Pending code-first operations:", len(pending))\n        for sql in'
        ' pending:\n            print(sql)\n        print("Manual SQL migrations:'
        ' review calls in db.mojo before applying.")\n        return\n    var count ='
        ' schema.sync(db)\n    print("Applied code-first schema changes:", count)\n\n  '
        "  # MANUAL SQL: one SQL statement per file; register each migration.\n    # _"
        ' = manual_migration_file(db, "001_custom", "migrations/001_custom.sql")\n'
    )


def _db_init() raises:
    _require_app()
    if exists("db.mojo"):
        raise Error("db.mojo already exists; refusing to overwrite schema.")
    if not exists("migrations"):
        mkdir("migrations")
    Path("db.mojo").write_text(_db_template())
    print("Created db.mojo and migrations/ (code-first and manual SQL)")
    print("Set 'database mysql|postgres|sqlite' in mojara.project.")
    print("Set database credentials or SQLite path through environment variables.")
    print("Next: edit db.mojo; run 'mojara db plan', then 'mojara db migrate'.")


def _build_db() raises:
    if not exists("db.mojo"):
        raise Error("db.mojo missing. Run 'mojara db init' first.")
    _check()
    _setup_compile_env()
    if not exists("build"):
        mkdir("build")
    var args = List[String]()
    args.append("build")
    args.append("-I")
    args.append(_home() + "/lib/mojo")
    args.append("db.mojo")
    args.append("-o")
    args.append("build/db-migrate")
    if CompilationTarget.is_linux():
        args.append("-Xlinker=-ldl")
    _run("mojo", args)
    print("Database migration runner: build/db-migrate")


def _db_action(operation: String) raises:
    _require_app()
    if operation == "init":
        _db_init()
        return
    if operation != "plan" and operation != "migrate":
        raise Error("Usage: mojara db init|plan|migrate")
    if not exists("db.mojo"):
        raise Error("db.mojo missing. Run 'mojara db init' first.")
    # Always recompile db.mojo: a previous runner may be stale after model edits.
    _build_db()
    var database = _database_kind()
    if database.byte_length() > 0 and getenv("MOJARA_DB_DRIVER", "").byte_length() == 0:
        _ = setenv("MOJARA_DB_DRIVER", database)
    _setup_runtime_env()
    if operation == "plan":
        _run("./build/db-migrate", ["--plan"])
    else:
        _run("./build/db-migrate", [])


def _new(name: String, api: Bool) raises:
    if not _valid_name(name):
        raise Error(
            "Use a name beginning with a letter; letters, digits, '-' and '_' only."
        )
    if exists(name):
        raise Error("Refusing to overwrite existing path: " + name)
    mkdir(name)
    mkdir(name + "/build")
    mkdir(name + "/static")
    mkdir(name + "/templates")
    Path(name + "/app.mojo").write_text(_api_app() if api else _hello_app())
    Path(name + "/templates/index.html").write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>{{ title }}</title>"
        '<link rel="stylesheet" href="/static/style.css"></head>'
        "<body><main><h1>{{ title }}</h1>"
        "<p>Your web application runs on native Mojo.</p></main></body></html>\n"
    )
    Path(name + "/static/style.css").write_text(
        "body{font:16px/1.5 system-ui,sans-serif;background:#fffaf3;color:#42271b;"
        "padding:50px}h1{color:#dd5c24}main{max-width:800px;margin:auto}\n"
    )
    Path(name + "/.gitignore").write_text("build/\n.mojo_cache/\n")
    Path(name + "/mojara.project").write_text("name " + name + "\nversion 1.2.10\n")
    print("Created", name)
    print("Next: cd " + name)
    print("      mojara dev")


def _check() raises:
    var home = _home()
    if not exists(home + "/lib/mojo/mojara.mojoc"):
        raise Error("Missing installed Mojara SDK: " + home)
    var suffix = ".dylib" if CompilationTarget.is_macos() else ".so"
    if not exists(home + "/lib/libmojara_web" + suffix):
        raise Error("Missing Mojara web bridge: " + home)
    print("Mojara SDK:", home)
    print("Mojo standard library:", _stdlib_dir())
    _run("mojo", ["--version"])
    print("SDK and Mojo compiler detected")


def _require_app() raises:
    if not exists("app.mojo"):
        raise Error("app.mojo not found. Run from the generated project directory.")


def _build() raises:
    _require_app()
    _check()
    _setup_compile_env()
    if not exists("build"):
        mkdir("build")
    var sdk_module_path = _home() + "/lib/mojo"
    var compiler_std_path = _stdlib_dir()
    print("Compiling with Mojara modules:", sdk_module_path)
    print("Mojo standard library:", compiler_std_path)
    var compiler_args = List[String]()
    compiler_args.append("build")
    compiler_args.append("-I")
    compiler_args.append(sdk_module_path.copy())
    compiler_args.append("app.mojo")
    compiler_args.append("-o")
    compiler_args.append("build/app")
    if CompilationTarget.is_linux():
        compiler_args.append("-Xlinker=-ldl")
    _run("mojo", compiler_args)
    print("Build successful: build/app")
    if exists("db.mojo"):
        _build_db()
    if CompilationTarget.is_linux():
        _ = _write_service()


def _project_setting(key: String, fallback: String) raises -> String:
    if not exists("mojara.project"):
        return fallback
    var config = Path("mojara.project").read_text()
    for raw in config.split("\n"):
        var parts = String(raw).split(" ")
        if len(parts) >= 2 and String(parts[0]) == key:
            return String(parts[1])
    return fallback


def _safe_identifier(raw: String) -> Bool:
    if raw.byte_length() == 0 or raw.byte_length() > 80:
        return False
    for i in range(raw.byte_length()):
        var c = Int(raw.as_bytes()[i])
        var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
        var digit = c >= 48 and c <= 57
        if not letter and not digit and c != 95 and c != 45 and c != 46:
            return False
    return True


def _project_name() raises -> String:
    var name = _project_setting("name", "")
    if not _valid_name(name):
        raise Error("mojara.project must contain a valid 'name PROJECT_NAME'")
    return name^


def _database_kind() raises -> String:
    var database = _project_setting("database", "")
    if (
        database.byte_length() > 0
        and database != "mysql"
        and database != "postgres"
        and database != "sqlite"
    ):
        raise Error("database must be mysql, postgres or sqlite in mojara.project")
    return database^


def _service_name() raises -> String:
    var service = _project_setting("service_name", "mojara-" + _project_name())
    if not _valid_name(service):
        raise Error("Invalid 'service_name' in mojara.project")
    return service^


def _deploy_path() raises -> String:
    var directory = _project_setting("deploy_path", "/srv/" + _service_name())
    if not directory.startswith("/srv/") or directory == "/srv/":
        raise Error("deploy_path must be an absolute path inside /srv/")
    if (
        directory.endswith("/")
        or len(directory.split("//")) > 1
        or len(directory.split("..")) > 1
    ):
        raise Error("Unsafe deploy_path in mojara.project")
    for i in range(directory.byte_length()):
        var c = Int(directory.as_bytes()[i])
        var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
        var digit = c >= 48 and c <= 57
        if not letter and not digit and c != 95 and c != 45 and c != 46 and c != 47:
            raise Error("Invalid character in deploy_path")
    return directory^


def _service_port() raises -> String:
    var value = _project_setting("port", "8000")
    if value.byte_length() == 0 or value.byte_length() > 5:
        raise Error("Invalid 'port' in mojara.project")
    for i in range(value.byte_length()):
        var c = Int(value.as_bytes()[i])
        if c < 48 or c > 57:
            raise Error("Port must contain only digits")
    var port = Int(value)
    if port < 1 or port > 65535:
        raise Error("Port must be between 1 and 65535")
    return value^


def _service_workers() raises -> String:
    var value = _project_setting("workers", "1")
    if value.byte_length() == 0 or value.byte_length() > 2:
        raise Error("workers must be between 1 and 64")
    for i in range(value.byte_length()):
        var ch = Int(value.as_bytes()[i])
        if ch < 48 or ch > 57:
            raise Error("workers must contain digits only")
    var count = Int(value)
    if count < 1 or count > 64:
        raise Error("workers must be between 1 and 64")
    return value^


def _service_text() raises -> String:
    var name = _service_name()
    var directory = _deploy_path()
    var user = _project_setting("service_user", "www-data")
    var group = _project_setting("service_group", "www-data")
    if not _safe_identifier(user) or not _safe_identifier(group):
        raise Error("Invalid service_user or service_group in mojara.project")
    var home = _home()
    var prefix = getenv("CONDA_PREFIX", "")
    if prefix.byte_length() == 0:
        prefix = dirname(dirname(home))
    var host = _project_setting("host", "127.0.0.1")
    if host != "127.0.0.1" and host != "0.0.0.0" and host != "::1":
        raise Error("host must be 127.0.0.1, 0.0.0.0 or ::1")
    var db_environment = String("")
    var database = _database_kind()
    if database.byte_length() > 0:
        db_environment = "Environment=MOJARA_DB_DRIVER=" + database + "\n"
    var db_prestart = String("")
    if exists("db.mojo"):
        if not exists("build/db-migrate"):
            raise Error("Missing compiled database runner. Run 'mojara build' first.")
        db_prestart = "ExecStartPre=" + directory + "/build/db-migrate\n"
    return (
        "# Generated by Mojara. 'mojara deploy' regenerates for the target host.\n"
        "[Unit]\n"
        "Description=Mojara application: "
        + name
        + "\n"
        "After=network-online.target\n"
        "Wants=network-online.target\n\n"
        "[Service]\n"
        "Type=simple\n"
        "User="
        + user
        + "\nGroup="
        + group
        + "\nWorkingDirectory="
        + directory
        + "\nExecStart="
        + directory
        + "/build/app\n"
        + db_prestart
        + "Environment=MOJARA_HOST="
        + host
        + "\nEnvironment=MOJARA_PORT="
        + _service_port()
        + "\nEnvironment=MOJARA_WORKERS="
        + _service_workers()
        + "\n"
        + db_environment
        + "Environment=MOJARA_HOME="
        + home
        + "\nEnvironment=CONDA_PREFIX="
        + home
        + "\nEnvironment=LD_LIBRARY_PATH="
        + home
        + "/lib:"
        + prefix
        + "/lib\nEnvironmentFile=-/etc/mojara/"
        + name
        + ".env\n"
        "Restart=on-failure\n"
        "RestartSec=3\n"
        "TimeoutStopSec=20\n"
        "NoNewPrivileges=true\n"
        "PrivateTmp=true\n"
        "UMask=0027\n\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n"
    )


def _write_service() raises -> String:
    var name = _service_name()
    if not exists("build"):
        mkdir("build")
    var unit = "build/" + name + ".service"
    Path(unit).write_text(_service_text())
    print("Systemd unit generated:", unit)
    return unit^


def _sudo(program: String, args: List[String]) raises:
    var command = List[String]()
    command.append(program)
    for item in args:
        command.append(item)
    _run("sudo", command)


def _unit() raises -> String:
    return _service_name() + ".service"


def _service_installed() raises -> Bool:
    return exists("/etc/systemd/system/" + _unit())


def _deploy(dry_run: Bool) raises:
    if CompilationTarget.is_macos():
        raise Error("Systemd deployment is Linux-only. Use mojara start --local.")
    _require_app()
    if not exists("build/app"):
        raise Error("Compiled app missing. Run 'mojara build' first.")
    var directory = _deploy_path()
    if exists("db.mojo") and not exists("build/db-migrate"):
        raise Error("Database runner missing. Run 'mojara build' before deployment.")
    var unit = _unit()
    var path = _write_service()
    print("Deployment directory:", directory)
    print("Systemd service:", unit)
    print("Installation requires sudo and an active systemd host.")
    if dry_run:
        print("Dry run only; no deployment files or system services changed.")
        print(
            "Would install build/app and optional static/, templates/, mojara.project."
        )
        if exists("db.mojo"):
            print(
                "Would install build/db-migrate and migrations/; systemd runs"
                " migrations before app start."
            )
        print("Would install " + path + " into /etc/systemd/system/" + unit)
        print("Would reload systemd, enable and restart " + unit)
        return
    var in_place = False
    if exists(directory):
        in_place = realpath(".") == realpath(directory)
    if in_place:
        print("Project is already at its deployment path; using existing build/app.")
    else:
        # Hold separate owned Strings before constructing subprocess arguments.
        # Mojo may reuse temporary concatenation storage in one List literal.
        var build_dir = directory + "/build"
        var staged_binary = directory + "/build/app.next"
        var live_binary = directory + "/build/app"
        _sudo("install", ["-d", "-m", "0755", directory])
        _sudo("install", ["-d", "-m", "0755", build_dir])
        _sudo("install", ["-m", "0755", "build/app", staged_binary])
        # A single validated shell command avoids Mojo 1.2.0's temporary
        # string aliasing when multiple derived path arguments are assembled.
        # deploy_path accepts only letters, digits, /, ., - and _.
        _sudo("sh", ["-c", "mv -f -- " + staged_binary + " " + live_binary])
        if exists("db.mojo"):
            var db_next = directory + "/build/db-migrate.next"
            var db_live = directory + "/build/db-migrate"
            _sudo("install", ["-m", "0755", "build/db-migrate", db_next])
            _sudo("sh", ["-c", "mv -f -- " + db_next + " " + db_live])
        if exists("migrations"):
            _sudo("install", ["-d", "-m", "0755", directory + "/migrations"])
            _sudo("cp", ["-a", "migrations/.", directory + "/migrations/"])
        if exists("templates"):
            _sudo("install", ["-d", "-m", "0755", directory + "/templates"])
            _sudo("cp", ["-a", "templates/.", directory + "/templates/"])
        if exists("static"):
            _sudo("install", ["-d", "-m", "0755", directory + "/static"])
            _sudo("cp", ["-a", "static/.", directory + "/static/"])
        _sudo(
            "install", ["-m", "0644", "mojara.project", directory + "/mojara.project"]
        )
    _sudo("install", ["-m", "0644", path, "/etc/systemd/system/" + unit])
    _sudo("systemctl", ["daemon-reload"])
    _sudo("systemctl", ["enable", unit])
    _sudo("systemctl", ["restart", unit])
    print("Deployed. Run 'mojara status' or 'mojara logs' to inspect the service.")


def _systemd_action(action: String) raises:
    if CompilationTarget.is_macos():
        raise Error("Systemd is unavailable on macOS.")
    var unit = _unit()
    if not _service_installed():
        raise Error("Service not installed: " + unit + ". Run 'mojara deploy' first.")
    if action == "status":
        _run("systemctl", ["status", "--no-pager", "--full", unit])
    elif action == "logs":
        # Pass one validated argument to avoid String aliasing in List literals.
        _sudo("sh", ["-c", "journalctl -u " + unit + " -n 100 --no-pager"])
    elif action == "stop" or action == "restart" or action == "start":
        # Pass one validated command string; avoid aliasing two dynamic String args.
        # action is one of the three allowed verbs, and the unit name is validated.
        _sudo("sh", ["-c", "systemctl " + action + " " + unit])
        print("systemctl " + action + " " + unit)
    else:
        raise Error("Unsupported service operation: " + action)


def _start(force_local: Bool = False) raises:
    if not force_local and _service_installed():
        _systemd_action("start")
        return
    if not exists("build/app"):
        raise Error("Compiled app missing. Run 'mojara build' first.")
    _setup_runtime_env()
    print("Starting Mojara server (Ctrl+C to stop)")
    _run("./build/app", [])


def _dev_needs_rebuild() raises -> Bool:
    """Recompile only when Mojo sources or the installed framework changed.

    HTML templates, stylesheets, JavaScript and JSON are read at runtime.
    Restarting their server does not require a Mojo compilation.
    """
    if not exists("build/app") or getenv("MOJARA_DEV_FORCE_BUILD", "0") == "1":
        return True
    _ = setenv("MOJARA_DEV_MODULE_PATH", _home() + "/lib/mojo/mojara.mojoc")
    var script = (
        'if [ "$MOJARA_DEV_MODULE_PATH" -nt build/app ]; then exit 0; fi; '
        "if find . "
        "\\( -type d \\( -name build -o -name .pixi -o -name .git \\) -prune \\) "
        "-o \\( -type f -name '*.mojo' -newer build/app -print -quit \\) "
        "| grep -q .; then exit 0; fi; exit 1"
    )
    var process = Process.run("sh", ["-c", script])
    var result = process.wait()
    if not result.exit_code:
        raise Error("Cannot determine Mojo source freshness")
    if result.exit_code.value() == 0:
        return True
    if result.exit_code.value() == 1:
        return False
    raise Error("Unable to scan Mojo source timestamps")


def _dev_once() raises:
    if _dev_needs_rebuild():
        _build()
    else:
        print("Mojo source unchanged; using compiled application.")
    # Only development runs enable the browser SSE endpoint and client.
    _ = setenv("MOJARA_DEV_RELOAD", "1")
    _start(True)


def _dev_watch() raises:
    _require_app()
    _check()
    print("Watching Mojo, templates, CSS and JavaScript for changes.")
    print("Mojo source changes trigger compilation; HTML/CSS/JS reuse the binary.")
    print(
        "Browser refresh is automatic after successful server restart. Ctrl+C to stop."
    )
    _run(
        "watchexec",
        [
            "--watch",
            ".",
            "--exts",
            "mojo,html,css,js,json",
            "--restart",
            "--",
            "mojara",
            "dev",
            "--once",
        ],
    )



# Static sites use a separate command namespace and output directory. This
# builder never imports the HTTP server, compiles app.mojo or touches build/.
def _site_escape(value: String) -> String:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def _site_emphasis(value: String) -> String:
    """Escape text before adding simple bold and inline-code markup."""
    var chunks = value.split("`")
    var output = String("")
    if len(chunks) % 2 == 0:
        return _site_escape(value)
    for i in range(len(chunks)):
        var chunk = String(chunks[i])
        if i % 2 == 1:
            output += "<code>" + _site_escape(chunk) + "</code>"
        else:
            var bold = chunk.split("**")
            if len(bold) % 2 == 0:
                output += _site_escape(chunk)
            else:
                for j in range(len(bold)):
                    if j % 2 == 1:
                        output += "<strong>" + _site_escape(String(bold[j])) + "</strong>"
                    else:
                        output += _site_escape(String(bold[j]))
    return output^


def _site_safe_link(url: String) -> Bool:
    return (
        url.startswith("https://")
        or url.startswith("http://")
        or url.startswith("mailto:")
        or url.startswith("/")
        or url.startswith("./")
        or url.startswith("../")
        or url.startswith("#")
    )


def _site_inline(value: String) -> String:
    """Render basic Markdown links without allowing dangerous URL schemes."""
    var output = String("")
    var offset = 0
    while offset < value.byte_length():
        var opening = value.find("[", offset)
        if opening < 0:
            output += _site_emphasis(String(value[byte=offset:]))
            break
        var separator = value.find("](", opening + 1)
        if separator < 0:
            output += _site_emphasis(String(value[byte=offset:]))
            break
        var closing = value.find(")", separator + 2)
        if closing < 0:
            output += _site_emphasis(String(value[byte=offset:]))
            break
        output += _site_emphasis(String(value[byte=offset:opening]))
        var label = String(value[byte=opening + 1:separator])
        var url = String(value[byte=separator + 2:closing])
        if _site_safe_link(url):
            output += (
                '<a href="' + _site_escape(url) + '">' +
                _site_emphasis(label) + "</a>"
            )
        else:
            output += _site_emphasis(String(value[byte=opening:closing + 1]))
        offset = closing + 1
    return output^


def _site_markdown(source: String) raises -> String:
    """Render headings, paragraphs, lists, fenced code, links and inline markup."""
    var html = String("")
    var paragraph = String("")
    var in_list = False
    var in_code = False
    for part in source.split("\n"):
        var line = String(part)
        var trimmed = String(line.strip())
        if trimmed.startswith("```"):
            if in_code:
                html += "</code></pre>\n"
                in_code = False
            else:
                if paragraph.byte_length() > 0:
                    html += "<p>" + _site_inline(paragraph) + "</p>\n"
                    paragraph = ""
                if in_list:
                    html += "</ul>\n"
                    in_list = False
                html += "<pre><code>"
                in_code = True
            continue
        if in_code:
            html += _site_escape(line) + "\n"
            continue
        if trimmed.byte_length() == 0:
            if paragraph.byte_length() > 0:
                html += "<p>" + _site_inline(paragraph) + "</p>\n"
                paragraph = ""
            if in_list:
                html += "</ul>\n"
                in_list = False
            continue
        var heading_level = 0
        while heading_level < 6 and heading_level < trimmed.byte_length():
            if Int(trimmed.as_bytes()[heading_level]) != 35:
                break
            heading_level += 1
        if (
            heading_level > 0
            and heading_level < trimmed.byte_length()
            and Int(trimmed.as_bytes()[heading_level]) == 32
        ):
            if paragraph.byte_length() > 0:
                html += "<p>" + _site_inline(paragraph) + "</p>\n"
                paragraph = ""
            if in_list:
                html += "</ul>\n"
                in_list = False
            var tag = "h" + String(heading_level)
            html += (
                "<" + tag + ">" +
                _site_inline(String(trimmed[byte=heading_level + 1:])) +
                "</" + tag + ">\n"
            )
            continue
        if trimmed.startswith("- ") or trimmed.startswith("* "):
            if paragraph.byte_length() > 0:
                html += "<p>" + _site_inline(paragraph) + "</p>\n"
                paragraph = ""
            if not in_list:
                html += "<ul>\n"
                in_list = True
            html += "<li>" + _site_inline(String(trimmed[byte=2:])) + "</li>\n"
            continue
        if in_list:
            html += "</ul>\n"
            in_list = False
        if paragraph.byte_length() > 0:
            paragraph += " "
        paragraph += trimmed
    if in_code:
        raise Error("Unclosed Markdown code fence")
    if paragraph.byte_length() > 0:
        html += "<p>" + _site_inline(paragraph) + "</p>\n"
    if in_list:
        html += "</ul>\n"
    return html^


def _site_create_directory(path: String) raises:
    """Create only directories, refusing to follow pre-existing symlinks."""
    if exists(path) or islink(path):
        if islink(path) or not isdir(path):
            raise Error("Not a safe output directory: " + path)
        return
    var parent = dirname(path)
    if parent.byte_length() > 0 and parent != path:
        _site_create_directory(parent)
    mkdir(path)


def _site_track_output(path: String, mut outputs: List[String]) raises:
    if path == "dist/.mojara-site":
        raise Error("Reserved site output path")
    for previous in outputs:
        if previous == path:
            raise Error("Two site sources write the same destination: " + path)
    if islink(path) or (exists(path) and isdir(path)):
        raise Error("Unsafe output file path: " + path)
    outputs.append(path)


def _site_copy_assets(source: String, target: String, mut outputs: List[String]) raises:
    if not exists(source):
        return
    if islink(source) or not isdir(source):
        raise Error("Static asset directory must not be a symlink: " + source)
    _site_create_directory(target)
    for entry in Path(source).listdir():
        var name = entry.name()
        var src = source + "/" + name
        var dst = target + "/" + name
        if islink(src):
            raise Error("Symlinked static assets are not supported: " + src)
        if isdir(src):
            _site_copy_assets(src, dst, outputs)
        else:
            _site_track_output(dst, outputs)
            var data = Path(src).read_bytes()
            Path(dst).write_bytes(Span(data))


def _site_page(source_path: String, fallback: String, layout: String) raises -> String:
    var raw = Path(source_path).read_text()
    var title = String("")
    var description = String("")
    var body = String("")
    var first = True
    var front = False
    for entry in raw.split("\n"):
        var line = String(entry)
        var trimmed = String(line.strip())
        if first:
            first = False
            if trimmed == "---":
                front = True
                continue
        if front:
            if trimmed == "---":
                front = False
            elif trimmed.startswith("title:"):
                var value = String(trimmed[byte=6:])
                title = String(value.strip())
            elif trimmed.startswith("description:"):
                var value = String(trimmed[byte=12:])
                description = String(value.strip())
            continue
        if title.byte_length() == 0 and trimmed.startswith("# "):
            title = String(trimmed[byte=2:])
        body += line + "\n"
    if front:
        raise Error("Unclosed Markdown front matter: " + source_path)
    if title.byte_length() == 0:
        title = fallback
    var rendered = layout.replace("{{ content }}", _site_markdown(body))
    rendered = rendered.replace("{{ title }}", _site_escape(title))
    rendered = rendered.replace("{{ description }}", _site_escape(description))
    return rendered^


def _site_pages(
    source: String, relative: String, layout: String, mut outputs: List[String]
) raises:
    if islink(source):
        raise Error("Symlinked content directories are not supported: " + source)
    for entry in Path(source).listdir():
        var name = entry.name()
        var src = source + "/" + name
        if islink(src):
            raise Error("Symlinked content is not supported: " + src)
        if isdir(src):
            _site_pages(src, relative + name + "/", layout, outputs)
        elif name.endswith(".md"):
            var stem = String(name[byte=0:name.byte_length() - 3])
            if stem.byte_length() == 0:
                raise Error("Invalid Markdown filename: " + src)
            var destination = String("")
            if stem == "index":
                destination = "dist/" + relative + "index.html"
            else:
                destination = "dist/" + relative + stem + "/index.html"
            _site_create_directory(dirname(destination))
            _site_track_output(destination, outputs)
            Path(destination).write_text(_site_page(src, stem, layout))
            print("  ", src, "->", destination)


def _site_new(name: String) raises:
    if not _valid_name(name):
        raise Error("Invalid site name. Use letters, digits, '-' or '_'.")
    if exists(name) or islink(name):
        raise Error("Refusing to overwrite existing path: " + name)
    mkdir(name)
    mkdir(name + "/content")
    mkdir(name + "/templates")
    mkdir(name + "/static")
    Path(name + "/mojara.project").write_text("name " + name + "\ntype site\n")
    Path(name + "/.gitignore").write_text("dist/\n.mojo_cache/\n")
    Path(name + "/content/index.md").write_text(
        "---\ntitle: Welcome to " + name +
        "\ndescription: A website built with Mojara and Mojo.\n---\n\n"
        "# Welcome to " + name +
        "\n\nThis website is generated by **Mojara**.\n\n"
        "- Write content in Markdown\n"
        "- Put images and stylesheets in static/\n"
        "- Run mojara site build\n"
    )
    Path(name + "/templates/base.html").write_text(
        '<!doctype html>\n<html lang="en">\n<head>\n'
        '  <meta charset="utf-8">\n'
        '  <meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '  <meta name="description" content="{{ description }}">\n'
        '  <title>{{ title }}</title>\n'
        '  <link rel="stylesheet" href="/static/style.css">\n'
        '</head>\n<body>\n<main>{{ content }}</main>\n</body>\n</html>\n'
    )
    Path(name + "/static/style.css").write_text(
        "body{font:16px/1.65 system-ui,sans-serif;background:#fffaf3;"
        "color:#39261c;margin:0;padding:40px}"
        "main{max-width:780px;margin:auto}h1,h2{color:#d9531e}"
        "a{color:#ac4319}pre{overflow:auto;background:#fff0df;padding:16px}"
        "code{font:0.92em ui-monospace,monospace}\n"
    )
    print("Created static website:", name)
    print("Next: cd " + name + " && mojara site build")


def _site_build() raises:
    if not isdir("content") or islink("content"):
        raise Error("content/ is missing or unsafe. Run from a static site project.")
    if not exists("templates/base.html") or islink("templates") or islink("templates/base.html"):
        raise Error("Missing or unsafe templates/base.html")
    if exists("app.mojo"):
        raise Error("This is a dynamic Mojara app. Static sites require a separate project.")
    if exists("dist") or islink("dist"):
        if islink("dist") or not isdir("dist"):
            raise Error("dist/ is not a safe directory")
        if not exists("dist/.mojara-site") or islink("dist/.mojara-site"):
            raise Error("dist/ is not owned by the Mojara site builder; refusing overwrite")
    else:
        mkdir("dist")
        Path("dist/.mojara-site").write_text("Generated by mojara site build.\n")
    var layout = Path("templates/base.html").read_text()
    if layout.find("{{ content }}") < 0:
        raise Error("templates/base.html must contain {{ content }}")
    var outputs = List[String]()
    _site_copy_assets("static", "dist/static", outputs)
    _site_pages("content", "", layout, outputs)
    print("Static website generated in dist/")



def _help():
    print("Mojara 1.2.10 - Native Mojo framework CLI")
    print("Usage: mojara <command> [args]")
    print("  new NAME [--api]   Create project")
    print("  dev                Watch, rebuild and restart on file changes")
    print("  dev --once         Build and run once")
    print("  build              Compile app, optional DB runner, and systemd unit")
    print("  site new NAME      Create a Markdown-powered static website")
    print("  site build         Generate static HTML and assets into dist/")
    print("  db init            Generate db.mojo with code-first and SQL support")
    print("  db plan            Preview additive schema changes")
    print("  db migrate         Execute code-first and registered SQL migrations")
    print("  deploy [--dry-run] Install app and systemd unit on this Linux host")
    print("  start [--local]    Start installed service or run app locally")
    print("  stop               Stop installed service")
    print("  restart            Restart installed service")
    print("  status             Show systemd service status")
    print("  logs               Show latest service logs")
    print("  doctor             Verify the SDK and compiler")
    print("  version            Print version")
    print("  help               Print help")


def main() raises:
    var args = argv()
    if len(args) < 2:
        _help()
        return
    var command = String(args[1])
    if command == "help" or command == "--help" or command == "-h":
        _help()
    elif command == "version" or command == "--version" or command == "-v":
        print("Mojara 1.2.10 (native Mojo CLI)")
    elif command == "doctor":
        _check()
    elif command == "new":
        if len(args) == 3:
            _new(String(args[2]), False)
        elif len(args) == 4 and String(args[3]) == "--api":
            _new(String(args[2]), True)
        else:
            raise Error("Usage: mojara new NAME [--api]")
    elif command == "dev":
        if len(args) == 3 and String(args[2]) == "--once":
            _dev_once()
        elif len(args) == 2:
            _dev_watch()
        else:
            raise Error("Usage: mojara dev [--once]")
    elif command == "db":
        if len(args) != 3:
            raise Error("Usage: mojara db init|plan|migrate")
        _db_action(String(args[2]))
    elif command == "site":
        if len(args) == 4 and String(args[2]) == "new":
            _site_new(String(args[3]))
        elif len(args) == 3 and String(args[2]) == "build":
            _site_build()
        else:
            raise Error("Usage: mojara site new NAME | mojara site build")
    elif command == "build":
        if len(args) != 2:
            raise Error("Usage: mojara build")
        _build()
    elif command == "deploy":
        if len(args) == 3 and String(args[2]) == "--dry-run":
            _deploy(True)
        elif len(args) == 2:
            _deploy(False)
        else:
            raise Error("Usage: mojara deploy [--dry-run]")
    elif command == "start":
        if len(args) == 3 and String(args[2]) == "--local":
            _start(True)
        elif len(args) == 2:
            _start()
        else:
            raise Error("Usage: mojara start [--local]")
    elif (
        command == "stop"
        or command == "restart"
        or command == "status"
        or command == "logs"
    ):
        if len(args) != 2:
            raise Error("Usage: mojara " + command)
        _systemd_action(command)
    else:
        raise Error("Unknown command: " + command)
