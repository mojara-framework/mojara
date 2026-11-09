"""HTML template rendering, static resources, and multipart uploads.

Handlers validate request-derived filenames and enforce filesystem bounds.
Templates renders trusted files with explicit interpolation context."""
from std.ffi import OwnedDLHandle, c_int
from std.os import getenv
from flare.http import Handler, Request
from json import Value
from . import Response, WireResponse, TemplateContext


def _safe_filename(filename: String) -> Bool:
    if filename.byte_length() < 1 or filename.byte_length() > 120:
        return False
    if filename.as_bytes()[0] == 46:
        return False
    for i in range(filename.byte_length()):
        var char = Int(filename.as_bytes()[i])
        if not (
            (char >= 65 and char <= 90)
            or (char >= 97 and char <= 122)
            or (char >= 48 and char <= 57)
            or char == 45
            or char == 95
            or char == 46
        ):
            return False
    return True


struct Templates(Copyable):
    var directory: String

    def __init__(out self, directory: String = "templates") raises:
        """Choose the trusted template source directory."""
        if directory.byte_length() == 0 or directory.byte_length() > 2048:
            raise Error("Invalid template directory")
        self.directory = directory

    def render(self, filename: String, var context: TemplateContext) raises -> Response:
        """Render a validated HTML template with the provided context."""
        if not _safe_filename(filename) or not filename.endswith(".html"):
            raise Error("Invalid template filename")
        return Response.render_file(self.directory + "/" + filename, context^)


def _content_type(filename: String) -> String:
    if filename.endswith(".css"):
        return "text/css; charset=utf-8"
    if filename.endswith(".js"):
        return "text/javascript; charset=utf-8"
    if filename.endswith(".svg"):
        return "image/svg+xml"
    if filename.endswith(".png"):
        return "image/png"
    if filename.endswith(".jpg") or filename.endswith(".jpeg"):
        return "image/jpeg"
    if filename.endswith(".webp"):
        return "image/webp"
    if filename.endswith(".html"):
        return "text/html; charset=utf-8"
    if filename.endswith(".txt"):
        return "text/plain; charset=utf-8"
    return "application/octet-stream"


struct StaticFile(Copyable, Handler):
    """Serve files by a single router parameter named `name`. No traversal."""

    var root: String
    var max_bytes: Int

    def __init__(out self, root: String, max_bytes: Int = 2 * 1024 * 1024):
        """Configure a static-file handler rooted at a trusted directory."""
        self.root = root
        self.max_bytes = max_bytes

    def serve(self, req: Request) raises -> WireResponse:
        """Serve a validated filename from the configured static directory."""
        var filename = req.param("name")
        if not _safe_filename(filename):
            var denied = Response.error(404, "Not found")
            return (denied^).into_wire()
        var name_owned = filename.copy()
        var root_owned = self.root.copy()
        var bytes = List[UInt8]()
        for _ in range(self.max_bytes):
            bytes.append(0)
        var used = List[Int64]()
        used.append(0)
        var lib = OwnedDLHandle("libmojara_web.so")
        var read = lib.get_function[c_int]("mj_web_read_static")
        var result = read(
            root_owned.as_c_string_span(),
            name_owned.as_c_string_span(),
            Int(bytes.unsafe_ptr()),
            Int64(len(bytes)),
            Int(used.unsafe_ptr()),
        )
        if result != 1:
            var missing = Response.error(
                404 if result == 0 else 413, "File unavailable"
            )
            return (missing^).into_wire()
        var payload = List[UInt8]()
        for i in range(Int(used[0])):
            payload.append(bytes[i])
        var empty_response = Response.text("")
        var wire = (empty_response^).into_wire()
        wire.body = payload^
        wire.headers.set("Content-Type", _content_type(filename))
        wire.headers.set("X-Content-Type-Options", "nosniff")
        wire.headers.set("Cache-Control", "public, max-age=300")
        return wire^


