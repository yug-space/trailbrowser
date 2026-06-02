# Browser Feature Matrix

TrailBrowser is a native macOS browser shell around `WKWebView`, not a Chromium
fork. This matrix tracks the everyday browser surface we intentionally support,
using Chromium command/controller areas as a reference point without copying its
architecture.

Status keys:

- `Done` means implemented and build-verified in this repo.
- `Partial` means usable but still missing expected polish or edge cases.
- `Planned` means not implemented yet.
- `N/A` means WebKit or project scope makes it intentionally different.

| Area | Status | Current implementation | Main files |
|------|--------|------------------------|------------|
| Navigation | Done | Address/search bar, back/forward/reload/home, command-click background tabs, popup tabs. | `BrowserAppDelegate.m` |
| Tabs | Done | Sidebar tabs, pin/unpin, drag reordering, close/new, favicon/title, live tab switching, default keep-loaded mode with memory-saver fallback, `Cmd+Opt+Tab` switcher, `Cmd+Shift+T` closed-tab restore, and tab context actions for reload, duplicate, move, close others, and close tabs to the right. | `BrowserAppDelegate.m`, `BrowserTabViews.*`, `Settings.*` |
| Private browsing | Partial | Private tabs use `WKWebsiteDataStore nonPersistentDataStore` and are excluded from history/session restore. Separate private windows and policy controls are not implemented. | `BrowserTab.h`, `BrowserAppDelegate.m` |
| Session restore | Done | Persists normal tabs, pinned tab state, recently closed normal tabs, active index, sidebar state, and window frame under Application Support. | `BrowserAppDelegate.m` |
| History | Done | Local redacted `history.jsonl`, Settings browser with automatic topic clusters, optional cached AI clustering, clear action, read-only MCP server. | `BrowserAppDelegate.m`, `Settings.*`, `mcp-history-server/` |
| Search and URL autocomplete | Done | Suggestions from typed searches plus browsing history. | `BrowserAppDelegate.m` |
| Bookmarks | Partial | Star current page, smart native bookmarks bar that appears only when bookmarks exist (`Cmd+Shift+B` still records explicit preference for saved bookmarks), toolbar bookmarks popover, Settings search/edit/remove/reorder, and Netscape HTML import/export. Folder hierarchy is not implemented. | `BrowserAppDelegate.m`, `Settings.*` |
| Downloads | Partial | WebKit download handling, unique filenames, active download popover with progress/cancel, resume data for failed/canceled downloads, local downloads log, Settings list, reveal/clear. Full background download scheduling and rich Finder-style queue controls are not implemented. | `BrowserAppDelegate.m`, `Settings.*` |
| Page find | Done | `Cmd+F`, next/previous, WebKit find on supported macOS with fallback JS find. | `BrowserAppDelegate.m` |
| Zoom | Done | Page zoom in/out/reset via View menu. | `BrowserAppDelegate.m` |
| Page info/security | Partial | Address icon shows HTTPS/HTTP/file/internal state, macOS trust summary, and saved camera/microphone permission state where WebKit exposes it. | `BrowserAppDelegate.m` |
| Print/export | Done | Open file, print, save page as PDF, view source. | `BrowserAppDelegate.m`, `Makefile` |
| Website data/privacy | Partial | Clear WebKit cookies/cache/storage, clear local history/download logs, and manage persisted camera/microphone permission decisions by origin. Per-site data browsing is not implemented. | `BrowserAppDelegate.m`, `Settings.*`, `Info.plist` |
| Cookie import | Done | User-initiated Chrome cookie import through Keychain-gated Chrome Safe Storage, with explicit reporting for partitioned Chrome cookies WebKit cannot preserve. | `ChromeCookieImporter.*` |
| Passkeys | Partial | Requests macOS browser passkey access through AuthenticationServices when the app is signed with Apple's browser public-key-credential entitlement. WebKit handles WebAuthentication prompts once macOS authorizes the browser. Local builds stay unsigned by default because the entitlement is restricted. | `BrowserAppDelegate.m`, `TrailBrowser.entitlements`, `Makefile`, `Settings.*` |
| Assistant | Partial | Ask/Edit, AI-generated pages, and user-confirmed AI form autofill through `codex` or `claude` CLI. Codex runs at `low` effort or higher for v0.135.0 tool compatibility. Autofill opens known embedded form providers directly before filling, and excludes existing field values, passwords, payment fields, hidden fields, OTPs, and file inputs. | `BrowserAppDelegate.m`, `Settings.*` |
| Passwords/autofill | Planned | No custom password store. WebKit/system behavior only. | N/A |
| Extensions | Planned | No WebExtension host yet. | N/A |
| Sync | N/A | No telemetry or cloud sync. Chrome cookie import is local-only and user-triggered. | `ChromeCookieImporter.*` |
| DevTools | Partial | `WKWebView.inspectable` enabled on supported macOS for Safari/WebKit inspection. No in-app DevTools frontend. | `BrowserAppDelegate.m` |

## Maintenance Rules

- Keep browser state explicit in model objects. Example: private browsing lives
  on `BrowserTab`, not hidden in UI state.
- Persist only what should survive restart. Private tabs, private history, and
  temporary WebKit data must not be written to TrailBrowser state files.
- Recently closed tab restore follows the same rule: save normal tabs only and
  never add private tabs to the reopen stack.
- Add new storage paths to `writeBrowserStateRunning:` so contributors and MCP
  tooling can discover them.
- Keep user-sensitive actions explicit and user-triggered: cookie import,
  website-data clearing, downloads reveal, filesystem open/save, and assistant
  process execution.
- Prefer WebKit/AppKit APIs over ad hoc behavior. When a Chromium feature maps
  poorly to WebKit, document the difference here instead of faking parity.

## High-Value Remaining Work

- More per-site controls where WebKit exposes native hooks: notifications,
  geolocation, popups, autoplay, and per-origin website data inspection.
- Bookmark folders.
- Richer download queue controls, including sorting, retry policy, and completed
  file cleanup.
- Password/autofill posture: decide whether TrailBrowser relies entirely on
  system/WebKit behavior or adds explicit local management.
- WebExtension host investigation.
