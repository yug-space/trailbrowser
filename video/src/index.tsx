// TrailBrowserVideo.tsx — a complete, self-contained Remotion explainer for TrailBrowser.
// Drop this single file into a Remotion project's src/ as your entry, then:
//   npm i @remotion/google-fonts
//   npm run dev      (preview in Remotion Studio)
//   npx remotion render TrailBrowserExplainer out/trailbrowser.mp4
//
// 1920x1080 · 30fps · ~24s. Theme mirrors TrailBrowser's TBTheme (#f76b1c accent).

import React from "react";
import {
  AbsoluteFill,
  Composition,
  Series,
  interpolate,
  registerRoot,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont as loadDisplay } from "@remotion/google-fonts/BricolageGrotesque";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

/* ── theme ──────────────────────────────────────────────────────────────── */
const { fontFamily: displayFont } = loadDisplay();
const { fontFamily: monoFont } = loadMono();

const palette = {
  bg: "#0a0a0b",
  surface: "#141417",
  surfaceHi: "#1c1c21",
  border: "rgba(255,255,255,0.08)",
  accent: "#f76b1c",
  accentSoft: "rgba(247,107,28,0.16)",
  accentGlow: "rgba(247,107,28,0.45)",
  text: "#f6f5f3",
  textDim: "#8b8b92",
  textFaint: "#5a5a61",
  green: "#3ecf8e",
  red: "#ff5f56",
  yellow: "#ffbd2e",
  trafficGreen: "#27c93f",
} as const;

/* ── scene durations (frames @ 30fps) ───────────────────────────────────── */
const FPS = 30;
const D_INTRO = 120;
const D_MEMORY = 150;
const D_AI = 180;
const D_MCP = 165;
const D_OUTRO = 120;
const TOTAL_DURATION = D_INTRO + D_MEMORY + D_AI + D_MCP + D_OUTRO;

