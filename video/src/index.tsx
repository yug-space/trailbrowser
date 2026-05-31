// TrailBrowserVideo.tsx — a complete, self-contained Remotion explainer for TrailBrowser.
// Drop this single file into a Remotion project's src/ as your entry, then:
//   npm i @remotion/google-fonts @remotion/transitions
//   npm run dev      (preview in Remotion Studio)
//   npx remotion render TrailBrowserExplainer out/trailbrowser.mp4
//
// 1920x1080 · 30fps · ~11s, fast-cut. Theme mirrors TrailBrowser's TBTheme (#f76b1c).

import React from "react";
import {
  AbsoluteFill,
  Composition,
  interpolate,
  registerRoot,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {
  TransitionSeries,
  springTiming,
  linearTiming,
} from "@remotion/transitions";
import { slide } from "@remotion/transitions/slide";
import { fade } from "@remotion/transitions/fade";
import { wipe } from "@remotion/transitions/wipe";
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

/* ── scene + transition durations (frames @ 30fps) ──────────────────────── */
const FPS = 30;
const D_INTRO = 66;
const D_MEMORY = 78;
const D_AI = 96;
const D_MCP = 84;
const D_OUTRO = 60;
const T = 12; // transition overlap
const TOTAL_DURATION =
  D_INTRO + D_MEMORY + D_AI + D_MCP + D_OUTRO - 4 * T;

/* ── spring configs ─────────────────────────────────────────────────────── */
const SNAP = { damping: 14, mass: 0.6, stiffness: 130 } as const;
const POP = { damping: 10, mass: 0.5, stiffness: 130 } as const;

/* ── animation + shared helpers ─────────────────────────────────────────── */
const ci = (frame: number, range: [number, number], out: [number, number]) =>
  interpolate(frame, range, out, { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

const pulse = (frame: number, speed = 6) => 0.5 + 0.5 * Math.sin(frame / speed);
const floaty = (frame: number, amp = 4, speed = 22) => Math.sin(frame / speed) * amp;

const useSpr = (delay = 0, config: Record<string, number> = SNAP) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config });
};

const Rise: React.FC<{ delay?: number; y?: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  delay = 0,
  y = 24,
  children,
  style,
}) => {
  const s = useSpr(delay, SNAP);
  return <div style={{ opacity: Math.min(1, s), transform: `translateY(${(1 - s) * y}px)`, ...style }}>{children}</div>;
};

const Pop: React.FC<{ delay?: number; from?: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  delay = 0,
  from = 0.82,
  children,
  style,
}) => {
  const s = useSpr(delay, POP);
  return <div style={{ opacity: Math.min(1, s), transform: `scale(${from + (1 - from) * s})`, ...style }}>{children}</div>;
};

const SlideIn: React.FC<{ delay?: number; x?: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  delay = 0,
  x = 44,
  children,
  style,
}) => {
  const s = useSpr(delay, SNAP);
  return <div style={{ opacity: Math.min(1, s), transform: `translateX(${(1 - s) * x}px)`, ...style }}>{children}</div>;
};

const SceneHeading: React.FC<{ eyebrow: string; title: React.ReactNode }> = ({ eyebrow, title }) => {
  const bar = useSpr(8, SNAP);
  return (
    <div style={{ marginBottom: 44 }}>
      <SlideIn x={-30}>
        <div style={{ fontFamily: monoFont, color: palette.accent, letterSpacing: 4, fontSize: 20, textTransform: "uppercase", marginBottom: 14 }}>
          {eyebrow}
        </div>
      </SlideIn>
      <Rise delay={3}>
        <h1 style={{ fontFamily: displayFont, color: palette.text, fontSize: 76, fontWeight: 700, lineHeight: 1.02, letterSpacing: -2, margin: 0, maxWidth: 1180 }}>
          {title}
        </h1>
      </Rise>
      <div style={{ marginTop: 18, height: 4, width: 120, borderRadius: 3, background: palette.accent, transform: `scaleX(${bar})`, transformOrigin: "left", boxShadow: `0 0 16px ${palette.accentGlow}` }} />
    </div>
  );
};

