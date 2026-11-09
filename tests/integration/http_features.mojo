"""Integration fixture for signed sessions, form bodies and private uploads.

This is a test-only Mojo web application. Test signing key and upload token are
deliberately nonproduction values, and no user credentials are referenced.
"""

from mojara import App, Request, Response, CookieSessionStore
from mojara.web import UploadFile
from mojara.forms import parse_request_form


def _store() raises -> CookieSessionStore:
    var secret = String("mojara-test-hmac-key-only-2026-32-bytes-plus")
    var key = List[UInt8](secret.as_bytes())
    return CookieSessionStore(key^, cookie_name="mojara_ci", ttl_s=300)


def issue_session(req: Request) raises -> Response:
    var store = _store()
    var value = store.encode("session-verified")
    var reply = Response.text("session-issued")
    reply.set_header(
        "Set-Cookie",
        "mojara_ci=" + value + "; Path=/; HttpOnly; SameSite=Lax",
    )
    reply.set_header("Cache-Control", "no-store")
    return reply^


def check_session(req: Request) raises -> Response:
    var store = _store()
    var current = store.load(req)
    if not current.present:
        return Response.error(401, "No valid session")
    return Response.text(current.value)


def accept_form(req: Request) raises -> Response:
    var fields = parse_request_form(req)
    var name = fields.get_first("name")
    if not name:
        return Response.error(400, "Name is required")
    return Response.text("name:" + name.value())


def health(req: Request) raises -> Response:
    return Response.json('{"status":"ok","framework":"Mojara"}')


def main() raises:
    var app = App()
    app.get("/health", health)
    app.get("/session/issue", issue_session)
    app.get("/session/verify", check_session)
    app.post("/form", accept_form)
    app.post_handler(
        "/upload",
        UploadFile(
            "private_uploads",
            max_bytes=1024,
            required_token="ci-upload-token-32-characters-minimum",
        ),
    )
    app.run_configured()