/* ── animation + shared helpers ─────────────────────────────────────────── */
const ci = (frame: number, range: [number, number], out: [number, number]) =>
  interpolate(frame, range, out, { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

const FadeUp: React.FC<{ delay?: number; y?: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  delay = 0,
  y = 28,
  children,
  style,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return <div style={{ opacity: s, transform: `translateY(${(1 - s) * y}px)`, ...style }}>{children}</div>;
};

const SceneHeading: React.FC<{ eyebrow: string; title: React.ReactNode }> = ({ eyebrow, title }) => (
  <div style={{ marginBottom: 56 }}>
    <FadeUp>
      <div style={{ fontFamily: monoFont, color: palette.accent, letterSpacing: 4, fontSize: 20, textTransform: "uppercase", marginBottom: 18 }}>
        {eyebrow}
      </div>
    </FadeUp>
    <FadeUp delay={6}>
      <h1 style={{ fontFamily: displayFont, color: palette.text, fontSize: 76, fontWeight: 700, lineHeight: 1.02, letterSpacing: -2, margin: 0, maxWidth: 1100 }}>
        {title}
      </h1>
    </FadeUp>
  </div>
);

const Backdrop: React.FC<{ glowX?: number; glowY?: number }> = ({ glowX = 50, glowY = 28 }) => (
  <AbsoluteFill style={{ backgroundColor: palette.bg }}>
    <AbsoluteFill
      style={{
        backgroundImage: `linear-gradient(${palette.border} 1px, transparent 1px), linear-gradient(90deg, ${palette.border} 1px, transparent 1px)`,
        backgroundSize: "64px 64px",
        opacity: 0.5,
        maskImage: "radial-gradient(circle at center, black, transparent 78%)",
        WebkitMaskImage: "radial-gradient(circle at center, black, transparent 78%)",
      }}
    />
    <AbsoluteFill style={{ background: `radial-gradient(620px circle at ${glowX}% ${glowY}%, ${palette.accentGlow}, transparent 60%)`, opacity: 0.35 }} />
  </AbsoluteFill>
);

const stroke = { stroke: palette.textDim, strokeWidth: 2, fill: "none", strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
const Icon: React.FC<{ name: string; size?: number }> = ({ name, size = 18 }) => {
  const p: Record<string, React.ReactNode> = {
    sidebar: (<><rect x="3" y="4" width="18" height="16" rx="2" {...stroke} /><line x1="9" y1="4" x2="9" y2="20" {...stroke} /></>),
    back: <polyline points="15,5 8,12 15,19" {...stroke} />,
    forward: <polyline points="9,5 16,12 9,19" {...stroke} />,
    reload: (<><path d="M20 11a8 8 0 1 0-2.3 5.7" {...stroke} /><polyline points="20,5 20,11 14,11" {...stroke} /></>),
    plus: (<><line x1="12" y1="6" x2="12" y2="18" {...stroke} /><line x1="6" y1="12" x2="18" y2="12" {...stroke} /></>),
    gear: (<><circle cx="12" cy="12" r="3.2" {...stroke} /><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4" {...stroke} /></>),
  };
  return <svg width={size} height={size} viewBox="0 0 24 24">{p[name]}</svg>;
};

const StatusDot: React.FC<{ color?: string }> = ({ color = palette.green }) => (
  <div style={{ width: 9, height: 9, borderRadius: "50%", background: color, boxShadow: `0 0 10px ${color}` }} />
);

const BrowserChrome: React.FC<{
  url?: string; statusColor?: string; width?: number; height?: number; children?: React.ReactNode; sidebar?: React.ReactNode;
}> = ({ url = "trailbrowser://home", statusColor = palette.green, width = 1180, height = 600, children, sidebar }) => (
  <div style={{ width, height, borderRadius: 18, overflow: "hidden", background: palette.surface, border: `1px solid ${palette.border}`, boxShadow: "0 50px 120px rgba(0,0,0,0.6)", display: "flex", flexDirection: "column" }}>
    <div style={{ height: 52, display: "flex", alignItems: "center", gap: 14, padding: "0 16px", borderBottom: `1px solid ${palette.border}`, background: palette.surface }}>
      <div style={{ display: "flex", gap: 8, marginRight: 4 }}>
        {[palette.red, palette.yellow, palette.trafficGreen].map((c) => (
          <div key={c} style={{ width: 12, height: 12, borderRadius: "50%", background: c }} />
        ))}
      </div>
      <Icon name="sidebar" /><Icon name="back" /><Icon name="forward" />
      <div style={{ flex: 1, display: "flex", justifyContent: "center" }}>
        <div style={{ minWidth: 420, height: 32, borderRadius: 16, background: palette.surfaceHi, border: `1px solid ${palette.border}`, display: "flex", alignItems: "center", justifyContent: "center", gap: 8, padding: "0 18px", fontFamily: monoFont, fontSize: 15, color: palette.textDim }}>
          <span style={{ color: palette.accent }}>◎</span>{url}
        </div>
      </div>
      <Icon name="reload" /><StatusDot color={statusColor} /><Icon name="plus" />
      <div style={{ height: 30, padding: "0 16px", borderRadius: 15, background: palette.accentSoft, border: `1px solid ${palette.accent}`, color: palette.accent, fontFamily: monoFont, fontSize: 14, display: "flex", alignItems: "center" }}>Ask</div>
      <Icon name="gear" />
    </div>
    <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
      {sidebar ? <div style={{ width: 268, borderRight: `1px solid ${palette.border}`, background: "#101013", padding: 12 }}>{sidebar}</div> : null}
      <div style={{ flex: 1, position: "relative", overflow: "hidden" }}>{children}</div>
    </div>
  </div>
);

/* ── 1. intro ───────────────────────────────────────────────────────────── */
const IntroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const trail = ci(frame, [22, 55], [0, 1]);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <Backdrop glowY={42} />
      <div style={{ textAlign: "center" }}>
        <FadeUp>
          <div style={{ fontFamily: displayFont, fontWeight: 700, fontSize: 132, letterSpacing: -4, color: palette.text }}>
            Trail<span style={{ color: palette.accent }}>Browser</span>
          </div>
        </FadeUp>
        <div style={{ height: 5, width: 560, margin: "10px auto 0", borderRadius: 3, background: palette.accent, transform: `scaleX(${trail})`, transformOrigin: "left center", boxShadow: `0 0 22px ${palette.accentGlow}` }} />
        <FadeUp delay={28}>
          <div style={{ marginTop: 34, fontFamily: monoFont, fontSize: 26, color: palette.textDim, letterSpacing: 1 }}>
            A simple native browser — light on memory, with AI built in.
          </div>
        </FadeUp>
      </div>
    </AbsoluteFill>
  );
};

/* ── 2. memory ──────────────────────────────────────────────────────────── */
const MemoryBar: React.FC<{ label: string; mb: number; ratio: number; color: string; delay: number }> = ({ label, mb, ratio, color, delay }) => {
  const frame = useCurrentFrame();
  const grow = ci(frame, [delay, delay + 30], [0, 1]);
  const value = Math.round(ci(frame, [delay, delay + 30], [0, mb]));
  const maxH = 360;
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
      <div style={{ fontFamily: monoFont, color: palette.text, fontSize: 30 }}>{value.toLocaleString()} MB</div>
      <div style={{ width: 150, height: maxH * ratio * grow, background: `linear-gradient(180deg, ${color}, ${color}cc)`, borderRadius: "10px 10px 0 0", boxShadow: `0 0 40px ${color}55` }} />
      <div style={{ fontFamily: monoFont, color: palette.textDim, fontSize: 22 }}>{label}</div>
    </div>
  );
};

const MemoryScene: React.FC = () => (
  <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
    <Backdrop glowX={72} glowY={30} />
    <SceneHeading eyebrow="The headline feature" title={<>Up to <span style={{ color: palette.accent }}>1/10th</span> of Chrome's memory.</>} />
    <div style={{ display: "flex", gap: 120, alignItems: "flex-end", paddingLeft: 20 }}>
      <MemoryBar label="Chrome" mb={2100} ratio={1} color={palette.textFaint} delay={14} />
      <MemoryBar label="TrailBrowser" mb={210} ratio={0.1} color={palette.accent} delay={28} />
    </div>
    <FadeUp delay={60}>
      <div style={{ marginTop: 48, fontFamily: monoFont, fontSize: 22, color: palette.textDim }}>
        Inactive tabs release their WKWebView entirely — only the URL, title &amp; favicon stay.
      </div>
    </FadeUp>
  </AbsoluteFill>
);

/* ── 3. AI ──────────────────────────────────────────────────────────────── */
const AIScene: React.FC = () => {
  const frame = useCurrentFrame();
  const q = "Summarize this page in one line.";
  const shown = q.slice(0, Math.floor(ci(frame, [30, 70], [0, q.length])));
  const answerOpacity = ci(frame, [86, 104], [0, 1]);
  return (
    <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
      <Backdrop glowX={70} />
      <SceneHeading eyebrow="AI, in the page" title={<>Ask. Edit. <span style={{ color: palette.accent }}>Search.</span></>} />
      <FadeUp delay={10} style={{ alignSelf: "center" }}>
        <BrowserChrome url="https://news.ycombinator.com" height={440} width={1100}>
          <AbsoluteFill style={{ opacity: 0.18, padding: 40 }}>
            {Array.from({ length: 9 }).map((_, i) => (
              <div key={i} style={{ height: 14, background: palette.textFaint, borderRadius: 6, margin: "10px 0", width: `${90 - i * 6}%`, opacity: 0.4 }} />
            ))}
          </AbsoluteFill>
          <div style={{ position: "absolute", left: "50%", bottom: 40, transform: "translateX(-50%)", width: 720, background: "rgba(20,20,23,0.82)", backdropFilter: "blur(20px)", border: `1px solid ${palette.border}`, borderRadius: 16, padding: 18, boxShadow: "0 30px 80px rgba(0,0,0,0.6)" }}>
            <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
              <div style={{ fontFamily: monoFont, fontSize: 14, color: palette.bg, background: palette.accent, padding: "5px 16px", borderRadius: 9 }}>Ask</div>
              <div style={{ fontFamily: monoFont, fontSize: 14, color: palette.textDim, padding: "5px 16px", borderRadius: 9, border: `1px solid ${palette.border}` }}>Edit</div>
            </div>
            <div style={{ fontFamily: monoFont, fontSize: 18, color: palette.text }}>
              {shown}<span style={{ opacity: frame % 30 < 15 ? 1 : 0, color: palette.accent }}>|</span>
            </div>
            <div style={{ opacity: answerOpacity, marginTop: 14, paddingTop: 14, borderTop: `1px solid ${palette.border}`, fontFamily: displayFont, fontSize: 18, color: palette.textDim, lineHeight: 1.5 }}>
              The top thread debates whether AI agents will replace traditional video editors.
            </div>
          </div>
        </BrowserChrome>
      </FadeUp>
      <FadeUp delay={70}>
        <div style={{ marginTop: 34, textAlign: "center", fontFamily: monoFont, fontSize: 20, color: palette.textDim }}>
          Powered by Codex or Claude — reading a redacted snapshot, never your secrets.
        </div>
      </FadeUp>
    </AbsoluteFill>
  );
};

/* ── 4. memory MCP ──────────────────────────────────────────────────────── */
const ToolRow: React.FC<{ name: string; desc: string; delay: number }> = ({ name, desc, delay }) => (
  <FadeUp delay={delay} y={16}>
    <div style={{ display: "flex", alignItems: "baseline", gap: 16, padding: "11px 0", borderBottom: `1px solid ${palette.border}` }}>
      <span style={{ color: palette.accent, fontFamily: monoFont, fontSize: 17 }}>▸</span>
      <span style={{ fontFamily: monoFont, fontSize: 18, color: palette.text, minWidth: 230 }}>{name}</span>
      <span style={{ fontFamily: monoFont, fontSize: 16, color: palette.textDim }}>{desc}</span>
    </div>
  </FadeUp>
);

const MCPScene: React.FC = () => (
  <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
    <Backdrop glowX={70} glowY={40} />
    <SceneHeading eyebrow="Your memory, via MCP" title={<>Browsing history, <span style={{ color: palette.accent }}>as an MCP server.</span></>} />
    <FadeUp delay={10} style={{ alignSelf: "center" }}>
      <div style={{ width: 1080, background: palette.surface, border: `1px solid ${palette.border}`, borderRadius: 16, boxShadow: "0 40px 100px rgba(0,0,0,0.55)", overflow: "hidden" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "14px 20px", borderBottom: `1px solid ${palette.border}` }}>
          <div style={{ display: "flex", gap: 7 }}>
            {[palette.red, palette.yellow, palette.trafficGreen].map((c) => (
              <div key={c} style={{ width: 11, height: 11, borderRadius: "50%", background: c }} />
            ))}
          </div>
          <span style={{ fontFamily: monoFont, fontSize: 15, color: palette.textDim, marginLeft: 6 }}>trailbrowser-history · read-only</span>
          <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 8 }}>
            <StatusDot /> <span style={{ fontFamily: monoFont, fontSize: 14, color: palette.green }}>connected</span>
          </div>
        </div>
        <div style={{ padding: "16px 28px 22px" }}>
          <ToolRow name="browser_status" desc="runtime status · cookies never exposed" delay={22} />
          <ToolRow name="history_recent" desc="latest visited pages" delay={32} />
          <ToolRow name="history_search" desc="match by url, title, or host" delay={42} />
          <ToolRow name="history_by_domain" desc="every visit to one domain" delay={52} />
          <ToolRow name="history_top_domains" desc="most-visited sites, ranked" delay={62} />
        </div>
      </div>
    </FadeUp>
    <FadeUp delay={78}>
      <div style={{ marginTop: 32, textAlign: "center", fontFamily: monoFont, fontSize: 20, color: palette.textDim }}>
        Strictly read-only over history.jsonl — secrets redacted, never cookies or keychain.
      </div>
    </FadeUp>
  </AbsoluteFill>
);

