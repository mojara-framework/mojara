"""Request validation and HTTP bearer authorization helpers.

Parse JSON bodies within limits, enforce required string fields and reject
requests without expected bearer authentication."""

from json import Value
from flare.http import Request
from . import Response


def json_body(req: Request) raises -> Value:
    """Parse JSON, rejecting non-JSON content types and malformed bodies."""
    var content_type = req.headers.get("content-type")
    if not (
        content_type == "application/json"
        or content_type.startswith("application/json;")
    ):
        raise Error("Content-Type must be application/json")
    return req.json()


def required_string(obj: Value, key: String) raises -> String:
    """Retrieve a required string field, rejecting absent/non-string fields."""
    var result: String
    try:
        var value = obj[key]
        result = value.string_value()
    except:
        raise Error("Missing or invalid string field: " + key)
    if result.byte_length() == 0:
        raise Error("Required field is empty: " + key)
    return result


def bearer_token(req: Request) -> String:
    """Extract a Bearer token; credentials must be checked by the app."""
    var auth = req.headers.get("authorization")
    if auth.startswith("Bearer "):
        return String(auth[byte=7:])
    return ""


def require_bearer(req: Request, expected: String) raises -> Response:
    """Example fixed-token authentication; use verified identity in production."""
    if expected.byte_length() == 0 or bearer_token(req) != expected:
        var reply = Response.error(401, "Unauthorized")
        reply.set_header("WWW-Authenticate", "Bearer")
        return reply^
    return Response.text("Authorized")
