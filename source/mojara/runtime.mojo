"""Validated HTTP listener configuration.

RuntimeSettings selects host, port and HTTP worker count from process
environment variables with safe defaults and explicit bounds."""

from std.os import getenv


def parse_runtime_number(
    text: String, label: String, minimum: Int, maximum: Int
) raises -> Int:
    """Parse bounded positive decimal settings without permissive coercions."""
    if text.byte_length() == 0 or text.byte_length() > 8:
        raise Error("Invalid " + label)
    var result = 0
    for i in range(text.byte_length()):
        var digit = Int(text.as_bytes()[i]) - 48
        if digit < 0 or digit > 9:
            raise Error("Invalid " + label)
        result = result * 10 + digit
        if result > maximum:
            raise Error(label + " exceeds its maximum")
    if result < minimum:
        raise Error(label + " is below its minimum")
    return result


struct RuntimeSettings(Copyable):
    """Validated network listener and Flare worker settings."""

    var host: String
    var port: UInt16
    var workers: Int

    def __init__(out self, host: String, port: UInt16, workers: Int) raises:
        """Initialize or copy HTTP listener and worker settings."""
        if host.byte_length() == 0:
            raise Error("MOJARA_HOST cannot be empty")
        if port == 0:
            raise Error("MOJARA_PORT must be 1..65535")
        if workers < 1 or workers > 64:
            raise Error("MOJARA_WORKERS must be 1..64")
        self.host = host
        self.port = port
        self.workers = workers

    def __init__(out self, *, copy: Self):
        """Copy this value while preserving its resource ownership contract."""
        self.host = copy.host
        self.port = copy.port
        self.workers = copy.workers


def load_runtime_settings(
    host: String = "127.0.0.1", port: UInt16 = 8000, workers: Int = 1
) raises -> RuntimeSettings:
    """Read process env overrides, preserving AppConfig values as defaults."""
    var configured_host = getenv("MOJARA_HOST", host)
    var configured_port = parse_runtime_number(
        getenv("MOJARA_PORT", String(port)), "MOJARA_PORT", 1, 65535
    )
    var configured_workers = parse_runtime_number(
        getenv("MOJARA_WORKERS", String(workers)), "MOJARA_WORKERS", 1, 64
    )
    return RuntimeSettings(configured_host, UInt16(configured_port), configured_workers)
