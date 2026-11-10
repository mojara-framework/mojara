#!/usr/bin/env python3
"""Sync public installation documents with the official GitHub repository."""
from html import escape, unescape
from pathlib import Path
import json
import re
import urllib.request

import markdown

ROOT = Path("/srv/mojara-website-app")
DOCS = ROOT / "site/docs"
CONTENT = ROOT / "content"
SITE = ROOT / "site"
GITHUB = "https://github.com/mojara-framework/mojara"
RAW = "https://raw.githubusercontent.com/mojara-framework/mojara/main/"

def fetch(path):
    req = urllib.request.Request(RAW + path, headers={"User-Agent": "MojaraDocs/1.2.7"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read().decode("utf-8")

readme = fetch("README.md")
assert "## Installation\n" in readme and "\n## Features\n" in readme
install = "# Install Mojara\n\n" + readme.split("## Installation\n", 1)[1].split("\n## Features\n", 1)[0].strip() + "\n"
docker = fetch("docs/DOCKER.md")
source = fetch("docs/BUILD-FROM-SOURCE.md")
assert "mojara==1.2.7" in install
assert "ghcr.io/mojara-framework/mojara:1.2.7" in install

link_map = {
    "docs/DOCKER.md": "/docs/docker.html",
    "docs/BUILD-FROM-SOURCE.md": "/docs/source-build.html",
    "docs/INSTALL-MACOS.md": "/docs/install.html",
    "docs/WINDOWS.md": "/docs/install.html",
    "docs/API-REFERENCE.md": "/docs/api-reference.html",
    "BUILD-FROM-SOURCE.md": "/docs/source-build.html",
    "DOCKER.md": "/docs/docker.html",
    "INSTALL-MACOS.md": "/docs/install.html",
    "INSTALL-LINUX.md": "/docs/install.html",
    "RELEASE-CHECKLIST.md": GITHUB + "/blob/main/docs/RELEASE-CHECKLIST.md",
    "../.github/workflows/publish-docker.yml": GITHUB + "/blob/main/.github/workflows/publish-docker.yml",
    "../scripts/ci/": GITHUB + "/tree/main/scripts/ci/",
}
def adapt(text):
    for old, new in sorted(link_map.items(), key=lambda entry: len(entry[0]), reverse=True):
        text = text.replace("](" + old + ")", "](" + new + ")")
    return text

quickstart = (CONTENT / "quickstart.md").read_text(encoding="utf-8")
quickstart = quickstart.replace("the **tested Mojara v1.2.0 CLI** and its", "the Mojara CLI and its")
quickstart = quickstart.replace("pixi run mojara", "mojara")
quickstart = quickstart.replace("mojara start\n", "mojara start --local\n")

releases = (
    "# Mojara 1.2.7\n\n"
    "Mojara is available natively for Linux x86-64, Linux ARM64 and macOS Apple Silicon, "
    "and through WSL2 on Windows or Docker and Lima on Intel Macs.\n\n"
    "## Install\n\n"
    "Choose [Installation](install.html), [Docker](docker.html), "
    "or [Build Mojara from source](source-build.html).\n\n"
    "## Features\n\n"
    "- Native Mojo CLI, HTTP routing, APIs, templates, forms, file uploads and WebSockets.\n"
    "- Authentication, sessions, PostgreSQL, MySQL, SQLite and connection pooling.\n"
    "- Official Docker images for Linux AMD64 and ARM64.\n\n"
    "[Official release and checksums](" + GITHUB + "/releases/tag/v1.2.7).\n"
)
pages = {
    "install": ("Install Mojara", "Install Mojara 1.2.7 on every supported platform, Docker, and from source", adapt(install)),
    "docker": ("Mojara with Docker", "Official Mojara AMD64 and ARM64 Docker images and Docker Compose", adapt(docker)),
    "source-build": ("Build Mojara from GitHub", "Compile the native Mojara Mojo framework, CLI and C bridges from source", adapt(source)),
    "quickstart": ("Your first Mojara website", "Generate and build your first native Mojara application", quickstart),
    "releases": ("Mojara releases", "Mojara 1.2.7 official release and installation", releases),
}

template = (DOCS / "install.html").read_text(encoding="utf-8")
article_re = re.compile(r'<article class="article">.*?</article>', flags=re.DOTALL)
assert article_re.search(template)
for slug, (title, description, md) in pages.items():
    (CONTENT / (slug + ".md")).write_text(md, encoding="utf-8")
    fragment = markdown.markdown(md, extensions=["fenced_code", "tables", "toc"], output_format="html5")
    page = article_re.sub(lambda _: '<article class="article">' + fragment + '</article>', template, count=1)
    page = re.sub(r"<title>.*?</title>", "<title>" + escape(title) + " | Mojara Documentation</title>", page, count=1)
    page = re.sub(r'<meta name="description" content="[^"]*">',
                  '<meta name="description" content="' + escape(description, quote=True) + '">', page, count=1)
    page = page.replace('<a class="current" href="/docs/install.html">Installation</a>',
                        '<a href="/docs/install.html">Installation</a>', 1)
    if slug == "install":
        page = page.replace('<a href="/docs/install.html">Installation</a>',
                            '<a class="current" href="/docs/install.html">Installation</a>', 1)
    (DOCS / (slug + ".html")).write_text(page, encoding="utf-8")

# Add public installation guides to the sidebar on all chapters.
nav_links = '<a href="/docs/docker.html">Docker</a><a href="/docs/source-build.html">Build from source</a>'
nav_find = re.compile(r'(<a(?: class="current")? href="/docs/install.html">Installation</a>)')
for file in DOCS.glob("*.html"):
    page = file.read_text(encoding="utf-8")
    if nav_links not in page and 'href="/docs/install.html"' in page:
        page, count = nav_find.subn(lambda match: match.group(1) + nav_links, page, count=1)
        assert count == 1, "No docs sidebar in " + file.name
    if file.name == "docker.html":
        page = page.replace('<a href="/docs/docker.html">Docker</a>', '<a class="current" href="/docs/docker.html">Docker</a>', 1)
    if file.name == "source-build.html":
        page = page.replace('<a href="/docs/source-build.html">Build from source</a>',
                            '<a class="current" href="/docs/source-build.html">Build from source</a>', 1)
    # Align references to the current released CLI/package.
    page = page.replace("mojara==1.2.6", "mojara==1.2.7")
    page = page.replace("Mojara 1.2.6", "Mojara 1.2.7")
    page = page.replace("v1.2.6", "v1.2.7")
    file.write_text(page, encoding="utf-8")

index = DOCS / "index.html"
index_html = index.read_text(encoding="utf-8")
if 'href="docker.html"' not in index_html:
    index_html = index_html.replace(
        "</article>", '<p>Get started with <a href="install.html">installation</a>, '
        '<a href="docker.html">Docker</a>, or '
        '<a href="source-build.html">building Mojara from GitHub source</a>.</p></article>', 1)
    index.write_text(index_html, encoding="utf-8")
index_md = CONTENT / "index.md"
index_src = index_md.read_text(encoding="utf-8")
if "[Docker](docker.html)" not in index_src:
    index_src = index_src.replace("[Installation](install.html)",
        "[Installation](install.html), [Docker](docker.html), and [Build from source](source-build.html)", 1)
    index_md.write_text(index_src, encoding="utf-8")

# Index all five changed chapters for the live search UI.
search_file = SITE / "search.json"
records = json.loads(search_file.read_text(encoding="utf-8"))
records = [entry for entry in records if entry.get("slug") not in pages]
for slug, (title, _, _) in pages.items():
    page = (DOCS / (slug + ".html")).read_text(encoding="utf-8")
    m = re.search(r'<article class="article">.*?</article>', page, flags=re.DOTALL)
    body = unescape(re.sub(r"<[^>]+>", " ", m.group(0) if m else page))
    body = re.sub(r"\s+", " ", body).strip()
    records.append({"slug": slug, "title": title, "text": body[:6500]})
search_file.write_text(json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

sitemap_file = SITE / "sitemap.xml"
xml = sitemap_file.read_text(encoding="utf-8")
for slug in ("docker", "source-build"):
    url = "https://mojara.kasua.ng/docs/" + slug + ".html"
    if url not in xml:
        xml = xml.replace("</urlset>", "<url><loc>" + url + "</loc></url></urlset>")
sitemap_file.write_text(xml, encoding="utf-8")

# Keep the static fallback files aligned with the Mojo website's content.
fallback = Path("/var/www/mojara-site")
for page in DOCS.glob("*.html"):
    (fallback / "docs" / page.name).write_text(page.read_text(encoding="utf-8"), encoding="utf-8")
for name in ("search.json", "sitemap.xml"):
    (fallback / name).write_bytes((SITE / name).read_bytes())
print("Updated 5 hosted guides with current Mojara 1.2.7 information")
print("Updated all documentation sidebars, search and sitemap")
print("Synchronized live content and static fallback; search entries:", len(records))

