"""Receive text fields and a file with a single Mojara parse_form call."""
from mojara import App, Request, Response
from mojara.forms import parse_form


def create_profile(req: Request) raises -> Response:
    var form = parse_form(req)
    var username = form.get_first("username")
    if not Bool(username) or username.value().byte_length() == 0:
        return Response.error(400, "Username is required")

    var avatar = form.file("avatar")
    if Bool(avatar):
        var picture = avatar.value().copy()
        if picture.size() > 2 * 1024 * 1024:
            return Response.error(413, "Image is too large")
        if picture.content_type != "image/png":
            return Response.error(415, "Choose a PNG image")
        return Response.text(
            "Received " + username.value() + " with "
            + String(picture.size()) + " image bytes"
        )

    return Response.text("Received " + username.value() + " without an image")


def main() raises:
    var app = App()
    app.post("/profile", create_profile)
    app.run_configured()
