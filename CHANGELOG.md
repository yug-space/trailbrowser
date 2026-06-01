# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Reopen Closed Tab (`Cmd+Shift+T`) restores recently closed normal tabs and
  keeps private tabs out of the persisted reopen stack.
- Sidebar tab context menu and Navigate menu actions for reload, duplicate,
  close other tabs, and close tabs to the right.
- Sidebar tab drag reordering plus move up/down menu actions.
- Pinned tabs with session restore and reopen-closed-tab preservation.
- Bookmarks bar now appears automatically when saved bookmarks exist until the
  user explicitly chooses a visibility preference.
- Settings now exposes a tab performance toggle: keep pages loaded by default
  for smooth switching, or enable memory saver to sleep older background tabs.
- AI form autofill appears on pages with safe fillable fields and uses the
  selected Codex/Claude CLI after a user confirmation prompt.
- View menu now exposes native macOS full-screen mode with `Ctrl+Cmd+F`.

### Changed
- Refreshed the native chrome and bundled pages with sleek light and dark
  themes, pale/deep surfaces, softer shadows, and a coral accent.
- Chrome cookie import now detects partitioned cookies that WebKit cannot
  preserve through its public cookie API and reports them separately from stale
  or unreadable cookies.
- Bookmark bar items now start at the leading edge, and the bar collapses when
  there are no saved bookmarks.
- Codex assistant calls now floor reasoning effort at `low`, avoiding Codex
  v0.135.0 failures caused by `minimal` effort with enabled tools.

## [1.0.0] - 2026-05-31

First public release.

### Added
- Native macOS browser shell on system WebKit (`WKWebView`) — Objective-C +
  AppKit, no Electron or bundled Chromium.
- Flat near-black + warm-orange themed UI: centered address pill, sidebar tabs
  with live count, per-tab status, hover-to-close, and smooth control animations.
- Native internal pages over the `trailbrowser://` scheme: home (Google ⇄ AI
  search), settings, and first-run onboarding.
- AI page assistant (Ask / Edit) and AI-generated search pages via the `codex`
  or `claude` CLI, configurable engine, model, and speed in Settings.
- Chrome cookie import (Keychain-gated, local-only).
- Efficient tab management: shared WebKit data store, a bounded live-tab pool
  with background preloading, tab sleeping, and a system memory-pressure
  responder — roughly half the resident memory of Chrome on a 12-tab benchmark
  with all tabs preloaded, and less once background tabs sleep
  (`tools/bench-memory.sh`).
- Read-only history MCP server (`mcp-history-server`).
