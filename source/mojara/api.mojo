"""Typed JSON endpoint validation and OpenAPI document generation.

Schema describes JSON object fields. Api registers validated or protected
operations and generates machine-readable and interactive API documentation."""

from json import Value, dumps
from flare.http import Handler, Request
from . import App, Response, WireResponse
from .auth import AuthStore, Principal, ProtectedRoute


struct FieldRule(Copyable):
    """A JSON object field with its expected type and requiredness."""

    var name: String
    var kind: String
    var required: Bool
    var min_length: Int

    def __init__(
        out self,
        name: String,
        kind: String,
        required: Bool = True,
        min_length: Int = 0,
    ):
        """Describe one JSON field and its validation constraints."""
        self.name = name
        self.kind = kind
        self.required = required
        self.min_length = min_length


struct Schema(Copyable):
    """Declarative flat JSON object schema with field-level errors."""

    var fields: List[FieldRule]

    def __init__(out self):
        """Create an empty JSON object validation schema."""
        self.fields = List[FieldRule]()

    def string(
        mut self, name: String, required: Bool = True, min_length: Int = 0
    ) raises:
        """Declare a string field with required and minimum-length options."""
        if name.byte_length() == 0 or min_length < 0:
            raise Error("Invalid string field definition")
        self.fields.append(FieldRule(name, "string", required, min_length))

    def integer(mut self, name: String, required: Bool = True) raises:
        """Declare an integer field, optionally required."""
        if name.byte_length() == 0:
            raise Error("Invalid integer field definition")
        self.fields.append(FieldRule(name, "integer", required))

    def boolean(mut self, name: String, required: Bool = True) raises:
        """Declare a Boolean field, optionally required."""
        if name.byte_length() == 0:
            raise Error("Invalid boolean field definition")
        self.fields.append(FieldRule(name, "boolean", required))

    def errors(self, payload: Value) raises -> Value:
        """Return a JSON array of violations; an empty array means valid."""
        var issues = Value.array()
        if not payload.is_object():
            issues.append(_issue("body", "Expected a JSON object"))
            return issues^

        for i in range(len(self.fields)):
            ref field = self.fields[i]
            var present = False
            var member = Value(None)
            try:
                member = payload[field.name]
                present = True
            except:
                pass
            if not present:
                if field.required:
                    issues.append(_issue(field.name, "Field is required"))
                continue
            if field.kind == "string":
                if not member.is_string():
                    issues.append(_issue(field.name, "Expected string"))
                else:
                    var text_value = member.string_value()
                    if len(text_value.codepoints()) < field.min_length:
                        issues.append(_issue(field.name, "String is too short"))
            elif field.kind == "integer":
                if not member.is_int():
                    issues.append(_issue(field.name, "Expected integer"))
            elif field.kind == "boolean":
                if not member.is_bool():
                    issues.append(_issue(field.name, "Expected boolean"))
        return issues^

    def openapi_schema(self) raises -> Value:
        """Translate field rules into an OpenAPI-compatible JSON schema."""
        var output = Value.object()
        output.set("type", Value("object"))
        var props = Value.object()
        var required = Value.array()
        for i in range(len(self.fields)):
            ref rule = self.fields[i]
            var prop = Value.object()
            prop.set("type", Value(rule.kind))
            if rule.kind == "string" and rule.min_length > 0:
                prop.set("minLength", Value(rule.min_length))
            props.set(rule.name, prop)
            if rule.required:
                required.append(Value(rule.name))
        output.set("properties", props)
        if required.array_count() > 0:
            output.set("required", required)
        return output^


def _issue(name: String, message: String) raises -> Value:
    var issue = Value.object()
    issue.set("field", Value(name))
    issue.set("message", Value(message))
    return issue^


def _api_error(
    status: Int, code: String, detail: String, issues: Value
) raises -> WireResponse:
    var payload = Value.object()
    payload.set("error", Value(code))
    payload.set("detail", Value(detail))
    payload.set("issues", issues)
    var reply = Response.json_value(payload)
    reply.set_status(status)
    return (reply^).into_wire()


@fieldwise_init
struct _ValidatedRoute(Copyable, Handler):
    var schema: Schema
    var callback: def(Request, Value) raises thin -> Response
    var max_body_bytes: Int

    def serve(self, req: Request) raises -> WireResponse:
        """Validate the JSON request before invoking the route."""
        if len(req.body) > self.max_body_bytes:
            return _api_error(
                413, "payload_too_large", "Request body too large", Value.array()
            )
        var content_type = req.headers.get("content-type")
        if not (
            content_type == "application/json"
            or content_type.startswith("application/json;")
        ):
            return _api_error(
                415,
                "unsupported_media_type",
                "Expected application/json",
                Value.array(),
            )
        var payload: Value
        try:
            payload = req.json()
        except:
            return _api_error(
                400, "invalid_json", "Malformed JSON request body", Value.array()
            )
        var issues = self.schema.errors(payload)
        if issues.array_count() > 0:
            return _api_error(
                422, "validation_error", "Request validation failed", issues
            )
        var reply = self.callback(req, payload)
        return (reply^).into_wire()