/* ── 5. outro ───────────────────────────────────────────────────────────── */
const OutroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <Backdrop glowY={50} />
      <div style={{ textAlign: "center", transform: `scale(${0.9 + pop * 0.1})` }}>
        <div style={{ fontFamily: displayFont, fontWeight: 700, fontSize: 120, letterSpacing: -4, color: palette.text }}>
          Trail<span style={{ color: palette.accent }}>Browser</span>
        </div>
        <FadeUp delay={18}>
          <div style={{ marginTop: 22, fontFamily: monoFont, fontSize: 24, color: palette.textDim }}>The browser that gets out of your way.</div>
        </FadeUp>
        <FadeUp delay={34}>
          <div style={{ marginTop: 40, display: "inline-flex", alignItems: "center", gap: 12, fontFamily: monoFont, fontSize: 18, color: palette.text, background: palette.surfaceHi, border: `1px solid ${palette.border}`, borderRadius: 12, padding: "14px 22px" }}>
            <StatusDot /> <span style={{ color: palette.accent }}>$</span> make &amp;&amp; open TrailBrowser.app
          </div>
        </FadeUp>
      </div>
    </AbsoluteFill>
  );
};

/* ── composition + registration ─────────────────────────────────────────── */
const TrailBrowserExplainer: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: palette.bg }}>
    <Series>
      <Series.Sequence durationInFrames={D_INTRO}><IntroScene /></Series.Sequence>
      <Series.Sequence durationInFrames={D_MEMORY}><MemoryScene /></Series.Sequence>
      <Series.Sequence durationInFrames={D_AI}><AIScene /></Series.Sequence>
      <Series.Sequence durationInFrames={D_MCP}><MCPScene /></Series.Sequence>
      <Series.Sequence durationInFrames={D_OUTRO}><OutroScene /></Series.Sequence>
    </Series>
  </AbsoluteFill>
);

const RemotionRoot: React.FC = () => (
  <Composition id="TrailBrowserExplainer" component={TrailBrowserExplainer} durationInFrames={TOTAL_DURATION} fps={FPS} width={1920} height={1080} />
);

registerRoot(RemotionRoot);
