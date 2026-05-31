# TrailBrowser explainer video

A self-contained [Remotion](https://www.remotion.dev/) explainer for TrailBrowser.
1920×1080 · 30fps · ~11s, fast-cut with animated slide/wipe/fade transitions.
Theme mirrors `TBTheme` (near-black + `#f76b1c`).

## Setup

```sh
cd video
npm install
```

## Preview / render

```sh
npm run dev      # open Remotion Studio for live preview
npm run render   # → out/trailbrowser.mp4
npm run still    # → out/frame.png (single frame, override with --frame=N)
```

Or directly:

```sh
npx remotion render src/index.tsx TrailBrowserExplainer out/trailbrowser.mp4
```

## Scenes

1. **Intro** — animated logo lockup: the brand mark's trail draws itself,
   waypoints pop, the summit ignites, then the wordmark + tagline slide in
2. **Memory** — ~1/10th of Chrome's resident memory (animated bars)
3. **AI** — Ask / Edit / Search via Codex or Claude on a redacted snapshot
4. **Memory MCP** — read-only history MCP server + its five tools
5. **Outro** — `make && open TrailBrowser.app`

Everything lives in `src/index.tsx`. The official brand SVGs (mark, app-icon
tile, wordmark lockup) are in `assets/`; the intro/outro re-create the mark as
an animated inline `<TrailMark>` so the trail can draw itself.
