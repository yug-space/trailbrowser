# Contributing to TrailBrowser

Thanks for your interest in TrailBrowser — a small native macOS browser shell
built on the system WebKit engine (AppKit + `WKWebView`).

## Getting set up

Requires macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`).
The AI page assistant additionally needs the `codex` or `claude` CLI on `PATH`
(optional; choose the engine in Settings).

```sh
make            # builds TrailBrowser.app
make run-browser
```

History MCP server:

```sh
make mcp-install
make run-history-mcp
```

Public website:

```sh
cd web
npm install
npm run dev
npm run build
```

## Project layout

See [AGENTS.md](AGENTS.md) for a full file-by-file map and architecture notes,
and [docs/BROWSER_FEATURES.md](docs/BROWSER_FEATURES.md) for the maintained
browser feature matrix.
In short:

- `mac-browser/` — the macOS app, split into focused files:
  `main.m`, `BrowserAppDelegate.{h,m}` (controller), `BrowserTab.{h,m}` (model),
  `BrowserTabViews.{h,m}` (sidebar list), `TBControls.{h,m}` + `TBTheme.{h,m}`
  (themed controls + palette), `ChromeCookieImporter.{h,m}`, and bundled pages
  under `home/`.
- `mcp-history-server/` — the read-only history MCP server.
- `web/` — the Next.js App Router public website used for Vercel deployment.

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
- **Website:** keep the `web/` site clean, white themed, and feature-focused.
  Do not commit `.next/`, `node_modules/`, screenshots, or generated output.

## Testing your change

There is no automated test suite. Build the app and exercise the affected flow
end to end, for example:

- Navigation: type a URL and a search phrase; back/forward/reload; the 2px
  progress line and status pill.
- Tabs: open (`Cmd+T` or the `+`), switch, hover-to-close, tab sleeping.
- Home page: Google vs AI search toggle, quick links.
- Settings: open via the sidebar or `Cmd+,`; Sync Chrome Cookies.
- Browser basics: bookmarks bar/popover, Settings management/reordering, bookmark
  import/export, downloads popover and reveal, private tabs (`Cmd+Shift+N`),
  site permissions, find, zoom, page info, print/PDF.
- Page assistant: Ask and Edit (requires the `codex` or `claude` CLI on `PATH`).
- Website: from `web/`, run `npm run lint`, `npm run build`, and check desktop
  plus mobile layouts before opening a PR.

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
redaction in `BrowserAppDelegate.m` and `mcp-history-server/server.mjs`).

See [SECURITY.md](SECURITY.md) for the security posture and how to report
vulnerabilities.

## License

By contributing, you agree your contributions are licensed under the project's
[MIT License](LICENSE).