struct UploadFile(Copyable, Handler):
    """Private single-file multipart endpoint. Server generates the filename."""

    var directory: String
    var max_bytes: Int
    var required_token: String

    def __init__(
        out self,
        directory: String,
        max_bytes: Int = 2 * 1024 * 1024,
        required_token: String = "",
    ):
        """Configure a bounded single-file upload handler."""
        self.directory = directory
        self.max_bytes = max_bytes
        self.required_token = required_token

    def serve(self, req: Request) raises -> WireResponse:
        """Validate and persist one multipart file."""
        if self.required_token.byte_length() < 24:
            var disabled = Response.error(
                503, "Upload authentication is not configured"
            )
            return (disabled^).into_wire()
        if req.headers.get("x-mojara-upload-token") != self.required_token:
            var forbidden = Response.error(403, "Forbidden")
            return (forbidden^).into_wire()
        var content_type = req.headers.get("content-type")
        if not content_type.startswith("multipart/form-data;"):
            var wrong_type = Response.error(415, "Expected multipart/form-data")
            return (wrong_type^).into_wire()
        if len(req.body) > self.max_bytes + 8192:
            var too_large = Response.error(413, "Upload limit exceeded")
            return (too_large^).into_wire()
        var body = req.body.copy()
        if len(body) == 0:
            var empty = Response.error(400, "Empty upload")
            return (empty^).into_wire()
        var directory = self.directory.copy()
        var mime = content_type.copy()
        var filename = List[UInt8]()
        for _ in range(80):
            filename.append(0)
        var file_bytes = List[Int64]()
        file_bytes.append(0)
        var lib = OwnedDLHandle("libmojara_web.so")
        var save = lib.get_function[c_int]("mj_web_store_multipart")
        var status = save(
            directory.as_c_string_span(),
            mime.as_c_string_span(),
            body.unsafe_ptr(),
            Int64(len(body)),
            Int64(self.max_bytes),
            Int(filename.unsafe_ptr()),
            Int64(len(filename)),
            Int(file_bytes.unsafe_ptr()),
        )
        if status != 1:
            var code = 413 if status == -2 else (500 if status == -3 else 400)
            var invalid = Response.error(code, "Upload rejected")
            return (invalid^).into_wire()
        # Copy the native output bytes through a bounded Mojo List before
        # turning them into UTF-8. Direct unsafe_from_utf8_ptr construction
        # returned an empty string on both Linux ARM64 and x86-64 with
        # Mojo 1.2.0, even though C had saved the file successfully.
        var name_bytes = List[UInt8]()
        for i in range(len(filename)):
            var character = filename[i]
            if character == 0:
                break
            name_bytes.append(character)
        if len(name_bytes) != 43:
            raise Error("Native upload returned an invalid stored filename")
        var stored = String(
            from_utf8=Span(unsafe_ptr=name_bytes.unsafe_ptr(), length=len(name_bytes))
        )
        var result = Value.object()
        result.set("stored_name", Value(stored))
        result.set("bytes", Value(Int(file_bytes[0])))
        var reply = Response.created_value(result)
        reply.set_header("Cache-Control", "no-store")
        return (reply^).into_wire()


