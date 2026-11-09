"""Native Mojo application routing, responses, and HTTP lifecycle.

App registers handlers and middleware, and Response constructs HTTP output.
Listener settings come from validated runtime configuration. Public HTTP,
session, and template interfaces are available from the Mojara package."""

from .platform import library_name
from std.pathlib import Path
from std.os import getenv
from std.ffi import OwnedDLHandle, c_int
from .runtime import load_runtime_settings
from json import Value, dumps
from flare.http import (
    Request,
    Response as WireResponse,
    Router,
    HttpServer,
    Handler,
    ServerConfig,
    WsUpgrade,
    Template,
    TemplateContext,
    html_escape,
    Session,
    CookieSessionStore,
    InMemorySessionStore,
    ok,
    ok_json,
)
from flare.net import IpAddr, SocketAddr
from flare.ws import WsConnection, WsOpcode, WsCloseCode


struct Response(Movable):
    """Mojara response wrapper with constructors for common content types."""

    var _wire: WireResponse

    def __init__(out self, var wire: WireResponse):
        """Take ownership of a native HTTP response."""
        self._wire = wire^

    @staticmethod
    def text(body: String) raises -> Response:
        """Build a UTF-8 plain-text response with the proper content type."""
        var wire = ok(body)
        wire.headers.set("Content-Type", "text/plain; charset=utf-8")
        return Response(wire^)

    @staticmethod
    def html(body: String) raises -> Response:
        """Build an HTML response with UTF-8 content type."""
        var wire = ok(body)
        wire.headers.set("Content-Type", "text/html; charset=utf-8")
        return Response(wire^)

    @staticmethod
    def json(body: String) -> Response:
        """Return pre-serialized JSON (prefer json_value for untrusted data)."""
        return Response(ok_json(body))

    @staticmethod
    def json_value(value: Value) raises -> Response:
        """Serialize a Mojo JSON Value, escaping string values correctly."""
        return Response(ok_json(dumps(value)))

    @staticmethod
    def created_json(body: String) -> Response:
        """Return pre-serialized JSON with HTTP status 201."""
        var wire = ok_json(body)
        wire.status = 201
        return Response(wire^)

    @staticmethod
    def created_value(value: Value) raises -> Response:
        """Serialize a JSON value and return HTTP status 201."""
        var reply = Response.json_value(value)
        reply.set_status(201)
        return reply^

    @staticmethod
    def redirect(location: String, permanent: Bool = False) raises -> Response:
        """Build an HTTP redirect; permanent selects HTTP 301."""
        var wire = ok("")
        wire.status = 301 if permanent else 302
        wire.headers.set("Location", location)
        return Response(wire^)

    @staticmethod
    def error(status: Int, message: String) raises -> Response:
        """Return an escaped JSON error body and the provided HTTP status."""
        var payload = Value.object()
        payload.set("error", Value(message))
        var reply = Response.json_value(payload)
        reply.set_status(status)
        return reply^

    @staticmethod
    def render(source: String, var context: TemplateContext) raises -> Response:
        """Compile and render HTML, escaping interpolated variables by default."""
        var body: String
        try:
            var template = Template.compile(source)
            body = template.render(context)
        except e:
            # Flare's template parser emits a typed TemplateError. Convert
            # it at the public Mojara API boundary to a general Mojo Error.
            raise Error(String(e))
        # HeaderMap.set() raises Error, not TemplateError. Run this outside
        # the typed template-error handling block.
        return Response.html(body)

    @staticmethod
    def render_file(path: String, var context: TemplateContext) raises -> Response:
        """Load trusted template path, render as HTML. Do not use user paths."""
        return Response.render(Path(path).read_text(), context^)

    def set_header(mut self, name: String, value: String) raises:
        """Add or replace a validated HTTP response header."""
        self._wire.headers.set(name, value)

    def set_status(mut self, status: Int):
        """Set the status code of the pending HTTP response."""
        self._wire.status = status

    def into_wire(deinit self) -> WireResponse:
        """Consume the wrapper, transferring its move-only Flare response."""
        return self._wire^


# Dev-only script loads same-origin.
comptime _MOJARA_RELOAD_SCRIPT: String = (
    '(function(){"use strict";'
    "if(window.__mojaraReloadConnected||!window.WebSocket)return;"
    "window.__mojaraReloadConnected=true;"
    "var sawConnection=false,lostConnection=false,stopped=false,retry=null,socket;"
    "function connect(){"
    'var scheme=location.protocol==="https:"?"wss:":"ws:";'
    'socket=new WebSocket(scheme+"//"+location.host+"/__mojara_dev/ws");'
    "socket.onopen=function(){"
    "if(lostConnection){stopped=true;socket.close();location.reload();return;}"
    "sawConnection=true;};"
    "socket.onclose=function(){if(stopped)return;if(sawConnection)lostConnection=true;"
    "retry=setTimeout(connect,500);};"
    "socket.onerror=function(){try{socket.close();}catch(e){}};"
    "}"
    'window.addEventListener("beforeunload",function(){stopped=true;'
    "if(retry)clearTimeout(retry);if(socket)socket.close();},{once:true});"
    "connect();})();"
)


