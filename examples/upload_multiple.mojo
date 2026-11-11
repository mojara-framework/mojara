"""Atomic multiple-file upload using Mojara UploadFiles."""
from mojara import App
from mojara.web import UploadFiles
from std.os import getenv


def main() raises:
    var app = App()
    app.post_handler(
        "/upload/attachments",
        UploadFiles(
            "private_uploads",
            max_file_bytes=2 * 1024 * 1024,
            max_total_bytes=6 * 1024 * 1024,
            max_files=3,
            required_token=getenv("MOJARA_UPLOAD_TOKEN", ""),
            allowed_mime_types="application/pdf,image/png",
        ),
    )
    app.run_configured()