const Backdrop: React.FC<{ glowX?: number; glowY?: number }> = ({ glowX = 50, glowY = 28 }) => {
  const frame = useCurrentFrame();
  const gx = glowX + Math.sin(frame / 40) * 6;
  const gy = glowY + Math.cos(frame / 50) * 5;
  const pan = (frame * 0.35) % 64;
  const glow = 0.3 + 0.12 * pulse(frame, 18);
  return (
    <AbsoluteFill style={{ backgroundColor: palette.bg }}>
      <AbsoluteFill
        style={{
          backgroundImage: `linear-gradient(${palette.border} 1px, transparent 1px), linear-gradient(90deg, ${palette.border} 1px, transparent 1px)`,
          backgroundSize: "64px 64px",
          backgroundPosition: `${pan}px ${pan}px`,
          opacity: 0.5,
          maskImage: "radial-gradient(circle at center, black, transparent 78%)",
          WebkitMaskImage: "radial-gradient(circle at center, black, transparent 78%)",
        }}
      />
      <AbsoluteFill style={{ background: `radial-gradient(640px circle at ${gx}% ${gy}%, ${palette.accentGlow}, transparent 60%)`, opacity: glow }} />
    </AbsoluteFill>
  );
};

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

const StatusDot: React.FC<{ color?: string; live?: boolean }> = ({ color = palette.green, live = true }) => {
  const frame = useCurrentFrame();
  const glow = live ? 6 + pulse(frame, 7) * 12 : 10;
  return <div style={{ width: 9, height: 9, borderRadius: "50%", background: color, boxShadow: `0 0 ${glow}px ${color}` }} />;
};

const BrowserChrome: React.FC<{
  url?: string; statusColor?: string; width?: number; height?: number; children?: React.ReactNode; sidebar?: React.ReactNode;
}> = ({ url = "trailbrowser://home", statusColor = palette.green, width = 1180, height = 600, children, sidebar }) => {
  const frame = useCurrentFrame();
  const lift = floaty(frame, 3, 24);
  const prog = ci(frame, [8, 44], [0, 100]);
  const progOpacity = ci(frame, [44, 56], [1, 0]);
  const askGlow = 6 + pulse(frame, 8) * 14;
  return (
    <div style={{ width, height, borderRadius: 18, overflow: "hidden", background: palette.surface, border: `1px solid ${palette.border}`, boxShadow: "0 50px 120px rgba(0,0,0,0.6)", display: "flex", flexDirection: "column", transform: `translateY(${lift}px)` }}>
      <div style={{ position: "relative", height: 52, display: "flex", alignItems: "center", gap: 14, padding: "0 16px", borderBottom: `1px solid ${palette.border}`, background: palette.surface }}>
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
        <div style={{ height: 30, padding: "0 16px", borderRadius: 15, background: palette.accentSoft, border: `1px solid ${palette.accent}`, color: palette.accent, fontFamily: monoFont, fontSize: 14, display: "flex", alignItems: "center", boxShadow: `0 0 ${askGlow}px ${palette.accentGlow}` }}>Ask</div>
        <Icon name="gear" />
        {/* 2px accent load bar, like the real app */}
        <div style={{ position: "absolute", left: 0, bottom: -1, height: 2, width: `${prog}%`, background: palette.accent, opacity: progOpacity, boxShadow: `0 0 10px ${palette.accentGlow}` }} />
      </div>
      <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
        {sidebar ? <div style={{ width: 268, borderRight: `1px solid ${palette.border}`, background: "#101013", padding: 12 }}>{sidebar}</div> : null}
        <div style={{ flex: 1, position: "relative", overflow: "hidden" }}>{children}</div>
      </div>
    </div>
  );
};

/* ── brand mark (the official TrailBrowser logo, animated) ──────────────── */
const TRAIL_D = "M170 392 C250 378 298 330 286 286 C276 246 200 240 192 200 C186 166 248 156 342 132";

const Waypoint: React.FC<{ x: number; y: number; r: number; ring?: boolean; popDelay: number; gid: string; animated: boolean }> = ({ x, y, r, ring, popDelay, gid, animated }) => {
  const spr = Math.min(1, useSpr(popDelay, POP));
  const s = animated ? spr : 1;
  if (s <= 0.001) return null;
  const common = { style: { transformBox: "fill-box" as const, transformOrigin: "center", transform: `scale(${s})` } };
  return ring
    ? <circle cx={x} cy={y} r={r} fill="#0a0a0b" stroke={`url(#${gid})`} strokeWidth={9} {...common} />
    : <circle cx={x} cy={y} r={r} fill="#f76b1c" {...common} />;
};

