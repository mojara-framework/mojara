"""Structured JSON-lines application event logging.

Provide only approved operational metadata; never log database credentials,
passwords, bearer tokens or untrusted sensitive request content."""

from json import Value, dumps
from std.os import getenv
from std.ffi import OwnedDLHandle, c_long


def _severity(level: String) -> Int:
    if level == "debug":
        return 10
    if level == "info":
        return 20
    if level == "warn":
        return 30
    if level == "error":
        return 40
    return 20


def log(
    level: String, event: String, message: String = "", request_id: String = ""
) raises:
    """Write one JSON object to stdout with a stable field structure."""
    if level != "debug" and level != "info" and level != "warn" and level != "error":
        raise Error("Unsupported log level")
    if _severity(level) < _severity(getenv("MOJARA_LOG_LEVEL", "info")):
        return
    var libc = OwnedDLHandle("libc.so.6")
    var unix_time = libc.get_function[c_long]("time")
    var obj = Value.object()
    obj.set("timestamp_unix", Value(Int(unix_time(Int(0)))))
    obj.set("level", Value(level))
    obj.set("event", Value(event))
    obj.set("message", Value(message))
    if request_id != "":
        obj.set("request_id", Value(request_id))
    print(dumps(obj))
