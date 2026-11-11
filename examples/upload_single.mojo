"""Authenticated single-file upload using the Mojara UploadFile handler."""
from mojara import App
from mojara.web import UploadFile
from std.os import getenv


def main() raises:
    var app = App()
    app.post_handler(
        "/upload/photo",
        UploadFile(
            "private_uploads",
            max_bytes=2 * 1024 * 1024,
            required_token=getenv("MOJARA_UPLOAD_TOKEN", ""),
        ),
    )
    app.run_configured()
