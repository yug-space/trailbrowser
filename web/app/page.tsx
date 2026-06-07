import ClientEffects from "./ClientEffects";

const repoUrl = "https://github.com/yug-space/trailbrowser";

const features = [
  {
    title: "Native WebKit shell",
    body: "TrailBrowser is Objective-C, AppKit, and WKWebView. No Electron runtime, no bundled Chromium, no second rendering engine.",
    icon: "browser",
  },
  {
    title: "Fast tab work",
    body: "Sidebar tabs, pinned tabs, drag reordering, favicon switcher, Ctrl+Tab cycling, recently closed tabs, and memory-aware tab sleeping.",
    icon: "tabs",
  },
  {
    title: "AI where it helps",
    body: "Ask or edit the current page, generate an AI page from the home search box, and autofill forms with explicit confirmation.",
    icon: "spark",
  },
  {
    title: "History that organizes itself",
    body: "Local redacted history, URL autocomplete, settings search, and optional AI topic clustering for browsing sessions.",
    icon: "history",
  },
  {
    title: "Bookmarks and downloads",
    body: "A smart bookmarks bar appears only when useful. Downloads include progress, cancel, resume, reveal, and a clearable log.",
    icon: "bookmark",
  },
  {
    title: "Privacy by default",
    body: "No telemetry. Private tabs use non-persistent storage. Cookie import is local, explicit, and Keychain-gated.",
    icon: "lock",
  },
  {
    title: "Passkeys",
    body: "Local builds ad-hoc sign with browser passkey entitlements. WebKit can use macOS fingerprint, face, or screen-lock flows.",
    icon: "key",
  },
  {
    title: "Agent ready",
    body: "A read-only MCP server exposes browser status and history search for local agent workflows.",
    icon: "terminal",
  },
];

const shortcuts = [
  ["⌘L", "Focus address bar"],
  ["⌘T", "New tab"],
  ["⌃Tab", "Next tab"],
  ["⌘⌥Tab", "Visual tab switcher"],
  ["⌘⇧T", "Reopen closed tab"],
  ["⌘F", "Find in page"],
  ["⌘D", "Bookmark page"],
  ["⌘,", "Settings"],
];

function Icon({ name }: { name: string }) {
  if (name === "tabs") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <rect x="3" y="4" width="7" height="16" rx="2" />
        <rect x="12" y="4" width="9" height="7" rx="2" opacity=".55" />
        <rect x="12" y="13" width="9" height="7" rx="2" opacity=".32" />
      </svg>
    );
  }
  if (name === "spark") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 3l1.6 5.1L19 10l-5.4 1.9L12 17l-1.6-5.1L5 10l5.4-1.9L12 3z" />
        <path d="M18 15l.8 2.2L21 18l-2.2.8L18 21l-.8-2.2L15 18l2.2-.8L18 15z" opacity=".55" />
      </svg>
    );
  }
  if (name === "history") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" strokeWidth="1.8" />
        <path d="M12 7v5l3 2" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
      </svg>
    );
  }
  if (name === "bookmark") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M7 4h10a1 1 0 0 1 1 1v16l-6-3.4L6 21V5a1 1 0 0 1 1-1z" />
      </svg>
    );
  }
  if (name === "lock") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M7 11V8a5 5 0 0 1 10 0v3" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        <rect x="5" y="11" width="14" height="10" rx="2" fill="none" stroke="currentColor" strokeWidth="1.8" />
      </svg>
    );
  }
  if (name === "key") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="8" cy="12" r="4" fill="none" stroke="currentColor" strokeWidth="1.8" />
        <path d="M12 12h9m-3 0v3m-3-3v2" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
      </svg>
    );
  }
  if (name === "terminal") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M4 6l5 5-5 5M11 18h9" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="3" fill="none" stroke="currentColor" strokeWidth="1.8" />
      <path d="M3 9h18M8 5v14" fill="none" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  );
}

