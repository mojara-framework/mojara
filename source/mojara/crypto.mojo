"""Native password hashing and cryptographic bearer token utilities.

Hashes and token digests are computed by the native cryptography backend.
Never expose raw credentials or token material in application logs."""

from .platform import library_name
from std.ffi import OwnedDLHandle, c_int, c_size_t, c_ulong_long


def _hex(bytes: List[UInt8]) raises -> String:
    var output = List[UInt8]()
    var alphabet = "0123456789abcdef"
    for i in range(len(bytes)):
        var value = Int(bytes[i])
        output.append(alphabet.as_bytes()[value // 16])
        output.append(alphabet.as_bytes()[value % 16])
    return String(from_utf8=Span(unsafe_ptr=output.unsafe_ptr(), length=len(output)))


def ensure_crypto() raises:
    """Check that the required native cryptography backend is available."""
    var sodium = OwnedDLHandle(library_name("libsodium.so.23", "libsodium.23.dylib"))
    var init = sodium.get_function[c_int]("sodium_init")
    if init() < 0:
        raise Error("libsodium initialization failed")


def hash_password(password: String) raises -> String:
    """Hash password with libsodium's Argon2id (3 ops, 64 MiB).

    Validate size before calling into C. No secret is logged. String values are
    passed as a pointer and explicit length; embedded NUL is not accepted.
    """
    if password.byte_length() < 12 or password.byte_length() > 1024:
        raise Error("Password must contain between 12 and 1024 UTF-8 bytes")
    for i in range(password.byte_length()):
        if password.as_bytes()[i] == 0:
            raise Error("Password cannot contain a NUL byte")
    var sodium = OwnedDLHandle(library_name("libsodium.so.23", "libsodium.23.dylib"))
    var init = sodium.get_function[c_int]("sodium_init")
    if init() < 0:
        raise Error("libsodium initialization failed")
    var result = List[UInt8]()
    for _ in range(128):
        result.append(0)
    var crypto_function = sodium.get_function[c_int]("crypto_pwhash_str")
    var password_bytes = password.as_bytes()
    var status = crypto_function(
        result.unsafe_ptr(),
        password_bytes.unsafe_ptr(),
        c_ulong_long(password.byte_length()),
        c_ulong_long(3),
        c_size_t(67108864),
    )
    if status != 0:
        raise Error("Argon2id password hashing failed")
    var count = 0
    while count < len(result) and result[count] != 0:
        count += 1
    if count == len(result):
        raise Error("Invalid password hash length")
    return String(from_utf8=Span(unsafe_ptr=result.unsafe_ptr(), length=count))


def verify_password(password: String, encoded_hash: String) raises -> Bool:
    """Verify a password without exposing the password hash to users."""
    if password.byte_length() > 1024 or encoded_hash.byte_length() == 0:
        return False
    var sodium = OwnedDLHandle(library_name("libsodium.so.23", "libsodium.23.dylib"))
    var init = sodium.get_function[c_int]("sodium_init")
    if init() < 0:
        raise Error("libsodium initialization failed")
    var crypto_function = sodium.get_function[c_int]("crypto_pwhash_str_verify")
    var password_bytes = password.as_bytes()
    var encoded_copy = encoded_hash.copy()
    var encoded_cstring = encoded_copy.as_c_string_span()
    return (
        crypto_function(
            encoded_cstring,
            password_bytes.unsafe_ptr(),
            c_ulong_long(password.byte_length()),
        )
        == 0
    )


def new_token() raises -> String:
    """Generate a 256-bit cryptographically random, lowercase hex token."""
    var sodium = OwnedDLHandle(library_name("libsodium.so.23", "libsodium.23.dylib"))
    var init = sodium.get_function[c_int]("sodium_init")
    if init() < 0:
        raise Error("libsodium initialization failed")
    var bytes = List[UInt8]()
    for _ in range(32):
        bytes.append(0)
    var random = sodium.get_function[NoneType]("randombytes_buf")
    random(bytes.unsafe_ptr(), c_size_t(32))
    return _hex(bytes)


def token_digest(token: String) raises -> String:
    """SHA-256 digest for database token lookup; raw token is never stored."""
    var sodium = OwnedDLHandle(library_name("libsodium.so.23", "libsodium.23.dylib"))
    var init = sodium.get_function[c_int]("sodium_init")
    if init() < 0:
        raise Error("libsodium initialization failed")
    var digest = List[UInt8]()
    for _ in range(32):
        digest.append(0)
    var sha256 = sodium.get_function[c_int]("crypto_hash_sha256")
    var token_bytes = token.as_bytes()
    if (
        sha256(
            digest.unsafe_ptr(),
            token_bytes.unsafe_ptr(),
            c_ulong_long(token.byte_length()),
        )
        != 0
    ):
        raise Error("SHA-256 failed")
    return _hex(digest)
