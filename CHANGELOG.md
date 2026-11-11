# Changelog

## 1.2.10 - Unified forms and file uploads (2026-11-11)

- Unified `parse_form(req)` handles URL-encoded and multipart forms, including multiple binary files.
- Removed the extra default form-body and field-count limits; HTTP request-body and upload policies remain configurable.
- Added three complete file-upload examples and expanded the forms API documentation.

## 1.2.9 - Forms, SQL helpers and static files (2026-11-10)

- The public request parser is `parse_form(req)`; optional body limits remain configurable.
- Portable database helpers: `query()`, `fetch_one()`, `fetch_all()`, `insert()`, `update()`, and `delete()`.
- `StaticFile("static/vendor/bootstrap")` uses a safe 4 MiB per-file default with no numeric argument required.
- All changes are distributed through fresh native packages and Docker images after successful platform qualification.

## 1.2.8 - Initial release (2026-11-10)

Mojara is a web framework written in Mojo, with full first-party source code, a native command-line interface and reproducible builds.

- HTTP routing, APIs, middleware, templates and static assets
- Authentication, sessions, cookies, forms, uploads and WebSockets
- PostgreSQL, MySQL and SQLite integration with pooling and transactions
- Native Conda packages for Linux x86-64, Linux ARM64 and macOS Apple Silicon
- Windows support through WSL2, plus Intel Mac support using Docker or a Linux VM
- Official AMD64 and ARM64 Docker images, with Docker Compose support
- Fast development reloads that reuse the compiled application for static-file changes
- Source-pinned dependencies, native ABI checks and independently qualified release packages
- Public tutorials, complete API reference and hosted documentation

[Download Mojara 1.2.8](https://github.com/mojara-framework/mojara/releases/tag/v1.2.8)
