"""Bounded URL-encoded request body parsing.

FormFields stores decoded fields. Parsing enforces supported content types
and limits request data before exposing values to application handlers."""
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


struct FormFields(Copyable):
    """Parsed key/value pairs; get_first returns None when a key is absent."""

    var names: List[String]
    var values: List[String]

    def __init__(out self):
        """Initialize a collection of decoded form fields."""
        self.names = List[String]()
        self.values = List[String]()

    def count(self) -> Int:
        """Return the total number of decoded fields."""
        return len(self.names)

    def get_first(self, key: String) -> Optional[String]:
        """Return the first value for a field or None if absent."""
        for i in range(len(self.names)):
            if self.names[i] == key:
                return Optional[String](self.values[i].copy())
        return None


def parse_form_encoded(
    body: String, max_bytes: Int = 65536, max_fields: Int = 64
) raises -> FormFields:
    """Decode and validate a bounded URL-encoded form body."""
    if max_bytes < 1 or max_fields < 1 or body.byte_length() > max_bytes:
        raise Error("Form body exceeds configured limits")
    var fields = FormFields()
    if body.byte_length() == 0:
        return fields^
    var parts = body.split("&")
    if len(parts) > max_fields:
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


def parse_request_form(
    req: Request, max_bytes: Int = 65536, max_fields: Int = 64
) raises -> FormFields:
    """Read and decode a URL-encoded HTTP request body."""
    var content_type = req.headers.get("content-type")
    if not (
        content_type == "application/x-www-form-urlencoded"
        or content_type.startswith("application/x-www-form-urlencoded;")
    ):
        raise Error("Expected application/x-www-form-urlencoded")
    if len(req.body) > max_bytes:
        raise Error("Form body exceeds configured limits")
    var bytes = req.body.copy()
    return parse_form_encoded(_from_bytes(bytes^), max_bytes, max_fields)