struct UploadFiles(Copyable, Handler):
    """Atomic multi-file multipart endpoint with private generated filenames.

    `allowed_mime_types` is an optional comma-separated allowlist of declared
    media types (e.g. "application/pdf,image/*"). This is a header policy,
    NOT proof of the uploaded bytes' actual file format.
    """

    var directory: String
    var max_file_bytes: Int
    var max_total_bytes: Int
    var max_files: Int
    var required_token: String
    var allowed_mime_types: String

    def __init__(
        out self,
        directory: String,
        max_file_bytes: Int = 2 * 1024 * 1024,
        max_total_bytes: Int = 8 * 1024 * 1024,
        max_files: Int = 5,
        required_token: String = "",
        allowed_mime_types: String = "",
    ) raises:
        """Configure limits for a multi-file upload handler."""
        if directory.byte_length() == 0 or directory.byte_length() > 2048:
            raise Error("Invalid private upload directory")
        if max_file_bytes < 1 or max_file_bytes > 64 * 1024 * 1024:
            raise Error("Invalid per-file upload limit")
        if max_total_bytes < 1 or max_total_bytes > 128 * 1024 * 1024:
            raise Error("Invalid total upload limit")
        if max_files < 1 or max_files > 32:
            raise Error("Invalid maximum upload file count")
        if allowed_mime_types.byte_length() > 1024:
            raise Error("Upload MIME allowlist is too long")
        self.directory = directory
        self.max_file_bytes = max_file_bytes
        self.max_total_bytes = max_total_bytes
        self.max_files = max_files
        self.required_token = required_token
        self.allowed_mime_types = allowed_mime_types

    def serve(self, req: Request) raises -> WireResponse:
        """Validate and persist a bounded multipart file collection."""
        if self.required_token.byte_length() < 24:
            var disabled = Response.error(
                503, "Upload authentication is not configured"
            )
            return (disabled^).into_wire()
        if req.headers.get("x-mojara-upload-token") != self.required_token:
            var forbidden = Response.error(403, "Forbidden")
            return (forbidden^).into_wire()
        var content_type = req.headers.get("content-type")
        if not content_type.startswith("multipart/form-data;"):
            var wrong_type = Response.error(415, "Expected multipart/form-data")
            return (wrong_type^).into_wire()
        if len(req.body) > self.max_total_bytes + self.max_files * (8192 + 128) + 128:
            var too_large = Response.error(413, "Upload request limit exceeded")
            return (too_large^).into_wire()
        var body = req.body.copy()
        if len(body) == 0:
            var empty = Response.error(400, "Empty upload request")
            return (empty^).into_wire()
        var directory = self.directory.copy()
        var media_type = content_type.copy()
        var policy = self.allowed_mime_types.copy()
        # Six C ABI arguments, all passed in registers on Linux x86_64.
        # The native bridge validates this single in/out buffer's capacity.
        # Layout: 24-byte little-endian limits, 1025-byte NUL-terminated MIME
        # allowlist, then an 8-byte header and 32 fixed 200-byte file records.
        var config_bytes = 24 + 1025
        var records_offset = config_bytes + 8
        var transfer = List[UInt8]()
        for _ in range(records_offset + 32 * 200):
            transfer.append(0)
        var limits = List[Int]()
        limits.append(self.max_file_bytes)
        limits.append(self.max_total_bytes)
        limits.append(self.max_files)
        for field in range(3):
            var value = limits[field]
            for byte_index in range(8):
                transfer[field * 8 + byte_index] = UInt8(value % 256)
                value = value // 256
        for i in range(policy.byte_length()):
            transfer[24 + i] = policy.as_bytes()[i]
        var lib = OwnedDLHandle("libmojara_web.so")
        var save = lib.get_function[c_int]("mj_web_store_multipart_multi_inline")
        var status = save(
            directory.as_c_string_span(),
            media_type.as_c_string_span(),
            body.unsafe_ptr(),
            Int64(len(body)),
            transfer.unsafe_ptr(),
            Int64(len(transfer)),
        )
        if status != 1:
            var code = 413 if status == -2 or status == -4 else (
                415 if status == -5 else (500 if status == -3 else 400)
            )
            var reason = "Multi-file upload rejected"
            # Diagnostic metadata only. Enabled by local, opt-in HTTP test;
            # never exposes uploaded bytes, filenames, paths or auth tokens.
            if getenv("MOJARA_UPLOAD_DIAGNOSTICS", "0") == "1":
                reason += " [native_status=" + String(status) + "]"
            var rejected = Response.error(code, reason)
            return (rejected^).into_wire()
        var records = Value.array()
        var count = Int(transfer[config_bytes])
        for i in range(count):
            var base = records_offset + i * 200
            var name = String(
                unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
                    unsafe_from_address=Int(transfer.unsafe_ptr()) + base
                )
            )
            var mime = String(
                unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
                    unsafe_from_address=Int(transfer.unsafe_ptr()) + base + 64
                )
            )
            var size: Int = 0
            var multiplier: Int = 1
            for j in range(8):
                size += Int(transfer[base + 192 + j]) * multiplier
                multiplier *= 256
            var record = Value.object()
            record.set("stored_name", Value(name))
            record.set("bytes", Value(size))
            record.set("content_type", Value(mime))
            records.append(record)
        var result = Value.object()
        result.set("count", Value(count))
        result.set("files", records)
        var reply = Response.created_value(result)
        reply.set_header("Cache-Control", "no-store")
        return (reply^).into_wire()
