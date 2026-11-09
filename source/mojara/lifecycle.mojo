"""Process-local HTTP drain and in-flight request inspection.

Call these helpers during controlled shutdown or readiness transitions.
Drain state does not itself close sockets or cancel active client requests."""
from .platform import library_name
from std.ffi import OwnedDLHandle, c_int


def begin_http_drain() raises:
    """Mark this process unready until its next restart."""
    var lib = OwnedDLHandle(library_name("libmojara_metrics.so", "libmojara_metrics.dylib"))
    var native_call = lib.get_function[c_int]("mj_runtime_begin_drain")
    if native_call() != 1:
        raise Error("Could not begin Mojara readiness drain")


def is_http_draining() raises -> Bool:
    """Report whether the current process is draining HTTP requests."""
    var lib = OwnedDLHandle(library_name("libmojara_metrics.so", "libmojara_metrics.dylib"))
    var native_call = lib.get_function[c_int]("mj_runtime_is_draining")
    return native_call() != 0


def handler_in_flight() raises -> UInt64:
    """Includes the request reading this value when metrics are enabled."""
    var lib = OwnedDLHandle(library_name("libmojara_metrics.so", "libmojara_metrics.dylib"))
    var native_call = lib.get_function[UInt64]("mj_runtime_in_flight")
    return native_call()
