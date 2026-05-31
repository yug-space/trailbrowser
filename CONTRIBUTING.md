# Contributing to TrailBrowser

Thanks for your interest in TrailBrowser — a small native browser shell built on
the system WebKit engine (AppKit/WebKit on macOS, GTK/WebKitGTK on Linux).

## Getting set up

### macOS
Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
make            # builds TrailBrowser.app
make run-browser
```

### Linux (Debian/Ubuntu)
```sh
sudo apt update
sudo apt install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
make            # builds ./trailbrowser
make run-browser
```

### History MCP server
```sh
make mcp-install
make run-history-mcp
```

## Project layout

See [AGENTS.md](AGENTS.md) for a full file-by-file map and architecture notes.
In short:

- `mac-browser/` — the macOS app, split into focused files:
  `main.m`, `BrowserAppDelegate.{h,m}` (controller), `BrowserTab.{h,m}` (model),
  `BrowserTabViews.{h,m}` (sidebar list), `TBControls.{h,m}` + `TBTheme.{h,m}`
  (themed controls + palette), `ChromeCookieImporter.{h,m}`, and bundled pages
  under `home/`.
- `linux-browser/trailbrowser.c` — the GTK app.
- `mcp-history-server/` — the read-only history MCP server.

## Coding style

- **Objective-C:** 4-space indentation, ARC (`-fobjc-arc`), `NS_ASSUME_NONNULL`
  in headers (mark genuinely-nullable properties `nullable`). Keep methods small
  and grouped with `#pragma mark`.
- **Colors:** use the `TB*()` palette helpers in `TBTheme.h` — do not hard-code
  hex values in controls or views.
- **New reusable control:** add it to `TBControls.{h,m}`; animate hover/press/
  focus state (via `TBAnimateBackground` or `CABasicAnimation`), never snap.
- **New bundled page:** add `Foo.{html,css,js}` under `mac-browser/home/`, list
  the files in `APP_HOME_RESOURCES` in the `Makefile`, and route via the
  `trailbrowser://` scheme in `-[BrowserAppDelegate handleInternalURL:]`.
- **New framework:** add it to `APP_FRAMEWORKS` in the `Makefile` (an `#import`
  alone will not link).
- **CSS/JS:** 2-space indentation; keep the near-black + orange theme variables
  at the top of each stylesheet in sync with `TBTheme`.

## Testing your change

There is no automated test suite. Build the app and exercise the affected flow
end to end, for example:

- Navigation: type a URL and a search phrase; back/forward/reload; the 2px
  progress line and status pill.
- Tabs: open (`Cmd+T` or the `+`), switch, hover-to-close, tab sleeping.
- Home page: Google vs AI search toggle, quick links.
- Settings: open via the sidebar or `Cmd+,`; Sync Chrome Cookies.
- Page assistant: Ask and Edit (requires the `codex` CLI on `PATH`).

Note what you tested in your PR description.

## Commit & PR guidelines

- Use clear, present-tense commit messages ("Add …", "Fix …").
- Keep PRs focused; describe what changed, why, and how you verified it.
- Don't commit build output (`TrailBrowser.app`, `trailbrowser`) — these are
  git-ignored.

## Scope & security

TrailBrowser is defensive and local-only: no telemetry, and the cookie import
and assistant are always user-initiated. When adding code that touches the
network, the filesystem, or spawns processes, keep it explicit and
user-triggered, and redact secrets in anything written to disk (see the URL
redaction in `BrowserAppDelegate.m` and `trailbrowser.c`).

## License

By contributing, you agree your contributions are licensed under the project's
[MIT License](LICENSE).
