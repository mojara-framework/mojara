"""Mojara request-form parsing for text fields and binary file uploads.

parse_form(req) accepts URL-encoded and multipart browser forms. The HTTP
server owns the request-body limit; applications may opt into stricter limits.
No Flare multipart parsing function is used.
"""
from flare.http import Request


def _from_bytes(var data: List[UInt8]) raises -> String:
    if len(data) == 0:
        return ""
    return String(from_utf8=Span(unsafe_ptr=data.unsafe_ptr(), length=len(data)))


def _hex_digit(value: Int) -> Int:
    if value >= 48 and value <= 57:
        return value - 48
    if value >= 65 and value <= 70:
        return value - 55
    if value >= 97 and value <= 102:
        return value - 87
    return -1


def _url_decode(text: String) raises -> String:
    var data = List[UInt8]()
    var index = 0
    while index < text.byte_length():
        var byte = Int(text.as_bytes()[index])
        if byte == 43:
            data.append(32)
        elif byte == 37:
            if index + 2 >= text.byte_length():
                raise Error("Invalid percent escape in form data")
            var hi = _hex_digit(Int(text.as_bytes()[index + 1]))
            var lo = _hex_digit(Int(text.as_bytes()[index + 2]))
            if hi < 0 or lo < 0:
                raise Error("Invalid percent escape in form data")
            var decoded = hi * 16 + lo
            if decoded == 0:
                raise Error("NUL is not permitted in form data")
            data.append(UInt8(decoded))
            index += 2
        else:
            if byte == 0:
                raise Error("NUL is not permitted in form data")
            data.append(UInt8(byte))
        index += 1
    return _from_bytes(data^)


@fieldwise_init
struct FormFile(Copyable):
    """One uploaded file, kept as binary data until the application saves it."""

    var name: String
    var filename: String
    var content_type: String
    var body: List[UInt8]

    def size(self) -> Int:
        """Return the original file length in bytes."""
        return len(self.body)

    def text(self) raises -> String:
        """Interpret the uploaded content as UTF-8 when appropriate."""
        return _from_bytes(self.body.copy())


struct FormFields(Copyable):
    """Decoded fields and uploaded files from one HTTP form."""

    var names: List[String]
    var values: List[String]
    var uploads: List[FormFile]

    def __init__(out self):
        self.names = List[String]()
        self.values = List[String]()
        self.uploads = List[FormFile]()

    def count(self) -> Int:
        """Return the number of text fields."""
        return len(self.names)

    def get_first(self, key: String) -> Optional[String]:
        """Return the first value for a text field, if any."""
        for i in range(len(self.names)):
            if self.names[i] == key:
                return Optional[String](self.values[i].copy())
        return None

    def file(self, key: String) -> Optional[FormFile]:
        """Return the first file uploaded with the given form-field name."""
        for i in range(len(self.uploads)):
            if self.uploads[i].name == key:
                return Optional[FormFile](self.uploads[i].copy())
        return None

    def files(self, key: String) -> List[FormFile]:
        """Return all files uploaded under the same name, in arrival order."""
        var result = List[FormFile]()
        for i in range(len(self.uploads)):
            if self.uploads[i].name == key:
                result.append(self.uploads[i].copy())
        return result^


def parse_form_encoded(
    body: String, max_bytes: Int = 0, max_fields: Int = 0
) raises -> FormFields:
    """Decode URL-encoded text fields; positive limits opt into stricter checks."""
    if max_bytes < 0 or max_fields < 0:
        raise Error("Form parser limits cannot be negative")
    if max_bytes > 0 and body.byte_length() > max_bytes:
        raise Error("Form body exceeds the configured limit")
    var fields = FormFields()
    if body.byte_length() == 0:
        return fields^
    var parts = body.split("&")
    if max_fields > 0 and len(parts) > max_fields:
        raise Error("Too many form fields")
    for i in range(len(parts)):
        var entry = String(parts[i])
        var split_at = entry.byte_length()
        for j in range(entry.byte_length()):
            if entry.as_bytes()[j] == 61:
                split_at = j
                break
        var name = _url_decode(String(entry[byte=:split_at]))
        if name.byte_length() == 0 or name.byte_length() > 256:
            raise Error("Invalid form field name")
        var value = String("")
        if split_at < entry.byte_length():
            value = _url_decode(String(entry[byte = split_at + 1 :]))
        fields.names.append(name)
        fields.values.append(value)
    return fields^


def _find_bytes(data: List[UInt8], pattern: String, start: Int) -> Int:
    """Locate a delimiter without decoding binary input as text."""
    if pattern.byte_length() == 0 or start < 0:
        return -1
    var last = len(data) - pattern.byte_length()
    for i in range(start, last + 1):
        var matches = True
        for j in range(pattern.byte_length()):
            if data[i + j] != pattern.as_bytes()[j]:
                matches = False
                break
        if matches:
            return i
    return -1


def _extract_boundary(content_type: String) raises -> String:
    var boundary = String("")
    var parts = content_type.split(";")
    for i in range(1, len(parts)):
        var field = String(String(parts[i]).strip())
        if not field.startswith("boundary="):
            continue
        if boundary.byte_length() > 0:
            raise Error("Repeated multipart boundary")
        var value = String(field[byte=9:])
        if value.startswith("\"") and value.endswith("\"") and value.byte_length() >= 2:
            var unquoted = String(value[byte=1:value.byte_length() - 1])
            value = unquoted
        if value.byte_length() == 0 or value.byte_length() > 70:
            raise Error("Invalid multipart boundary")
        for j in range(value.byte_length()):
            var character = Int(value.as_bytes()[j])
            var letter = (character >= 65 and character <= 90) or (character >= 97 and character <= 122)
            var digit = character >= 48 and character <= 57
            var punctuation = character == 39 or character == 40 or character == 41 or character == 43 or character == 44 or character == 45 or character == 46 or character == 47 or character == 58 or character == 61 or character == 63 or character == 95
            if not (letter or digit or punctuation):
                raise Error("Invalid multipart boundary")
        boundary = value
    if boundary.byte_length() == 0:
        raise Error("Missing multipart boundary")
    return boundary


