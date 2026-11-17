# Build a static website with Mojara

Mojara includes a native Mojo static site generator for documentation, blogs, portfolios and product websites. It converts Markdown and HTML templates into ready-to-host HTML, CSS and other static assets. No Python or Node.js runtime is needed.

## 1. Create a site

Install Mojara using the [installation guide](INSTALL-LINUX.md), then create a site:

```bash
mojara site new mysite
cd mysite
```

This creates:

```text
mysite/
├── mojara.project
├── content/
│   └── index.md
├── templates/
│   └── base.html
└── static/
    └── style.css
```

Static sites use a separate workflow from dynamic applications. The usual `mojara new`, `mojara dev` and `mojara build` commands remain unchanged.

## 2. Write Markdown

Edit `content/index.md`:

```markdown
---
title: My Website
description: Notes built using Mojara.
---

# Hello from Mojo

A **fast** website powered by Mojo.

- Documentation
- Blog posts
- Project pages

Read the [installation guide](https://mojara.kasua.ng/docs/).
```

The generator supports headings (`#` through `######`), paragraphs, unordered lists, fenced code blocks, bold, inline code and Markdown links. Front matter supports `title:` and `description:`. Untrusted HTML in Markdown is escaped, and links with unsafe URL schemes are not turned into hyperlinks.

## 3. Customize the HTML template

Edit `templates/base.html`. Three placeholders are supported:

- `{{ title }}`: HTML-escaped page title
- `{{ description }}`: HTML-escaped description
- `{{ content }}`: generated page HTML

Place stylesheets, images, fonts and JavaScript files in `static/`. These files are copied to `dist/static/` byte for byte, including nested folders.

## 4. Add pages

Markdown filenames become clean URLs:

| Markdown source | Generated file | URL |
| --- | --- | --- |
| `content/index.md` | `dist/index.html` | `/` |
| `content/about.md` | `dist/about/index.html` | `/about/` |
| `content/blog/index.md` | `dist/blog/index.html` | `/blog/` |
| `content/blog/first-post.md` | `dist/blog/first-post/index.html` | `/blog/first-post/` |

## 5. Generate the website

From the site directory:

```bash
mojara site build
```

The completed website is in `dist/`. Deploy that directory to an ordinary static file host or web server. Database access and the Mojara HTTP server are not required to serve the generated pages.

Re-running the command updates generated pages and assets. It deliberately does not delete files already in `dist/`; remove stale pages there yourself when removing content files. The builder writes only inside its own marked `dist/` directory and refuses to overwrite an unrelated directory or follow symlinks in its inputs.

## Static and dynamic projects

| Capability | Static website | Dynamic Mojara application |
| --- | --- | --- |
| Entry command | `mojara site new` | `mojara new` |
| Build command | `mojara site build` | `mojara build` |
| Output | `dist/` | `build/app` |
| Requires a server process | No | Yes |
| Routes, database, authentication, uploads | No | Yes |

For web applications with user accounts, dynamic forms, APIs or databases, use [Mojara's ordinary application workflow](QUICKSTART-API.md). A static website can still link to a separately deployed Mojara API.