def _dev_reload_client(req: Request) raises -> Response:
    var reply = Response.text(_MOJARA_RELOAD_SCRIPT)
    reply.set_header("Content-Type", "application/javascript; charset=utf-8")
    reply.set_header("Cache-Control", "no-store, no-cache, must-revalidate")
    reply.set_header("X-Content-Type-Options", "nosniff")
    return reply^


def _dev_reload_websocket(mut conn: WsConnection) raises -> None:
    # Local development only. Prevent arbitrary external websites from
    # opening a WebSocket to the developer machine through a browser.
    if conn.origin.byte_length() > 0 and not (
        conn.origin.startswith("http://127.0.0.1:")
        or conn.origin.startswith("http://localhost:")
        or conn.origin == "http://localhost"
        or conn.origin == "http://127.0.0.1"
    ):
        conn.close(WsCloseCode.POLICY_VIOLATION)
        return
    # Blocking receive runs on a bounded offloaded WebSocket worker.
    # Unlike Flare's current SSE channel this parks without consuming
    # a CPU core. The connection drops when the dev process restarts.
    try:
        while True:
            var frame = conn.recv()
            if frame.opcode == WsOpcode.CLOSE:
                break
    except:
        pass


@fieldwise_init
struct _RouteHandler(Copyable, Handler):
    """Convert a Mojara callback into a Flare-compatible handler."""

    var callback: def(Request) raises thin -> Response

    def serve(self, req: Request) raises -> WireResponse:
        """Invoke a registered route function and return its wire response."""
        var reply = self.callback(req)
        return (reply^).into_wire()


@fieldwise_init
struct _Lifecycle(Copyable, Handler):
    """Middleware executed in registered order before and after dispatch."""

    var router: Router
    var guards: List[def(Request) raises thin -> Bool]
    var after: List[def(Request, var WireResponse) raises thin -> WireResponse]
    var on_404: def(Request) raises thin -> Response
    var on_405: def(Request) raises thin -> Response
    var custom_404: Bool
    var custom_405: Bool
    var metrics_enabled: Bool
    var cors_origin: String
    var cors_methods: String
    var cors_headers: String
    var cors_credentials: Bool
    var dev_reload_enabled: Bool

    def serve(self, req: Request) raises -> WireResponse:
        """Execute request guards, dispatch, error handling, and response hooks."""
        # Opt-in: avoids changing the default low-overhead request path.
        # Measures application dispatch time, not socket accept/transport time.
        if not self.metrics_enabled:
            return self._serve_unmeasured(req)
        var lib = OwnedDLHandle(library_name("libmojara_metrics.so", "libmojara_metrics.dylib"))
        var begin = lib.get_function[Int]("mj_metrics_start")
        var finish = lib.get_function[NoneType]("mj_metrics_finish")
        var started = begin()
        var result: WireResponse
        try:
            result = self._serve_unmeasured(req)
        except e:
            finish(started, c_int(500))
            raise Error(String(e))
        finish(started, c_int(result.status))
        return result^

    def _cors_matches(self, origin: String) -> Bool:
        return origin.byte_length() > 0 and (
            self.cors_origin == "*" or origin == self.cors_origin
        )

    def _cors_headers(self, req: Request, mut response: WireResponse) raises:
        var origin = req.headers.get("origin")
        if not self._cors_matches(origin):
            return
        response.headers.set(
            "Access-Control-Allow-Origin", "*" if self.cors_origin == "*" else origin
        )
        if self.cors_origin != "*":
            response.headers.set("Vary", "Origin")
        if self.cors_credentials:
            response.headers.set("Access-Control-Allow-Credentials", "true")

    def _serve_unmeasured(self, req: Request) raises -> WireResponse:
        var origin = req.headers.get("origin")
        if (
            self.cors_origin.byte_length() > 0
            and req.method == "OPTIONS"
            and (req.headers.get("access-control-request-method").byte_length() > 0)
        ):
            if not self._cors_matches(origin):
                var denied = Response.error(403, "CORS origin not permitted")
                return (denied^).into_wire()
            var method = req.headers.get("access-control-request-method")
            if not self._cors_methods_allow(method):
                var denied = Response.error(403, "CORS method not permitted")
                return (denied^).into_wire()
            var empty = Response.text("")
            empty.set_status(204)
            var preflight = (empty^).into_wire()
            self._cors_headers(req, preflight)
            preflight.headers.set("Access-Control-Allow-Methods", self.cors_methods)
            preflight.headers.set("Access-Control-Allow-Headers", self.cors_headers)
            preflight.headers.set("Access-Control-Max-Age", "600")
            return preflight^
        var accepted = True
        for index in range(len(self.guards)):
            if not self.guards[index](req):
                accepted = False
                break

        var result: WireResponse
        if not accepted:
            var forbidden = Response.error(403, "Forbidden")
            result = (forbidden^).into_wire()
        else:
            result = self.router.serve(req)
            if result.status == 404 and self.custom_404:
                var reply = self.on_404(req)
                result = (reply^).into_wire()
            elif result.status == 405 and self.custom_405:
                var reply = self.on_405(req)
                result = (reply^).into_wire()

        for index in range(len(self.after)):
            result = self.after[index](req, result^)
        if (
            self.dev_reload_enabled
            and req.method == "GET"
            and (
                result.status == 200
                and result.headers.get("Content-Type").startswith("text/html")
                and len(result.body) > 0
            )
        ):
            var html = result.text()
            var marker = '<script defer src="/__mojara_dev/client.js"></script>'
            html = html.replace("</body>", marker + "</body>")
            result.body = List[UInt8](html.as_bytes())
            result.headers.set("Cache-Control", "no-store")
        if self.cors_origin.byte_length() > 0:
            self._cors_headers(req, result)
        return result^

    def _cors_methods_allow(self, method: String) -> Bool:
        for item in self.cors_methods.split(","):
            # Allow exactly the configured methods; do not reflect arbitrary input.
            if String(item) == method:
                return True
        return False