def _parameter(header: String, key: String) -> String:
    var sections = header.split(";")
    for i in range(1, len(sections)):
        var piece = String(String(sections[i]).strip())
        var prefix = key + "="
        if not piece.startswith(prefix):
            continue
        var value = String(piece[byte=prefix.byte_length():])
        if value.startswith("\"") and value.endswith("\"") and value.byte_length() >= 2:
            return String(value[byte=1:value.byte_length() - 1])
        return value
    return ""


def _parse_multipart(
    var data: List[UInt8], content_type: String, max_fields: Int
) raises -> FormFields:
    """Parse multipart in Mojara, preserving binary files and repeated names."""
    var boundary = _extract_boundary(content_type)
    var opening = "--" + boundary
    var delimiter = "\r\n--" + boundary
    var headers_ending = "\r\n\r\n"
    var result = FormFields()
    var pos = 0
    if _find_bytes(data, opening, 0) != 0:
        raise Error("Invalid multipart body start")
    pos = opening.byte_length()
    if _find_bytes(data, "--", pos) == pos:
        if pos + 2 == len(data) or _find_bytes(data, "\r\n", pos + 2) == pos + 2:
            return result^
        raise Error("Invalid empty multipart body")
    if _find_bytes(data, "\r\n", pos) != pos:
        raise Error("Missing multipart header delimiter")
    pos += 2
    var part_count = 0
    while pos < len(data):
        var end_headers = _find_bytes(data, headers_ending, pos)
        if end_headers < 0 or end_headers - pos > 8192:
            raise Error("Invalid multipart part headers")
        var header_bytes = List[UInt8]()
        for j in range(pos, end_headers):
            header_bytes.append(data[j])
        var header_text = _from_bytes(header_bytes^)
        var disposition = String("")
        var mime = String("application/octet-stream")
        var lines = header_text.split("\r\n")
        for i in range(len(lines)):
            var line = String(lines[i])
            var lower_line = line.lower()
            if lower_line.startswith("content-disposition:"):
                if disposition.byte_length() != 0:
                    raise Error("Repeated Content-Disposition")
                disposition = String(String(line[byte=20:]).strip())
            elif lower_line.startswith("content-type:"):
                mime = String(String(line[byte=13:]).strip())
            elif lower_line.startswith("content-transfer-encoding:"):
                raise Error("Unsupported multipart transfer encoding")
        if not disposition.startswith("form-data"):
            raise Error("Missing form-data disposition")
        var name = _parameter(disposition, "name")
        var filename = _parameter(disposition, "filename")
        if name.byte_length() == 0 or name.byte_length() > 256:
            raise Error("Invalid multipart field name")
        part_count += 1
        if max_fields > 0 and part_count > max_fields:
            raise Error("Too many form parts")
        var data_start = end_headers + headers_ending.byte_length()
        var next_boundary = _find_bytes(data, delimiter, data_start)
        while next_boundary >= 0:
            var after = next_boundary + delimiter.byte_length()
            if _find_bytes(data, "\r\n", after) == after or _find_bytes(data, "--", after) == after:
                break
            next_boundary = _find_bytes(data, delimiter, next_boundary + 1)
        if next_boundary < 0:
            raise Error("Missing closing multipart boundary")
        var content = List[UInt8]()
        for i in range(data_start, next_boundary):
            content.append(data[i])
        if filename.byte_length() > 0:
            if filename.byte_length() > 255:
                raise Error("Uploaded filename is too long")
            for i in range(filename.byte_length()):
                var b = Int(filename.as_bytes()[i])
                if b < 32 or b == 127 or b == 47 or b == 92:
                    raise Error("Unsafe uploaded filename")
            result.uploads.append(FormFile(name, filename, mime, content^))
        else:
            result.names.append(name)
            result.values.append(_from_bytes(content^))
        pos = next_boundary + delimiter.byte_length()
        if _find_bytes(data, "--", pos) == pos:
            pos += 2
            if pos == len(data) or (pos + 2 == len(data) and _find_bytes(data, "\r\n", pos) == pos):
                return result^
            raise Error("Invalid multipart end marker")
        if _find_bytes(data, "\r\n", pos) != pos:
            raise Error("Invalid multipart boundary separator")
        pos += 2
    raise Error("Truncated multipart body")


def parse_form(
    req: Request, max_bytes: Int = 0, max_fields: Int = 0
) raises -> FormFields:
    """Read URL-encoded or multipart forms using Mojara's own parser."""
    if max_bytes < 0 or max_fields < 0:
        raise Error("Form parser limits cannot be negative")
    if max_bytes > 0 and len(req.body) > max_bytes:
        raise Error("Form body exceeds the configured limit")
    var content_type = req.headers.get("content-type")
    if content_type == "application/x-www-form-urlencoded" or content_type.startswith("application/x-www-form-urlencoded;"):
        return parse_form_encoded(_from_bytes(req.body.copy()), max_bytes, max_fields)
    if content_type.startswith("multipart/form-data;"):
        return _parse_multipart(req.body.copy(), content_type, max_fields)
    raise Error("Expected URL-encoded or multipart form data")


def parse_request_form(
    req: Request, max_bytes: Int = 0, max_fields: Int = 0
) raises -> FormFields:
    """Compatibility alias; prefer parse_form(req)."""
    return parse_form(req, max_bytes, max_fields)