const TrailMark: React.FC<{ size?: number; tile?: boolean; drawDelay?: number; drawDur?: number; uid?: string; animated?: boolean }> = ({ size = 240, tile = true, drawDelay = 6, drawDur = 32, uid = "m", animated = true }) => {
  const frame = useCurrentFrame();
  const p = animated ? ci(frame, [drawDelay, drawDelay + drawDur], [0, 1]) : 1;
  const summitSpr = Math.min(1, useSpr(drawDelay + drawDur, POP));
  const summit = animated ? summitSpr : 1;
  const tid = `tb-trail-${uid}`, sid = `tb-summit-${uid}`, gid = `tb-glow-${uid}`, bid = `tb-tile-${uid}`;
  const dot = { transformBox: "fill-box" as const, transformOrigin: "center", transform: `scale(${summit})` };
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" style={{ overflow: "visible" }}>
      <defs>
        <linearGradient id={bid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1e1e24" /><stop offset="1" stopColor="#0a0a0b" />
        </linearGradient>
        <linearGradient id={tid} x1="0.1" y1="1" x2="0.9" y2="0">
          <stop offset="0" stopColor="#ffb066" /><stop offset="1" stopColor="#f76b1c" />
        </linearGradient>
        <radialGradient id={sid} cx="0.5" cy="0.4" r="0.6">
          <stop offset="0" stopColor="#ffd9b0" /><stop offset="0.55" stopColor="#f76b1c" /><stop offset="1" stopColor="#f76b1c" />
        </radialGradient>
        <filter id={gid} x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="10" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
        </filter>
      </defs>
      {tile ? (
        <>
          <rect x="16" y="16" width="480" height="480" rx="108" fill={`url(#${bid})`} />
          <rect x="16.5" y="16.5" width="479" height="479" rx="107.5" fill="none" stroke="rgba(255,255,255,0.09)" />
          <rect x="16" y="16" width="480" height="240" rx="108" fill="white" opacity="0.04" />
        </>
      ) : null}
      <path d={TRAIL_D} fill="none" stroke="#f76b1c" strokeWidth={26} strokeLinecap="round" opacity={0.35} filter={`url(#${gid})`} pathLength={1} strokeDasharray={1} strokeDashoffset={1 - p} />
      <path d={TRAIL_D} fill="none" stroke={`url(#${tid})`} strokeWidth={26} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - p} />
      <Waypoint x={170} y={392} r={15} ring popDelay={drawDelay} gid={tid} animated={animated} />
      <Waypoint x={286} y={286} r={13} popDelay={drawDelay + drawDur * 0.46} gid={tid} animated={animated} />
      <Waypoint x={192} y={200} r={13} popDelay={drawDelay + drawDur * 0.72} gid={tid} animated={animated} />
      <circle cx={342} cy={132} r={34} fill="#f76b1c" opacity={0.18 + 0.22 * pulse(frame, 9)} filter={`url(#${gid})`} style={dot} />
      <circle cx={342} cy={132} r={22} fill={`url(#${sid})`} style={dot} />
    </svg>
  );
};

/* ── 1. intro ───────────────────────────────────────────────────────────── */
const IntroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const lift = floaty(frame, 5, 26);
  const bar = useSpr(34, SNAP);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <Backdrop glowY={42} />
      <div style={{ display: "flex", alignItems: "center", gap: 46, transform: `translateY(${lift}px)` }}>
        <Pop from={0.7}><TrailMark size={236} tile drawDelay={8} drawDur={34} uid="intro" /></Pop>
        <div>
          <SlideIn delay={16} x={44}>
            <div style={{ fontFamily: displayFont, fontWeight: 700, fontSize: 112, letterSpacing: -4, color: palette.text, lineHeight: 1 }}>
              Trail<span style={{ color: palette.accent }}>Browser</span>
            </div>
          </SlideIn>
          <div style={{ height: 5, width: 300, marginTop: 16, borderRadius: 3, background: palette.accent, transform: `scaleX(${bar})`, transformOrigin: "left", boxShadow: `0 0 ${18 + pulse(frame, 9) * 14}px ${palette.accentGlow}` }} />
          <Rise delay={24}>
            <div style={{ marginTop: 20, fontFamily: monoFont, fontSize: 24, color: palette.textDim, letterSpacing: 1 }}>
              A simple native browser — light on memory, with AI built in.
            </div>
          </Rise>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ── 2. memory ──────────────────────────────────────────────────────────── */
