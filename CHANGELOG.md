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