def _default_error(req: Request) raises -> Response:
    return Response.error(500, "Internal server error")


struct AppConfig(Copyable):
    """Configuration for the development server. Defaults are loopback-only."""

    var host: String
    var port: UInt16
    var workers: Int

    def __init__(out self):
        """Initialize listener and worker defaults."""
        self.host = "127.0.0.1"
        self.port = 8000
        self.workers = 1


struct App:
    """Routing, HTTP lifecycle and app server entrypoints."""

    var _router: Router
    var _guards: List[def(Request) raises thin -> Bool]
    var _after: List[def(Request, var WireResponse) raises thin -> WireResponse]
    var _on_404: def(Request) raises thin -> Response
    var _on_405: def(Request) raises thin -> Response
    var _custom_404: Bool
    var _custom_405: Bool
    var _metrics_enabled: Bool
    var _cors_origin: String
    var _cors_methods: String
    var _cors_headers: String
    var _cors_credentials: Bool
    var _dev_reload_enabled: Bool
    var config: AppConfig

    def __init__(out self):
        """Create an application router with empty middleware and configuration."""
        self._router = Router()
        self._guards = List[def(Request) raises thin -> Bool]()
        self._after = List[def(Request, var WireResponse) raises thin -> WireResponse]()
        self._on_404 = _default_error
        self._on_405 = _default_error
        self._custom_404 = False
        self._custom_405 = False
        self._metrics_enabled = (
            getenv("MOJARA_METRICS", "0") == "1"
            or getenv("MOJARA_DRAIN_TOKEN", "").byte_length() >= 24
        )
        self._cors_origin = ""
        self._cors_methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS"
        self._cors_headers = "Content-Type,Authorization"
        self._cors_credentials = False
        self._dev_reload_enabled = getenv("MOJARA_DEV_RELOAD", "0") == "1"
        self.config = AppConfig()

    def get(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP GET."""
        self._router.get(path, _RouteHandler(handler))

    def post(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP POST."""
        self._router.post(path, _RouteHandler(handler))

    def put(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP PUT."""
        self._router.put(path, _RouteHandler(handler))

    def patch(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP PATCH."""
        self._router.patch(path, _RouteHandler(handler))

    def delete(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP DELETE."""
        self._router.delete(path, _RouteHandler(handler))

    def head(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP HEAD."""
        self._router.head(path, _RouteHandler(handler))

    def options(
        mut self, path: String, handler: def(Request) raises thin -> Response
    ) raises:
        """Register a function handler for HTTP OPTIONS."""
        self._router.options(path, _RouteHandler(handler))

    def get_handler[
        H: Handler & Copyable
    ](mut self, path: String, var handler: H) raises:
        """Register a stateful Mojo Handler, retaining its associated state."""
        self._router.get(path, handler^)

    def post_handler[
        H: Handler & Copyable
    ](mut self, path: String, var handler: H) raises:
        """Register a stateful POST handler (used by validated APIs)."""
        self._router.post(path, handler^)

    def put_handler[
        H: Handler & Copyable
    ](mut self, path: String, var handler: H) raises:
        """Register a stateful handler for HTTP PUT."""
        self._router.put(path, handler^)

    def patch_handler[
        H: Handler & Copyable
    ](mut self, path: String, var handler: H) raises:
        """Register a stateful handler for HTTP PATCH."""
        self._router.patch(path, handler^)

    def mount(mut self, prefix: String, sub: App) raises:
        """Mount sub-app routes. Sub-app middleware does not propagate."""
        self._router.mount(prefix, sub._router.copy())

    def cors(
        mut self,
        origin: String,
        methods: String = "GET,POST,OPTIONS",
        headers: String = "Content-Type,Authorization",
        credentials: Bool = False,
    ) raises:
        """Enable CORS for an exact trusted Origin, or * without credentials."""
        if origin.byte_length() == 0 or (
            origin != "*"
            and not (origin.startswith("https://") or origin.startswith("http://"))
        ):
            raise Error("CORS requires an explicit origin or *")
        if origin == "*" and credentials:
            raise Error("CORS wildcard cannot be used with credentials")
        if (
            origin.byte_length() > 2048
            or methods.byte_length() > 512
            or headers.byte_length() > 1024
        ):
            raise Error("Invalid CORS configuration")
        self._cors_origin = origin
        self._cors_methods = methods
        self._cors_headers = headers
        self._cors_credentials = credentials

    def before_request(mut self, hook: def(Request) raises thin -> Bool):
        """Register a guard: False rejects with HTTP 403, True continues."""
        self._guards.append(hook)

    def after_request(
        mut self,
        hook: def(Request, var WireResponse) raises thin -> WireResponse,
    ):
        """Register a response hook for every response, including 403/404."""
        self._after.append(hook)

    def errorhandler(
        mut self, status: Int, callback: def(Request) raises thin -> Response
    ) raises:
        """Replace 404 or 405 responses; other statuses are unsupported."""
        if status == 404:
            self._on_404 = callback
            self._custom_404 = True
        elif status == 405:
            self._on_405 = callback
            self._custom_405 = True
        else:
            raise Error("errorhandler currently supports only 404 and 405")

    def _handler(self) -> _Lifecycle:
        return _Lifecycle(
            router=self._router.copy(),
            guards=self._guards.copy(),
            after=self._after.copy(),
            on_404=self._on_404,
            on_405=self._on_405,
            custom_404=self._custom_404,
            custom_405=self._custom_405,
            metrics_enabled=self._metrics_enabled,
            cors_origin=self._cors_origin.copy(),
            cors_methods=self._cors_methods.copy(),
            cors_headers=self._cors_headers.copy(),
            cors_credentials=self._cors_credentials,
            dev_reload_enabled=self._dev_reload_enabled,
        )

    def handle(self, req: Request) raises -> WireResponse:
        """Dispatch in-process, including middleware, without opening TCP."""
        var pipeline = self._handler()
        return pipeline.serve(req)

    def run(
        mut self,
        host: String = "127.0.0.1",
        port: UInt16 = 8000,
        workers: Int = 1,
    ) raises:
        """Blocking native server; binds loopback unless configured otherwise."""
        if workers < 1 or workers > 64:
            raise Error("workers must be in the range 1..64")
        if self._dev_reload_enabled:
            self.get("/__mojara_dev/client.js", _dev_reload_client)
        var address = SocketAddr(IpAddr.parse(host), port)
        # Do not announce success before checking that the address can bind.
        if self._dev_reload_enabled:
            var dev_config = ServerConfig()
            dev_config.ws = WsUpgrade(
                _dev_reload_websocket, offload=True, max_offloaded=32
            )
            var server = HttpServer.bind(address, dev_config^)
            print("Mojara listening at http://" + host + ":" + String(port))
            server.serve(self._handler(), num_workers=workers)
        else:
            var server = HttpServer.bind(address)
            print("Mojara listening at http://" + host + ":" + String(port))
            server.serve(self._handler(), num_workers=workers)

    def run_configured(mut self) raises:
        """Honor MOJARA_HOST, MOJARA_PORT and MOJARA_WORKERS if configured."""
        var settings = load_runtime_settings(
            self.config.host.copy(), self.config.port, self.config.workers
        )
        var host = settings.host.copy()
        var port = settings.port
        var workers = settings.workers
        self.run(host, port, workers)


# Native Flare session primitives are re-exported above. Sessions must use
# a unique, secret signing key; never embed a key in application source.
