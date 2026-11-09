"""Process-local HTTP metrics snapshots.

Expose aggregate request metrics without recording individual request
bodies, credentials or route-specific secret material."""
from std.ffi import OwnedDLHandle


def metrics_snapshot_json() raises -> String:
    """Return atomic-counter snapshot (non-transactional across fields)."""
    var lib = OwnedDLHandle("libmojara_metrics.so")
    var snapshot = lib.get_function[Int]("mj_metrics_snapshot_json")
    var address = snapshot()
    if address == 0:
        raise Error("Mojara native telemetry snapshot failed")
    return String(
        unsafe_from_utf8_ptr=Pointer[UInt8, MutUntrackedOrigin](
            unsafe_from_address=address
        )
    )
