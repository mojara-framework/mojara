"""Database-backed authentication and route-level role authorization.

AuthStore manages accounts, password verification, sessions, and token
revocation. ProtectedRoute validates identity and authorization at dispatch."""

from flare.http import Request, Handler
from sqlite import Database
from . import Response, WireResponse
from .database import open_sqlite
from .security import bearer_token
from .crypto import (
    ensure_crypto,
    hash_password,
    verify_password,
    new_token,
    token_digest,
)


@fieldwise_init
struct Principal(Copyable):
    """Identity resolved from a valid bearer token."""

    var id: Int
    var email: String
    var role: String


struct AuthStore(Copyable):
    """Stateless facade: each call uses its own SQLite database connection."""

    var db_path: String

    def __init__(out self, path: String) raises:
        """Select the authentication database path."""
        if path.byte_length() == 0 or path == ":memory:":
            raise Error("Authentication requires a persistent SQLite file")
        self.db_path = path

    def install(self) raises:
        """Idempotent setup of authorization tables (run before serving)."""
        ensure_crypto()
        var db = open_sqlite(self.db_path)
        db.execute(
            "CREATE TABLE IF NOT EXISTS mojara_auth_users ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "email TEXT NOT NULL UNIQUE COLLATE NOCASE,"
            "password_hash TEXT NOT NULL,"
            "role TEXT NOT NULL DEFAULT 'user',"
            "enabled INTEGER NOT NULL DEFAULT 1,"
            "created_at INTEGER NOT NULL DEFAULT (unixepoch()))"
        )
        db.execute(
            "CREATE TABLE IF NOT EXISTS mojara_auth_tokens (token_hash TEXT PRIMARY"
            " KEY,user_id INTEGER NOT NULL REFERENCES mojara_auth_users(id) ON DELETE"
            " CASCADE,expires_at INTEGER NOT NULL,created_at INTEGER NOT NULL DEFAULT"
            " (unixepoch()))"
        )
        db.execute(
            "CREATE INDEX IF NOT EXISTS mojara_auth_token_user_idx "
            "ON mojara_auth_tokens(user_id)"
        )
        db.execute(
            "CREATE TABLE IF NOT EXISTS mojara_auth_attempts ("
            "email TEXT PRIMARY KEY COLLATE NOCASE,"
            "attempts INTEGER NOT NULL,"
            "window_started INTEGER NOT NULL)"
        )

    def register(self, email: String, password: String) raises -> Int:
        """Register a regular user. Role cannot be chosen by the caller."""
        if email.byte_length() < 3 or email.byte_length() > 254:
            raise Error("Invalid email length")
        if (
            len(email.split("@")) != 2
            or len(email.split("\n")) != 1
            or len(email.split("\r")) != 1
        ):
            raise Error("Invalid email address")
        var encoded = hash_password(password)
        var db = open_sqlite(self.db_path)
        var stmt = db.prepare(
            "INSERT INTO mojara_auth_users(email, password_hash, role) "
            "VALUES (?, ?, 'user')"
        )
        stmt.bind_text(1, email)
        stmt.bind_text(2, encoded)
        _ = stmt.step()
        var result = db.prepare("SELECT last_insert_rowid()")
        var maybe = result.step()
        if not Bool(maybe):
            raise Error("Registration failed")
        return maybe.value().int_val(0)

    def login(
        self, email: String, password: String, ttl_seconds: Int = 3600
    ) raises -> String:
        """Verify credentials; enforce max 5 tries/email/15min; issue token."""
        if ttl_seconds < 60 or ttl_seconds > 2592000:
            raise Error("Token lifetime must be 60 seconds to 30 days")
        if email.byte_length() < 3 or email.byte_length() > 254:
            raise Error("Invalid credentials")
        var db = open_sqlite(self.db_path)
        var attempt = db.prepare(
            "INSERT INTO mojara_auth_attempts(email, attempts, window_started) "
            "VALUES (?, 1, unixepoch()) ON CONFLICT(email) DO UPDATE SET "
            "attempts = CASE WHEN window_started <= unixepoch() - 900 "
            "THEN 1 ELSE attempts + 1 END, "
            "window_started = CASE WHEN window_started <= unixepoch() - 900 "
            "THEN unixepoch() ELSE window_started END"
        )
        attempt.bind_text(1, email)
        _ = attempt.step()
        var tries = db.prepare(
            "SELECT attempts FROM mojara_auth_attempts WHERE email = ?"
        )
        tries.bind_text(1, email)
        var count = tries.step()
        if not Bool(count) or count.value().int_val(0) > 5:
            raise Error("Too many login attempts. Try again later")
        var user_stmt = db.prepare(
            "SELECT id, password_hash FROM mojara_auth_users "
            "WHERE email = ? AND enabled = 1"
        )
        user_stmt.bind_text(1, email)
        var user = user_stmt.step()
        if not Bool(user):
            raise Error("Invalid credentials")
        var id = user.value().int_val(0)
        var encoded = user.value().text_val(1)
        if not verify_password(password, encoded):
            raise Error("Invalid credentials")
        var clear_attempts = db.prepare(
            "DELETE FROM mojara_auth_attempts WHERE email = ?"
        )
        clear_attempts.bind_text(1, email)
        _ = clear_attempts.step()
        var token = new_token()
        var ins = db.prepare(
            "INSERT INTO mojara_auth_tokens(token_hash, user_id, expires_at) "
            "VALUES (?, ?, unixepoch() + ?)"
        )
        ins.bind_text(1, token_digest(token))
        ins.bind_int(2, id)
        ins.bind_int(3, ttl_seconds)
        _ = ins.step()
        return token^

    def authenticate(self, req: Request) raises -> Optional[Principal]:
        """Return resolved identity or None; expired/revoked tokens fail shut."""
        var token = bearer_token(req)
        if token.byte_length() != 64:
            return None
        var db = open_sqlite(self.db_path)
        var stmt = db.prepare(
            "SELECT u.id, u.email, u.role FROM mojara_auth_users AS u "
            "JOIN mojara_auth_tokens AS t ON t.user_id = u.id "
            "WHERE t.token_hash = ? AND t.expires_at > unixepoch() "
            "AND u.enabled = 1"
        )
        stmt.bind_text(1, token_digest(token))
        var row = stmt.step()
        if not Bool(row):
            return None
        return Optional[Principal](
            Principal(
                row.value().int_val(0),
                row.value().text_val(1),
                row.value().text_val(2),
            )
        )

    def logout(self, req: Request) raises:
        """Immediately revoke the supplied bearer token."""
        var token = bearer_token(req)
        if token.byte_length() != 64:
            return
        var db = open_sqlite(self.db_path)
        var stmt = db.prepare("DELETE FROM mojara_auth_tokens WHERE token_hash = ?")
        stmt.bind_text(1, token_digest(token))
        _ = stmt.step()

    def revoke_user(self, id: Int) raises:
        """Revoke every token belonging to a user (trusted admin operation)."""
        var db = open_sqlite(self.db_path)
        var stmt = db.prepare("DELETE FROM mojara_auth_tokens WHERE user_id = ?")
        stmt.bind_int(1, id)
        _ = stmt.step()

    def set_role(self, id: Int, role: String) raises:
        """Trusted administrative operation; never bind directly to signup."""
        if role != "user" and role != "admin" and role != "moderator":
            raise Error("Unsupported role")
        var db = open_sqlite(self.db_path)
        var stmt = db.prepare("UPDATE mojara_auth_users SET role = ? WHERE id = ?")
        stmt.bind_text(1, role)
        stmt.bind_int(2, id)
        _ = stmt.step()

    def disable(self, id: Int) raises:
        """Disable user and invalidate outstanding bearer tokens."""
        var db = open_sqlite(self.db_path)
        var tx = db.transaction()
        var stmt = db.prepare("UPDATE mojara_auth_users SET enabled = 0 WHERE id = ?")
        stmt.bind_int(1, id)
        _ = stmt.step()
        var revoke = db.prepare("DELETE FROM mojara_auth_tokens WHERE user_id = ?")
        revoke.bind_int(1, id)
        _ = revoke.step()
        tx.commit()

    def clear_expired_tokens(self) raises:
        """Delete expired token records."""
        var db = open_sqlite(self.db_path)
        db.execute("DELETE FROM mojara_auth_tokens WHERE expires_at <= unixepoch()")


@fieldwise_init
struct ProtectedRoute(Copyable, Handler):
    """Per-route authentication and role enforcement; no global state."""

    var auth: AuthStore
    var callback: def(Request, Principal) raises thin -> Response
    var role: String

    def serve(self, req: Request) raises -> WireResponse:
        """Authenticate the request, check its required role and dispatch."""
        var principal = self.auth.authenticate(req)
        if not Bool(principal):
            var denied = Response.error(401, "Authentication required")
            denied.set_header("WWW-Authenticate", "Bearer")
            denied.set_header("Cache-Control", "no-store")
            return (denied^).into_wire()
        var person = principal.value().copy()
        if self.role != "" and person.role != self.role:
            var forbidden = Response.error(403, "Forbidden")
            return (forbidden^).into_wire()
        var reply = self.callback(req, person)
        reply.set_header("Cache-Control", "no-store")
        return (reply^).into_wire()