@fieldwise_init
struct _DocumentHandler(Copyable, Handler):
    var content: String

    def serve(self, req: Request) raises -> WireResponse:
        """Return the generated OpenAPI JSON document."""
        var reply = Response.json(self.content)
        return (reply^).into_wire()


@fieldwise_init
struct _HtmlHandler(Copyable, Handler):
    var content: String

    def serve(self, req: Request) raises -> WireResponse:
        """Return the interactive API documentation."""
        var reply = Response.html(self.content)
        return (reply^).into_wire()


struct Operation(Copyable):
    var method: String
    var path: String
    var summary: String
    var schema: Schema
    var has_body: Bool
    var secured: Bool

    def __init__(
        out self,
        method: String,
        path: String,
        summary: String,
        schema: Schema = Schema(),
        has_body: Bool = False,
        secured: Bool = False,
    ):
        """Record the route operation metadata used for OpenAPI."""
        self.method = method
        self.path = path
        self.summary = summary
        self.schema = schema.copy()
        self.has_body = has_body
        self.secured = secured


def _swagger_html() -> String:
    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>Mojara API | Swagger UI</title>"
        '<link rel="stylesheet"'
        ' href="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui.css">'
        '</head><body><div id="swagger-ui"></div>'
        "<script"
        ' src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"></script>'
        '<script>window.onload=function(){SwaggerUIBundle({url:"/openapi.json",dom_id:"#swagger-ui"});};</script>'
        "</body></html>"
    )


def _redoc_html() -> String:
    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>Mojara API | ReDoc</title></head><body>"
        '<redoc spec-url="/openapi.json"></redoc>'
        "<script"
        ' src="https://cdn.jsdelivr.net/npm/redoc@2.5.0/bundles/redoc.standalone.js"></script>'
        "</body></html>"
    )


def _openapi_path(path: String) -> String:
    """Translate Flare's /:param segments into OpenAPI /{param} paths."""
    var segments = path.split("/")
    var output = String("")
    for i in range(len(segments)):
        if i > 0:
            output += "/"
        var segment = String(segments[i])
        if segment.startswith(":"):
            output += "{" + String(segment[byte=1:]) + "}"
        else:
            output += segment
    return output


def _openapi_parameters(path: String) raises -> Value:
    var params = Value.array()
    var segments = path.split("/")
    for i in range(len(segments)):
        var segment = String(segments[i])
        if segment.startswith(":"):
            var param = Value.object()
            param.set("name", Value(String(segment[byte=1:])))
            param.set("in", Value("path"))
            param.set("required", Value(True))
            var schema = Value.object()
            schema.set("type", Value("string"))
            param.set("schema", schema)
            params.append(param)
    return params^


