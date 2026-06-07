const repoUrl = "https://github.com/yug-space/trailbrowser";

const steps = [
  {
    number: "01",
    title: "Switch",
    body: "Move between open tabs with a clean favicon switcher, sidebar tabs, Ctrl+Tab, and Cmd+Opt+Tab.",
  },
  {
    number: "02",
    title: "Ask",
    body: "Ask the current page questions, edit selected text, or fill safe form fields with your local Codex or Claude CLI.",
  },
  {
    number: "03",
    title: "Remember",
    body: "Keep bookmarks, downloads, local history, topic clusters, passkeys, and a read-only MCP history server close by.",
  },
];

const howItWorks = [
  ["01", "Built native", "Objective-C, AppKit, and the system WebKit engine. No Electron and no bundled Chromium."],
  ["02", "Keeps pages smooth", "Tabs stay live by default, then older background tabs can sleep when memory pressure rises."],
  ["03", "Runs AI locally", "The assistant shells out to Codex or Claude only when you ask. No hosted assistant backend."],
  ["04", "Stays yours", "No telemetry. Private tabs use non-persistent storage. Cookie import is explicit and Keychain gated."],
];

export default function Home() {
  return (
    <>
      <header className="nav">
        <a className="brand" href="#top" aria-label="TrailBrowser home">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/trailbrowser-mark.svg" alt="" />
          <span>TrailBrowser</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#what">What it does</a>
          <a href="#how">How it works</a>
        </nav>
        <div className="nav-actions">
          <a href={repoUrl} target="_blank" rel="noreferrer">
            GitHub
          </a>
          <a href={`${repoUrl}/releases`} target="_blank" rel="noreferrer">
            Download
          </a>
        </div>
      </header>

      <main id="top">
        <section className="hero">
          <p className="kicker">macOS · local-first · WebKit</p>
          <h1>
            Your browser,
            <br />
            one switcher away.
          </h1>
          <div className="shortcut" aria-label="Command Option Tab">
            <kbd>command</kbd>
            <span>+</span>
            <kbd>option</kbd>
            <span>+</span>
            <kbd>tab</kbd>
          </div>
          <p className="lead">
            TrailBrowser is a small native macOS browser for people who keep a lot open.
            It gives you fast tabs, local history, bookmarks, passkeys, and an optional AI
            page assistant without Electron, telemetry, or cloud sync.
          </p>
          <div className="actions">
            <a className="button primary" href={`${repoUrl}/releases`} target="_blank" rel="noreferrer">
              Download for macOS
            </a>
            <a className="button" href={repoUrl} target="_blank" rel="noreferrer">
              GitHub
            </a>
          </div>
        </section>

        <section className="section" id="what">
          <div className="section-head">
            <p>Three moves, one browser</p>
            <span>01 - 03</span>
          </div>
          <div className="steps">
            {steps.map((step) => (
              <article key={step.number}>
                <span>{step.number}</span>
                <h2>{step.title}</h2>
                <p>{step.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="statement">
          <h2>A browser should be quiet, fast, and yours.</h2>
          <p>
            TrailBrowser keeps the everyday browser surface simple: tabs, search,
            bookmarks, downloads, settings, passkeys, history, and page questions.
          </p>
        </section>

        <section className="section" id="how">
          <div className="section-head">
            <p>How it works</p>
            <span>local by default</span>
          </div>
          <div className="how-list">
            {howItWorks.map(([number, title, body]) => (
              <article key={number}>
                <span>{number}</span>
                <div>
                  <h3>{title}</h3>
                  <p>{body}</p>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="build">
          <p>Build it yourself</p>
          <pre><code>{`git clone https://github.com/yug-space/trailbrowser
cd trailbrowser
make
make run-browser`}</code></pre>
        </section>
      </main>

      <footer>
        <a className="brand" href="#top">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/assets/trailbrowser-mark.svg" alt="" />
          <span>TrailBrowser</span>
        </a>
        <nav aria-label="Footer navigation">
          <a href={repoUrl} target="_blank" rel="noreferrer">
            GitHub
          </a>
          <a href={`${repoUrl}/blob/main/docs/BROWSER_FEATURES.md`} target="_blank" rel="noreferrer">
            Features
          </a>
          <a href={`${repoUrl}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noreferrer">
            Contributing
          </a>
        </nav>
        <p>2026 · built on macOS</p>
      </footer>
    </>
  );
}