const MemoryBar: React.FC<{ label: string; mb: number; ratio: number; color: string; delay: number; badge?: string }> = ({ label, mb, ratio, color, delay, badge }) => {
  const frame = useCurrentFrame();
  const grow = Math.min(1, useSpr(delay, SNAP));
  const value = Math.round(grow * mb);
  const maxH = 360;
  const badgePop = Math.min(1, useSpr(delay + 14, POP));
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14, position: "relative" }}>
      <div style={{ fontFamily: monoFont, color: palette.text, fontSize: 30 }}>{value.toLocaleString()} MB</div>
      <div style={{ position: "relative", width: 150, height: maxH * ratio * grow, background: `linear-gradient(180deg, ${color}, ${color}cc)`, borderRadius: "10px 10px 0 0", boxShadow: `0 0 ${30 + pulse(frame, 10) * 20}px ${color}55` }}>
        {badge ? (
          <div style={{ position: "absolute", top: "50%", right: -168, transform: `translateY(-50%) scale(${badgePop})`, transformOrigin: "left center", fontFamily: monoFont, fontSize: 22, fontWeight: 700, color: palette.accent, background: palette.accentSoft, border: `1px solid ${palette.accent}`, borderRadius: 10, padding: "6px 12px", whiteSpace: "nowrap", boxShadow: `0 0 18px ${palette.accentGlow}` }}>{badge}</div>
        ) : null}
      </div>
      <div style={{ fontFamily: monoFont, color: palette.textDim, fontSize: 22 }}>{label}</div>
    </div>
  );
};

const MemoryScene: React.FC = () => (
  <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
    <Backdrop glowX={72} glowY={30} />
    <SceneHeading eyebrow="The headline feature" title={<>Up to <span style={{ color: palette.accent }}>1/10th</span> of Chrome's memory.</>} />
    <div style={{ display: "flex", gap: 120, alignItems: "flex-end", paddingLeft: 20 }}>
      <MemoryBar label="Chrome" mb={2100} ratio={1} color={palette.textFaint} delay={6} />
      <MemoryBar label="TrailBrowser" mb={210} ratio={0.1} color={palette.accent} delay={14} badge="10× lighter" />
    </div>
    <Rise delay={36}>
      <div style={{ marginTop: 44, fontFamily: monoFont, fontSize: 22, color: palette.textDim }}>
        Inactive tabs release their WKWebView entirely — only the URL, title &amp; favicon stay.
      </div>
    </Rise>
  </AbsoluteFill>
);

/* ── 3. AI ──────────────────────────────────────────────────────────────── */
const SkeletonLine: React.FC<{ i: number }> = ({ i }) => {
  const s = Math.min(1, useSpr(8 + i * 1.5, SNAP));
  return <div style={{ height: 14, background: palette.textFaint, borderRadius: 6, margin: "10px 0", width: `${(90 - i * 6) * s}%`, opacity: 0.4 }} />;
};

const EngineChip: React.FC<{ name: string; cmd: string; tag: string; delay: number }> = ({ name, cmd, tag, delay }) => {
  const frame = useCurrentFrame();
  const glow = 6 + pulse(frame, 9) * 10;
  return (
    <Pop delay={delay} from={0.85}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, background: palette.surfaceHi, border: `1px solid ${palette.border}`, borderRadius: 12, padding: "11px 16px", boxShadow: `0 0 ${glow}px rgba(247,107,28,0.18)` }}>
        <span style={{ color: palette.accent, fontFamily: monoFont, fontSize: 16 }}>$</span>
        <span style={{ fontFamily: displayFont, fontWeight: 700, fontSize: 20, color: palette.text }}>{name}</span>
        <span style={{ fontFamily: monoFont, fontSize: 15, color: palette.textFaint }}>{cmd}</span>
        <span style={{ fontFamily: monoFont, fontSize: 12, color: palette.accent, background: palette.accentSoft, border: `1px solid ${palette.accent}`, borderRadius: 6, padding: "2px 8px" }}>{tag}</span>
      </div>
    </Pop>
  );
};