export default function Home() {
  return (
    <>
      <ClientEffects />
      <header className="site-nav" id="nav">
        <a className="brand" href="#top" aria-label="TrailBrowser home">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/trailbrowser-mark.svg" alt="" />
          <span>TrailBrowser</span>
        </a>
        <nav className="nav-links" aria-label="Primary navigation">
          <a href="#features">Features</a>
          <a href="#assistant">Assistant</a>
          <a href="#opensource">Open source</a>
          <a href="#build">Build</a>
        </nav>
        <div className="nav-actions">
          <a href={repoUrl} target="_blank" rel="noreferrer">
            GitHub
          </a>
          <a className="button small" href="#build">
            Get started
          </a>
        </div>
        <button className="nav-toggle" id="navToggle" type="button" aria-label="Toggle navigation">
          <span />
          <span />
        </button>
      </header>

      <main id="top">
        <section className="hero section-pad">
          <div className="hero-copy">
            <p className="eyebrow">Native macOS browser · WebKit · MIT licensed</p>
            <h1>A calm, fast browser for people who keep a lot open.</h1>
            <p className="hero-subtitle">
              TrailBrowser is a small AppKit browser built on the system WebKit engine. It keeps everyday
              browser work sharp: tabs, bookmarks, history, downloads, passkeys, and a local AI assistant,
              without Electron or telemetry.
            </p>
            <div className="hero-actions">
              <a className="button" href={repoUrl} target="_blank" rel="noreferrer">
                View source
              </a>
              <a className="button secondary" href="#features">
                Explore features
              </a>
            </div>
            <div className="stats" aria-label="Project highlights">
              <span>No telemetry</span>
              <span>macOS 11+</span>
              <span>Objective-C</span>
              <span>Local MCP server</span>
            </div>
          </div>

          <div className="browser-card" aria-label="TrailBrowser interface preview">
            <div className="traffic">
              <span />
              <span />
              <span />
            </div>
            <div className="mock-toolbar">
              <button aria-label="Sidebar" />
              <div className="address">
                <span className="lock-dot" />
                <span className="url-static">https://news.ycombinator.com</span>
                <span className="url-typed" id="typed" />
              </div>
              <button className="ask">Ask AI</button>
            </div>
            <div className="bookmark-strip">
              <span>Hacker News</span>
              <span>GitHub</span>
              <span>WebKit</span>
            </div>
            <div className="mock-body">
              <aside>
                <p>Tabs 6</p>
                <div className="tab active">Hacker News</div>
                <div className="tab">GitHub pull request</div>
                <div className="tab">AltSpace form</div>
                <div className="tab sleeping">Reference docs</div>
              </aside>
              <section>
                <div className="page-line wide" />
                <div className="page-line" />
                <div className="page-grid">
                  <div />
                  <div />
                  <div />
                </div>
                <div className="assistant-panel chat">
                  <strong>Ask AI</strong>
                  <p className="typing"><i /><i /><i /></p>
                  <p className="ai-text">This page has three relevant links, one discussion thread, and a form action worth checking.</p>
                </div>
              </section>
            </div>
          </div>
        </section>

        <section className="feature-band">
          <span>System WebKit</span>
          <span>Sidebar tabs</span>
          <span>AI form autofill</span>
          <span>Passkeys</span>
          <span>Bookmarks</span>
          <span>History clustering</span>
          <span>MCP history server</span>
        </section>

        <section className="section-pad" id="features">
          <div className="section-head">
            <p className="eyebrow">Feature complete where it matters</p>
            <h2>Small browser, serious surface area.</h2>
            <p>
              The repo is built to be readable, maintainable, and hackable. Core browser behavior lives in
              one native macOS app, with docs and contribution paths already in place.
            </p>
          </div>
          <div className="feature-grid">
            {features.map((feature) => (
              <article className="feature-card reveal" key={feature.title}>
                <div className="feature-icon">
                  <Icon name={feature.icon} />
                </div>
                <h3>{feature.title}</h3>
                <p>{feature.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section-pad split" id="assistant">
          <div>
            <p className="eyebrow">Local assistant</p>
            <h2>Ask pages questions, edit text, and fill forms carefully.</h2>
            <p>
              The assistant shells out to your selected local CLI, Codex or Claude. It can summarize the
              current page, draft edits, create generated pages, and fill detected forms with explicit user
              approval. Sensitive fields are excluded.
            </p>
            <ul className="check-list">
              <li>Form autofill ignores passwords, payment fields, OTPs, hidden fields, and file inputs.</li>
              <li>Ask/Edit mode changes close stale popups automatically.</li>
              <li>Known embedded form providers are opened directly before filling.</li>
            </ul>
          </div>
          <div className="chat-card chat reveal">
            <div className="chat-head">
              <span>Ask AI</span>
              <small>codex</small>
            </div>
            <div className="chat-bubble user">Fill this stay application from my note.</div>
            <div className="chat-bubble ai">
              <span className="typing"><i /><i /><i /></span>
              <p className="ai-text">I found 9 fillable fields. I can fill name, email, dates, work type, and message. I will skip hidden and sensitive fields.</p>
            </div>
            <div className="chat-input">Review before filling</div>
          </div>
        </section>

        <section className="section-pad split reverse">
          <div>
            <p className="eyebrow">Performance posture</p>
            <h2>Designed around WebKit sharing and memory pressure.</h2>
            <p>
              TrailBrowser can keep tabs live for smooth switching, then sleep inactive tabs when memory
              pressure rises. The benchmark script is included so contributors can reproduce claims instead
              of trusting marketing copy.
            </p>
          </div>
          <div className="bench reveal">
            <div className="bench-row">
              <span>Chrome · 12 live tabs</span>
              <div><i className="bench-fill chrome" data-w="100">3.7 GB</i></div>
            </div>
            <div className="bench-row">
              <span>TrailBrowser · 12 live tabs</span>
              <div><i className="bench-fill trail" data-w="46">1.7 GB</i></div>
            </div>
            <p>Measured with <code>tools/bench-memory.sh</code>. Lower is better.</p>
          </div>
        </section>

        <section className="section-pad" id="opensource">
          <div className="section-head">
            <p className="eyebrow">Open source ready</p>
            <h2>Maintained like a real project.</h2>
          </div>
          <div className="open-grid">
            <a href={`${repoUrl}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noreferrer">Contributing guide</a>
            <a href={`${repoUrl}/blob/main/SECURITY.md`} target="_blank" rel="noreferrer">Security policy</a>
            <a href={`${repoUrl}/blob/main/CODE_OF_CONDUCT.md`} target="_blank" rel="noreferrer">Code of conduct</a>
            <a href={`${repoUrl}/blob/main/CHANGELOG.md`} target="_blank" rel="noreferrer">Changelog</a>
            <a href={`${repoUrl}/blob/main/docs/BROWSER_FEATURES.md`} target="_blank" rel="noreferrer">Feature matrix</a>
            <a href={`${repoUrl}/blob/main/LICENSE`} target="_blank" rel="noreferrer">MIT license</a>
          </div>
        </section>

        <section className="section-pad" id="shortcuts">
          <div className="section-head">
            <p className="eyebrow">Keyboard first</p>
            <h2>Fast paths for everyday browsing.</h2>
          </div>
          <div className="shortcut-grid">
            {shortcuts.map(([key, label]) => (
              <div className="shortcut reveal" key={key}>
                <kbd>{key}</kbd>
                <span>{label}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="section-pad build-card" id="build">
          <div>
            <p className="eyebrow">Build locally</p>
            <h2>Clone, make, run.</h2>
            <p>TrailBrowser builds with the macOS command line tools. The website is this Next.js app.</p>
          </div>
          <pre aria-label="Build commands"><code>{`git clone https://github.com/yug-space/trailbrowser
cd trailbrowser
make
make run-browser

cd web
npm install
npm run build`}</code></pre>
        </section>
      </main>

      <footer>
        <div className="footer-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/trailbrowser-mark.svg" alt="" />
          <span>TrailBrowser</span>
        </div>
        <p>Native macOS browser. WebKit. No telemetry. MIT licensed.</p>
        <nav>
          <a href={repoUrl} target="_blank" rel="noreferrer">GitHub</a>
          <a href={`${repoUrl}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noreferrer">Contributing</a>
          <a href={`${repoUrl}/blob/main/SECURITY.md`} target="_blank" rel="noreferrer">Security</a>
        </nav>
      </footer>
    </>
  );
}
