# AGENTS.md

Guidance for AI coding agents (and humans) working in the TrailBrowser repo.

## What this project is

TrailBrowser is a small **native macOS** browser shell built on the system
WebKit engine — no Electron, no bundled Chromium.

- **mac-browser** — Objective-C + AppKit + WebKit (`WKWebView`): sidebar tabs,
  page assistant, cookie import, settings, onboarding.
- **mcp-history-server** — a read-only Node MCP server exposing browsing history.

The app is the native UI *around* WebKit; it is not a rendering engine. (There
is intentionally no Linux/GTK build — the repo is macOS + MCP only.)

## Repository layout

```
mac-browser/
  main.m                     # NSApplication entry point
  BrowserAppDelegate.{h,m}   # App controller: window, tabs, navigation,
                             #   assistant, history/state, cookie import
  BrowserTab.{h,m}           # Tab model (sleeps its WKWebView when inactive)
  BrowserTabViews.{h,m}      # Sidebar row + cell views (selection, hover, close)
  TBControls.{h,m}           # Themed controls: TBFlatButton, TBPillButton,
                             #   TBProgressBar, TBFieldContainer
  TBTheme.{h,m}              # Color palette + layer animation helper
  ChromeCookieImporter.{h,m} # Reads cookies from a local Chrome profile
  Info.plist                 # App bundle metadata
  home/                      # Bundled internal pages (Home + Settings)
    Home.{html,css,js}       # trailbrowser://home  (search / quick links)
    Settings.{html,css,js}   # trailbrowser://settings (sync cookies, etc.)
linux-browser/trailbrowser.c # GTK/WebKitGTK browser
mcp-history-server/server.mjs# Read-only history MCP server
Makefile                     # Auto-selects macOS or Linux target
```

## Build & run

```sh
make            # builds the native target for the current OS
make run-browser
make clean
```

macOS produces `TrailBrowser.app`; Linux produces `./trailbrowser`. On Linux,
install deps first (see README). The macOS app links `Cocoa`, `WebKit`,
`Security`, `QuartzCore`, and `sqlite3` — **add new frameworks to
`APP_FRAMEWORKS` in the Makefile**, not just an `#import`.

There is no test suite; verify by building and running the app and exercising
the changed flow (navigation, tabs, assistant, settings, cookie import).

## Conventions

- **Theme:** never hard-code colors in controls/views. Use the `TB*()` helpers
  in `TBTheme.h` (near-black surfaces, warm orange `TBAccent()`). Section
  headers are uppercase + tracked + `TBMuted()`.
- **New reusable control?** Put it in `TBControls.{h,m}`. Hover/press/focus
  states animate via `TBAnimateBackground(...)` or `CABasicAnimation` — keep
  state changes smooth, not instant.
- **New bundled page?** Add `Foo.{html,css,js}` under `mac-browser/home/`, list
  the files in `APP_HOME_RESOURCES` in the Makefile, and route it through the
  `trailbrowser://` scheme (see below).
- Match the surrounding style: 4-space indent, ARC (`-fobjc-arc`), `NS_ASSUME_NONNULL`
  in headers (mark genuinely-nullable properties `nullable`).
- Keep the controller's WebKit/navigation/history/assistant **behavior** stable
  when doing UI work — those flows already work.

## Internal URL scheme

`-[BrowserAppDelegate handleInternalURL:]` intercepts `trailbrowser://` links:

| URL | Effect |
|-----|--------|
| `trailbrowser://home` | Load the native home page |
| `trailbrowser://settings` | Load the native settings page |
| `trailbrowser://open?input=…` | Open a URL / run a search |
| `trailbrowser://deep-search?q=…` | Run Codex Deep Search |
| `trailbrowser://sync-cookies` | Import cookies from Chrome |
| `trailbrowser://assistant` | Open the page assistant bar |

Bundled JS (e.g. `Home.js`, `Settings.js`) talks to the native app by setting
`window.location.href` to one of these.

## Gotchas

- **The page assistant shells out to the `codex` CLI** (`runCodexWithPrompt:`),
  searching `~/.nvm/.../bin`, `/opt/homebrew/bin`, `/usr/local/bin`. It runs
  read-only/sandboxed. Without `codex` installed the assistant returns an error.
- **History/state** are written to `~/Library/Application Support/TrailBrowser/`
  (`history.jsonl`, `state.json`); URLs are redacted for sensitive query keys.
  The MCP server reads these.
- **Tab sleeping:** inactive tabs release their `WKWebView` (`webView == nil`);
  reselecting recreates it. Don't assume `tab.webView` is non-nil.
- **Cookie import** prompts for Keychain access ("Chrome Safe Storage"); it is
  always user-initiated.
- Google may show an "unusual traffic" reCAPTCHA for signed-out, cookieless
  sessions — importing Chrome cookies resolves it.

## Security posture

Defensive/local-only. No telemetry. Cookie import and the assistant are
user-initiated. When adding network or process-spawning code, keep it explicit
and user-triggered, and redact secrets in anything persisted to disk.