const AIScene: React.FC = () => {
  const frame = useCurrentFrame();
  const q = "Summarize this page in one line.";
  const shown = q.slice(0, Math.floor(ci(frame, [20, 46], [0, q.length])));
  const answerS = Math.min(1, useSpr(50, SNAP));
  const panelLift = floaty(frame, 4, 20);
  return (
    <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
      <Backdrop glowX={70} />
      <SceneHeading eyebrow="AI, in the page" title={<>Ask. Edit. <span style={{ color: palette.accent }}>Search.</span></>} />
      <Pop delay={4} from={0.9} style={{ alignSelf: "center" }}>
        <BrowserChrome url="https://news.ycombinator.com" height={400} width={1100}>
          <AbsoluteFill style={{ opacity: 0.18, padding: 40 }}>
            {Array.from({ length: 9 }).map((_, i) => <SkeletonLine key={i} i={i} />)}
          </AbsoluteFill>
          <div style={{ position: "absolute", left: "50%", bottom: 40, transform: `translate(-50%, ${panelLift}px)`, width: 720, background: "rgba(20,20,23,0.82)", backdropFilter: "blur(20px)", border: `1px solid ${palette.border}`, borderRadius: 16, padding: 18, boxShadow: "0 30px 80px rgba(0,0,0,0.6)" }}>
            <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
              <div style={{ fontFamily: monoFont, fontSize: 14, color: palette.bg, background: palette.accent, padding: "5px 16px", borderRadius: 9 }}>Ask</div>
              <div style={{ fontFamily: monoFont, fontSize: 14, color: palette.textDim, padding: "5px 16px", borderRadius: 9, border: `1px solid ${palette.border}` }}>Edit</div>
            </div>
            <div style={{ fontFamily: monoFont, fontSize: 18, color: palette.text }}>
              {shown}<span style={{ opacity: frame % 20 < 10 ? 1 : 0, color: palette.accent }}>|</span>
            </div>
            <div style={{ opacity: answerS, transform: `translateY(${(1 - answerS) * 10}px)`, marginTop: 14, paddingTop: 14, borderTop: `1px solid ${palette.border}`, fontFamily: displayFont, fontSize: 18, color: palette.textDim, lineHeight: 1.5 }}>
              The top thread debates whether AI agents will replace traditional video editors.
            </div>
          </div>
        </BrowserChrome>
      </Pop>
      <div style={{ marginTop: 24, display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
        <div style={{ display: "flex", gap: 16 }}>
          <EngineChip name="Codex" cmd="codex exec --sandbox read-only" tag="default" delay={56} />
          <EngineChip name="Claude" cmd="claude -p" tag="Claude Code" delay={62} />
        </div>
        <Rise delay={70}>
          <div style={{ textAlign: "center", fontFamily: monoFont, fontSize: 19, color: palette.textDim }}>
            Runs your local codex or claude CLI — on your Mac, read-only, never your secrets.
          </div>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

/* ── 4. memory MCP ──────────────────────────────────────────────────────── */
const ToolRow: React.FC<{ name: string; desc: string; delay: number; lit: boolean }> = ({ name, desc, delay, lit }) => (
  <SlideIn delay={delay} x={-36}>
    <div style={{ display: "flex", alignItems: "baseline", gap: 16, padding: "11px 14px", borderRadius: 8, borderBottom: `1px solid ${palette.border}`, background: lit ? palette.accentSoft : "transparent", transition: "background 0.1s" }}>
      <span style={{ color: palette.accent, fontFamily: monoFont, fontSize: 17 }}>▸</span>
      <span style={{ fontFamily: monoFont, fontSize: 18, color: palette.text, minWidth: 230 }}>{name}</span>
      <span style={{ fontFamily: monoFont, fontSize: 16, color: palette.textDim }}>{desc}</span>
    </div>
  </SlideIn>
);

const MCPScene: React.FC = () => {
  const frame = useCurrentFrame();
  const tools = [
    { name: "browser_status", desc: "runtime status · cookies never exposed", delay: 12 },
    { name: "history_recent", desc: "latest visited pages", delay: 17 },
    { name: "history_search", desc: "match by url, title, or host", delay: 22 },
    { name: "history_by_domain", desc: "every visit to one domain", delay: 27 },
    { name: "history_top_domains", desc: "most-visited sites, ranked", delay: 32 },
  ];
  const scan = frame > 44 ? Math.floor((frame - 44) / 9) % tools.length : -1;
  return (
    <AbsoluteFill style={{ padding: 100, justifyContent: "center" }}>
      <Backdrop glowX={70} glowY={40} />
      <SceneHeading eyebrow="Your memory, via MCP" title={<>Browsing history, <span style={{ color: palette.accent }}>as an MCP server.</span></>} />
      <Pop delay={4} from={0.92} style={{ alignSelf: "center" }}>
        <div style={{ width: 1080, background: palette.surface, border: `1px solid ${palette.border}`, borderRadius: 16, boxShadow: "0 40px 100px rgba(0,0,0,0.55)", overflow: "hidden", transform: `translateY(${floaty(frame, 3, 24)}px)` }}>
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
          <div style={{ padding: "12px 20px 18px" }}>
            {tools.map((t, i) => <ToolRow key={t.name} {...t} lit={scan === i} />)}
          </div>
        </div>
      </Pop>
      <Rise delay={52}>
        <div style={{ marginTop: 30, textAlign: "center", fontFamily: monoFont, fontSize: 20, color: palette.textDim }}>
          Strictly read-only over history.jsonl — secrets redacted, never cookies or keychain.
        </div>
      </Rise>
    </AbsoluteFill>
  );
};

/* ── 5. outro ───────────────────────────────────────────────────────────── */
const OutroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const pop = useSpr(0, POP);
  const lift = floaty(frame, 4, 24);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <Backdrop glowY={50} />
      <div style={{ textAlign: "center", transform: `translateY(${lift}px) scale(${0.9 + Math.min(1, pop) * 0.1})` }}>
        <div style={{ display: "flex", justifyContent: "center", marginBottom: 4 }}>
          <TrailMark size={148} tile={false} drawDelay={2} drawDur={24} uid="outro" />
        </div>
        <div style={{ fontFamily: displayFont, fontWeight: 700, fontSize: 116, letterSpacing: -4, color: palette.text }}>
          Trail<span style={{ color: palette.accent }}>Browser</span>
        </div>
        <Rise delay={12}>
          <div style={{ marginTop: 16, fontFamily: monoFont, fontSize: 24, color: palette.textDim }}>The browser that gets out of your way.</div>
        </Rise>
        <Pop delay={22} from={0.85}>
          <div style={{ marginTop: 38, display: "inline-flex", alignItems: "center", gap: 12, fontFamily: monoFont, fontSize: 18, color: palette.text, background: palette.surfaceHi, border: `1px solid ${palette.border}`, borderRadius: 12, padding: "14px 22px", boxShadow: `0 0 ${16 + pulse(frame, 8) * 22}px ${palette.accentGlow}` }}>
            <StatusDot /> <span style={{ color: palette.accent }}>$</span> make &amp;&amp; open TrailBrowser.app
          </div>
        </Pop>
      </div>
    </AbsoluteFill>
  );
};

/* ── composition + registration ─────────────────────────────────────────── */
const slideT = springTiming({ config: { damping: 26 }, durationInFrames: T });
const fastT = linearTiming({ durationInFrames: T });

const TrailBrowserExplainer: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: palette.bg }}>
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={D_INTRO}><IntroScene /></TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: "from-right" })} timing={slideT} />
      <TransitionSeries.Sequence durationInFrames={D_MEMORY}><MemoryScene /></TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={wipe({ direction: "from-left" })} timing={fastT} />
      <TransitionSeries.Sequence durationInFrames={D_AI}><AIScene /></TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: "from-bottom" })} timing={slideT} />
      <TransitionSeries.Sequence durationInFrames={D_MCP}><MCPScene /></TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={fade()} timing={fastT} />
      <TransitionSeries.Sequence durationInFrames={D_OUTRO}><OutroScene /></TransitionSeries.Sequence>
    </TransitionSeries>
  </AbsoluteFill>
);

const RemotionRoot: React.FC = () => (
  <Composition id="TrailBrowserExplainer" component={TrailBrowserExplainer} durationInFrames={TOTAL_DURATION} fps={FPS} width={1920} height={1080} />
);

registerRoot(RemotionRoot);