struct Api:
    """API-first wrapper over Mojara App with registered-route documentation."""

    var app: App
    var title: String
    var version: String
    var _operations: List[Operation]

    def __init__(out self, title: String = "Mojara API", version: String = "0.1.0"):
        """Create an API router with a title and document version."""
        self.app = App()
        self.title = title
        self.version = version
        self._operations = List[Operation]()

    def get(
        mut self,
        path: String,
        callback: def(Request) raises thin -> Response,
        summary: String = "",
    ) raises:
        """Register a documented GET route."""
        self.app.get(path, callback)
        self._operations.append(Operation("get", path, summary))

    def post(
        mut self,
        path: String,
        callback: def(Request) raises thin -> Response,
        summary: String = "",
    ) raises:
        """Register a documented POST route."""
        self.app.post(path, callback)
        self._operations.append(Operation("post", path, summary))

    def post_validated(
        mut self,
        path: String,
        callback: def(Request, Value) raises thin -> Response,
        schema: Schema,
        summary: String = "",
        max_body_bytes: Int = 1048576,
    ) raises:
        """Register a POST route that validates its JSON request body."""
        if max_body_bytes < 1:
            raise Error("max_body_bytes must be positive")
        self.app.post_handler(
            path, _ValidatedRoute(schema.copy(), callback, max_body_bytes)
        )
        self._operations.append(Operation("post", path, summary, schema.copy(), True))

    def put_validated(
        mut self,
        path: String,
        callback: def(Request, Value) raises thin -> Response,
        schema: Schema,
        summary: String = "",
        max_body_bytes: Int = 1048576,
    ) raises:
        """Register a PUT route that validates its JSON request body."""
        if max_body_bytes < 1:
            raise Error("max_body_bytes must be positive")
        self.app.put_handler(
            path, _ValidatedRoute(schema.copy(), callback, max_body_bytes)
        )
        self._operations.append(Operation("put", path, summary, schema.copy(), True))

    def patch_validated(
        mut self,
        path: String,
        callback: def(Request, Value) raises thin -> Response,
        schema: Schema,
        summary: String = "",
        max_body_bytes: Int = 1048576,
    ) raises:
        """Register a PATCH route that validates its JSON request body."""
        if max_body_bytes < 1:
            raise Error("max_body_bytes must be positive")
        self.app.patch_handler(
            path, _ValidatedRoute(schema.copy(), callback, max_body_bytes)
        )
        self._operations.append(Operation("patch", path, summary, schema.copy(), True))

    def secure_get(
        mut self,
        path: String,
        callback: def(Request, Principal) raises thin -> Response,
        auth: AuthStore,
        summary: String = "",
        role: String = "",
    ) raises:
        """Authenticated GET, optionally requiring an exact account role."""
        self.app.get_handler(path, ProtectedRoute(auth.copy(), callback, role))
        self._operations.append(Operation("get", path, summary, Schema(), False, True))

    def secure_post(
        mut self,
        path: String,
        callback: def(Request, Principal) raises thin -> Response,
        auth: AuthStore,
        summary: String = "",
        role: String = "",
    ) raises:
        """Authenticated POST, optionally requiring an exact account role."""
        self.app.post_handler(path, ProtectedRoute(auth.copy(), callback, role))
        self._operations.append(Operation("post", path, summary, Schema(), False, True))

    def openapi_document(self) raises -> Value:
        """Generate OpenAPI 3.1 documentation from registered API operations."""
        var root = Value.object()
        root.set("openapi", Value("3.1.0"))
        var info = Value.object()
        info.set("title", Value(self.title))
        info.set("version", Value(self.version))
        root.set("info", info)
        var paths = Value.object()
        for i in range(len(self._operations)):
            ref op = self._operations[i]
            var item = Value.object()
            for j in range(len(self._operations)):
                ref candidate = self._operations[j]
                if candidate.path != op.path:
                    continue
                var operation = Value.object()
                operation.set("summary", Value(candidate.summary))
                var parameters = _openapi_parameters(candidate.path)
                if parameters.array_count() > 0:
                    operation.set("parameters", parameters)
                var responses = Value.object()
                var success = Value.object()
                success.set("description", Value("Successful response"))
                var success_status = "201" if candidate.method == "post" else "200"
                responses.set(success_status, success)
                if candidate.has_body:
                    var validation_error = Value.object()
                    validation_error.set("description", Value("Invalid request body"))
                    responses.set("422", validation_error)
                    var media = Value.object()
                    media.set("schema", candidate.schema.openapi_schema())
                    var content = Value.object()
                    content.set("application/json", media)
                    var request_body = Value.object()
                    request_body.set("required", Value(True))
                    request_body.set("content", content)
                    operation.set("requestBody", request_body)
                if candidate.secured:
                    var unauthorized = Value.object()
                    unauthorized.set("description", Value("Authentication required"))
                    responses.set("401", unauthorized)
                    var forbidden = Value.object()
                    forbidden.set("description", Value("Insufficient permissions"))
                    responses.set("403", forbidden)
                    var requirement = Value.object()
                    requirement.set("BearerAuth", Value.array())
                    var security = Value.array()
                    security.append(requirement)
                    operation.set("security", security)
                operation.set("responses", responses)
                item.set(candidate.method, operation)
            paths.set(_openapi_path(op.path), item)
        root.set("paths", paths)
        var schemes = Value.object()
        var bearer = Value.object()
        bearer.set("type", Value("http"))
        bearer.set("scheme", Value("bearer"))
        schemes.set("BearerAuth", bearer)
        var components = Value.object()
        components.set("securitySchemes", schemes)
        root.set("components", components)
        return root^

    def install_docs(mut self) raises:
        """Register /openapi.json, /docs and /redoc after API routes are set."""
        var serialized = dumps(self.openapi_document())
        self.app.get_handler("/openapi.json", _DocumentHandler(serialized))
        self.app.get_handler("/docs", _HtmlHandler(_swagger_html()))
        self.app.get_handler("/redoc", _HtmlHandler(_redoc_html()))

    def handle(self, req: Request) raises -> WireResponse:
        """Dispatch an HTTP request through the API router."""
        return self.app.handle(req)

    def run_configured(mut self) raises:
        """Start the API using validated listener configuration."""
        self.app.run_configured()
