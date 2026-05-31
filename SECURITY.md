# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

Email **theta.computer01@gmail.com** with:

- a description of the issue and its impact,
- steps to reproduce (a proof of concept if possible), and
- the affected version / commit.

You'll get an acknowledgement, and a fix or mitigation plan once the report is
triaged. Please give a reasonable window to address the issue before any public
disclosure.

## Security posture

TrailBrowser is a local-only, defensive tool. It has **no telemetry** and makes
no network requests of its own beyond loading the pages you navigate to.

Sensitive surfaces, and how they're handled:

- **Chrome cookie import.** Importing reads the `Chrome Safe Storage` key from
  your macOS Keychain (which triggers an OS consent prompt the first time),
  copies the profile's `Cookies` SQLite database to a temp file, decrypts the
  `v10`/`v11` values, writes them into WebKit's cookie store, and deletes the
  temp copy. It is always **user-initiated**, only ever touches the current
  user's own local Chrome data, and never transmits anything off-device.
- **AI page assistant.** Ask / Edit / AI-search spawn a local CLI (`codex` or
  `claude`) only when you invoke them. Codex runs in a **read-only sandbox**.
  Your prompt and a snapshot of the current page are passed to that CLI, which
  may use it per its own policies — treat it like sending text to that tool.
- **AI-generated content executes in the page.** Edit mode and AI-generated
  pages run model-produced HTML/JS in the WebKit page context. Generated pages
  are self-contained (the app strips `<script>`/`<style>` wrappers and provides
  the template), but this is a trust boundary worth knowing about.
- **History.** Browsing history is stored locally at
  `~/Library/Application Support/TrailBrowser/history.jsonl`. URLs are redacted
  for sensitive query keys before being written. The history MCP server is
  strictly **read-only** over that file and never reads Chrome profiles,
  Keychain data, or cookies.

No secrets or credentials are stored in this repository.
