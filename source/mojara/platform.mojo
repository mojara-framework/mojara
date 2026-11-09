"""Native library file selection for Mojara's supported compilation targets.

All first-party native bridges use the shared platform-specific naming
convention; callers do not need to manage dynamic library suffixes.
"""

from std.sys.info import CompilationTarget


def library_name(linux: String, macos: String) -> String:
    """Return the correct native dynamic-library filename for this host."""
    if CompilationTarget.is_macos():
        return macos
    return linux
