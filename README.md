# TrailBrowser

A small, fast, native **macOS** browser shell built on Apple's system WebKit
engine — no Electron, no bundled Chromium.

- Objective-C + AppKit for the native window, toolbar, and sidebar
- `WKWebView` (system WebKit) for real website rendering

The app is the native UI *around* WebKit; it is not a rendering engine.

## Features

- A flat, near-black UI with a warm-orange accent and smooth control animations
- A clean one-line top bar: highlighted sidebar toggle, centered address/search
  pill, reload, **Ask**, and a settings gear
- A native **home page** with a Google ⇄ AI search toggle and quick links
- **First-run onboarding** that offers to sync cookies from Chrome
- A **settings page** (`Cmd+,`) for syncing Chrome cookies and more
- Sidebar tabs: a live count, per-tab status (active accent bar, dimmed when
  slept), and hover-to-close
- **Efficient memory & process use:** a single shared web-content process pool
  and one shared cookie/data store across tabs; inactive tabs release their
  `WKWebView` (keeping only URL/title/favicon), so dozens of open tabs cost
  roughly one live WebKit page
- A built-in **page assistant** (Ask / Edit) powered by the `codex` CLI
- A 2px accent loading bar and a status dot
- Keyboard shortcuts: `Cmd+L`, `Cmd+R`, `Cmd+T`, `Cmd+W`, `Cmd+B`, `Cmd+,`,
  `Cmd+[`, `Cmd+]`
- A read-only **history MCP server** for querying your browsing history

## Repository layout

| Path | Purpose |
|------|---------|
| `mac-browser/main.m` | `NSApplication` entry point |
| `mac-browser/BrowserAppDelegate.{h,m}` | App controller: window, tabs, navigation, assistant, history, cookies |
| `mac-browser/BrowserTab.{h,m}` | Tab model (sleeps its `WKWebView` when inactive) |
| `mac-browser/BrowserTabViews.{h,m}` | Sidebar tab row + cell views |
| `mac-browser/TBControls.{h,m}` | Themed controls (flat buttons, pill button, progress bar, field) |
| `mac-browser/TBTheme.{h,m}` | Color palette + layer animation helper |
| `mac-browser/ChromeCookieImporter.{h,m}` | Imports cookies from a local Chrome profile |
| `mac-browser/home/` | Bundled internal pages: `Home.*`, `Settings.*`, `Onboarding.*` |
| `mac-browser/Info.plist` | macOS app bundle metadata |
| `mcp-history-server/server.mjs` | Read-only MCP server for TrailBrowser history |
| `Makefile` | Builds the app and runs the MCP server |

See [AGENTS.md](AGENTS.md) for architecture and conventions, and
[CONTRIBUTING.md](CONTRIBUTING.md) for how to build and test.

## Build & run

Requires the Xcode Command Line Tools (`xcode-select --install`).

```sh
make            # builds TrailBrowser.app
make run-browser
make clean
```

Type in the top address bar and press Return: full URLs and domain-like inputs
open as websites, while phrases become Google searches. The home page's Google ⇄
AI toggle chooses between a normal search and Codex Deep Search.

## Internal pages

TrailBrowser serves a few native pages via the `trailbrowser://` scheme:

- `trailbrowser://home` — search and quick links
- `trailbrowser://settings` — sync Chrome cookies and more
- `trailbrowser://welcome` — first-run onboarding

## Import Cookies from Chrome

Settings → **Sync Chrome Cookies** (or TrailBrowser → Import Cookies from Chrome…)
copies cookies from a local Google Chrome profile into TrailBrowser's shared
WebKit cookie store, so sites you were signed in to in Chrome stay signed in
here. It also reduces "unusual traffic" checks from sites like Google that
distrust signed-out, cookieless sessions.

How it works:

1. Lists the Chrome profiles under
   `~/Library/Application Support/Google/Chrome` (and their account emails). If
   you have more than one profile, you choose which to import.
2. Reads the AES key from the `Chrome Safe Storage` Keychain item. macOS shows a
   consent prompt the first time — this is the gate that keeps the import
   user-authorized.
3. Copies the profile's `Cookies` SQLite database to a temp file, decrypts each
   `v10`/`v11` value (AES-128-CBC, PBKDF2-derived key), and writes the cookies
   into `WKHTTPCookieStore`.

It only ever touches the current user's own Chrome data on this machine, never
sends cookies anywhere, and deletes the temporary database copy when done.

## History MCP Server

TrailBrowser writes its own browsing history to:

```text
~/Library/Application Support/TrailBrowser/history.jsonl
```

The MCP server reads that file and exposes read-only tools:

- `browser_status`
- `history_recent`
- `history_search`
- `history_by_domain`
- `history_top_domains`

```sh
make mcp-install     # install dependencies
make run-history-mcp # run the server over stdio
```

The MCP server is strictly read-only over `history.jsonl`: it does **not** read
Chrome profiles, decrypt Keychain data, read cookies, or expose session cookies.
URLs are redacted for sensitive query keys before being written to history.

## How it works

`main()` starts an `NSApplication` and installs `BrowserAppDelegate`. On launch
the delegate builds the menu and window, then opens the onboarding page on first
run or the home page afterwards.

The UI is native AppKit, themed near-black with a warm-orange accent
(`TBTheme`):

- `NSWindow` is the main app window; the toolbar and sidebar are flat
  layer-backed `NSView`s.
- `TBFlatButton` / `TBPillButton` are the navigation and action buttons.
- A `TBFieldContainer` wraps the address `NSTextField` as a focusable pill.
- `TBProgressBar` shows page load progress as a 2px accent line.
- `NSTableView` with `BrowserTabViews` renders the sidebar tab list.

The web page itself is rendered by WebKit: `WKWebView` displays the site;
`loadRequest:`, `goBack`, `goForward`, and `reload` drive navigation; and
key-value observing tracks `estimatedProgress`, `URL`, `canGoBack`, and
`canGoForward` so the UI stays in sync. All web views share one
`WKProcessPool` and the default `WKWebsiteDataStore`, and inactive tabs are
slept to keep memory close to a single live WebKit page.

This is a native browser shell, not a custom browser engine. WebKit handles
parsing HTML, applying CSS, running JavaScript, loading images, and navigation.

## License

[MIT](LICENSE)
