const syncButton = document.getElementById("sync-cookies");
const homeButton = document.getElementById("open-home");
const bookmarkBarToggle = document.getElementById("bookmark-bar-toggle");
const engineSelect = document.getElementById("ai-engine");
const modelSelect = document.getElementById("ai-model");
const speedSelect = document.getElementById("codex-speed");
const speedField = document.getElementById("speed-field");
const historyFilter = document.getElementById("history-filter");
const historyList = document.getElementById("history-list");
const historyClusterMeta = document.getElementById("history-cluster-meta");
const clusterHistoryButton = document.getElementById("cluster-history");
const clearHistoryButton = document.getElementById("clear-history");
const bookmarkList = document.getElementById("bookmark-list");
const bookmarkFilter = document.getElementById("bookmark-filter");
const importBookmarksButton = document.getElementById("import-bookmarks");
const exportBookmarksButton = document.getElementById("export-bookmarks");
const downloadList = document.getElementById("download-list");
const clearDownloadsButton = document.getElementById("clear-downloads");
const clearSiteDataButton = document.getElementById("clear-site-data");
const clearAllDataButton = document.getElementById("clear-all-data");
const permissionList = document.getElementById("permission-list");
const permissionFilter = document.getElementById("permission-filter");
const clearPermissionsButton = document.getElementById("clear-permissions");
const settingsNavItems = Array.from(document.querySelectorAll("[data-settings-page]"));
const settingsPages = Array.from(document.querySelectorAll("[data-page]"));
const settingsPageIds = new Set(settingsPages.map((page) => page.dataset.page));

function requestedSettingsPage() {
  const fromHash = window.location.hash.replace(/^#/, "");
  if (settingsPageIds.has(fromHash)) return fromHash;
  const stored = window.localStorage.getItem("tb-settings-page");
  return settingsPageIds.has(stored) ? stored : "general";
}

function showSettingsPage(pageId) {
  const nextPage = settingsPageIds.has(pageId) ? pageId : "general";
  for (const page of settingsPages) {
    page.hidden = page.dataset.page !== nextPage;
  }
  for (const item of settingsNavItems) {
    const active = item.dataset.settingsPage === nextPage;
    item.classList.toggle("active", active);
    if (active) {
      item.setAttribute("aria-current", "page");
    } else {
      item.removeAttribute("aria-current");
    }
  }
  window.localStorage.setItem("tb-settings-page", nextPage);
}

for (const item of settingsNavItems) {
  item.addEventListener("click", () => showSettingsPage(item.dataset.settingsPage));
}

window.addEventListener("hashchange", () => showSettingsPage(requestedSettingsPage()));
showSettingsPage(requestedSettingsPage());

const MODELS = {
  codex: [
    { value: "", label: "Default" },
    { value: "gpt-5-codex", label: "gpt-5-codex" },
    { value: "gpt-5", label: "gpt-5" },
    { value: "gpt-5-mini", label: "gpt-5-mini" },
  ],
  claude: [
    { value: "", label: "Default" },
    { value: "opus", label: "Opus" },
    { value: "sonnet", label: "Sonnet" },
    { value: "haiku", label: "Haiku" },
  ],
};

function storedModel(engine) {
  return engine === "claude" ? (window.__tbClaudeModel || "") : (window.__tbCodexModel || "");
}

function renderModels(engine) {
  modelSelect.innerHTML = "";
  for (const { value, label } of MODELS[engine]) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    modelSelect.appendChild(option);
  }
  modelSelect.value = storedModel(engine);
  speedField.style.display = engine === "codex" ? "" : "none";
}

function setPref(key, value) {
  window.location.href = `trailbrowser://set-pref?key=${encodeURIComponent(key)}&value=${encodeURIComponent(value)}`;
}

const engine = window.__tbEngine || "codex";
engineSelect.value = engine;
renderModels(engine);
speedSelect.value = window.__tbEffort || "minimal";

engineSelect.addEventListener("change", () => {
  setPref("aiEngine", engineSelect.value);
  renderModels(engineSelect.value);
});

modelSelect.addEventListener("change", () => {
  const key = engineSelect.value === "claude" ? "claudeModel" : "codexModel";
  setPref(key, modelSelect.value);
});

speedSelect.addEventListener("change", () => setPref("codexEffort", speedSelect.value));

syncButton.addEventListener("click", () => {
  syncButton.disabled = true;
  syncButton.textContent = "Syncing…";
  window.location.href = "trailbrowser://sync-cookies";
  window.setTimeout(() => {
    syncButton.disabled = false;
    syncButton.textContent = "Sync Chrome Cookies";
  }, 2500);
});

homeButton.addEventListener("click", () => {
  window.location.href = "trailbrowser://home";
});

bookmarkBarToggle.checked = Boolean(window.__tbBookmarkBarVisible);
bookmarkBarToggle.addEventListener("change", () => {
  setPref("bookmarkBar", bookmarkBarToggle.checked ? "1" : "0");
});

const historyEntries = Array.isArray(window.__tbHistory) ? window.__tbHistory : [];
const historyClusterPayload = window.__tbHistoryClusters && typeof window.__tbHistoryClusters === "object"
  ? window.__tbHistoryClusters
  : {};
const bookmarkEntries = Array.isArray(window.__tbBookmarks) ? window.__tbBookmarks : [];
const downloadEntries = Array.isArray(window.__tbDownloads) ? window.__tbDownloads : [];
const permissionEntries = Array.isArray(window.__tbPermissions) ? window.__tbPermissions : [];

function formatTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function openHistoryURL(url) {
  window.location.href = `trailbrowser://open?input=${encodeURIComponent(url)}`;
}

function removeBookmark(url) {
  window.location.href = `trailbrowser://remove-bookmark?url=${encodeURIComponent(url)}`;
}

function updateBookmark(oldUrl, title, newUrl) {
  window.location.href =
    `trailbrowser://update-bookmark?url=${encodeURIComponent(oldUrl)}&title=${encodeURIComponent(title)}&newUrl=${encodeURIComponent(newUrl)}`;
}

function revealDownload(path) {
  window.location.href = `trailbrowser://reveal-download?path=${encodeURIComponent(path)}`;
}

function cancelDownload(id) {
  if (!id) return;
  window.location.href = `trailbrowser://cancel-download?id=${encodeURIComponent(id)}`;
}

function resumeDownload(id) {
  if (!id) return;
  window.location.href = `trailbrowser://resume-download?id=${encodeURIComponent(id)}`;
}

function refreshHistoryClusters() {
  clusterHistoryButton.disabled = true;
  clusterHistoryButton.textContent = "Clustering...";
  window.location.href = "trailbrowser://cluster-history";
  window.setTimeout(() => {
    clusterHistoryButton.disabled = false;
    clusterHistoryButton.textContent = "Refresh AI Clusters";
  }, 3500);
}

function setPermission(origin, kind, value) {
  window.location.href =
    `trailbrowser://set-permission?origin=${encodeURIComponent(origin)}&kind=${encodeURIComponent(kind)}&value=${encodeURIComponent(value)}`;
}

function permissionSelect(origin, kind, value) {
  const select = document.createElement("select");
  select.className = "permission-select";
  select.setAttribute("aria-label", `${kind} permission for ${origin}`);
  for (const option of [
    { value: "ask", label: "Ask" },
    { value: "allow", label: "Allow" },
    { value: "deny", label: "Block" },
  ]) {
    const item = document.createElement("option");
    item.value = option.value;
    item.textContent = option.label;
    select.appendChild(item);
  }
  select.value = value || "ask";
  select.addEventListener("change", () => setPermission(origin, kind, select.value));
  return select;
}

function renderPermissions() {
  const filter = permissionFilter.value.trim().toLowerCase();
  const matches = permissionEntries.filter((entry) => {
    if (!filter) return true;
    return `${entry.origin || ""}`.toLowerCase().includes(filter);
  });

  permissionList.innerHTML = "";
  if (matches.length === 0) {
    const empty = document.createElement("div");
    empty.className = "history-empty";
    empty.textContent = permissionEntries.length === 0 ? "No saved site permissions." : "No matching permissions.";
    permissionList.appendChild(empty);
    return;
  }

  for (const entry of matches) {
    const item = document.createElement("div");
    item.className = "history-item permission-item";

    const time = document.createElement("div");
    time.className = "history-time";
    time.textContent = formatTime(entry.updatedAt) || "Saved";

    const text = document.createElement("div");
    const origin = document.createElement("div");
    origin.className = "history-title";
    origin.textContent = entry.origin;
    const detail = document.createElement("div");
    detail.className = "history-url";
    detail.textContent = "Camera and microphone";
    text.append(origin, detail);

    const controls = document.createElement("div");
    controls.className = "permission-controls";
    const cameraLabel = document.createElement("label");
    cameraLabel.textContent = "Camera";
    cameraLabel.appendChild(permissionSelect(entry.origin, "camera", entry.camera));
    const microphoneLabel = document.createElement("label");
    microphoneLabel.textContent = "Mic";
    microphoneLabel.appendChild(permissionSelect(entry.origin, "microphone", entry.microphone));
    controls.append(cameraLabel, microphoneLabel);

    item.append(time, text, controls);
    permissionList.appendChild(item);
  }
}

function renderBookmarks() {
  const filter = bookmarkFilter.value.trim().toLowerCase();
  const matches = bookmarkEntries.filter((entry) => {
    if (!filter) return true;
    return `${entry.title || ""} ${entry.url || ""} ${entry.host || ""}`.toLowerCase().includes(filter);
  });

  bookmarkList.innerHTML = "";
  if (matches.length === 0) {
    const empty = document.createElement("div");
    empty.className = "history-empty";
    empty.textContent = bookmarkEntries.length === 0 ? "No bookmarks yet." : "No matching bookmarks.";
    bookmarkList.appendChild(empty);
    return;
  }

  for (const entry of matches) {
    const item = document.createElement("div");
    item.className = "history-item bookmark-item";

    const meta = document.createElement("div");
    meta.className = "history-time";
    meta.textContent = entry.host || "Saved";

    const link = document.createElement("a");
    link.className = "bookmark-link";
    link.href = entry.url;
    link.addEventListener("click", (event) => {
      event.preventDefault();
      openHistoryURL(entry.url);
    });

    const title = document.createElement("div");
    title.className = "history-title";
    title.textContent = entry.title || entry.host || entry.url;

    const url = document.createElement("div");
    url.className = "history-url";
    url.textContent = entry.url;
    link.append(title, url);

    const remove = document.createElement("button");
    remove.className = "bookmark-remove";
    remove.type = "button";
    remove.textContent = "Remove";
    remove.addEventListener("click", () => removeBookmark(entry.url));

    const edit = document.createElement("button");
    edit.className = "bookmark-remove neutral";
    edit.type = "button";
    edit.textContent = "Edit";
    edit.addEventListener("click", () => {
      const nextTitle = window.prompt("Bookmark title", entry.title || entry.host || entry.url);
      if (nextTitle === null) return;
      const nextUrl = window.prompt("Bookmark URL", entry.url);
      if (nextUrl === null || nextUrl.trim() === "") return;
      updateBookmark(entry.url, nextTitle.trim(), nextUrl.trim());
    });

    const actions = document.createElement("div");
    actions.className = "row-actions";
    actions.append(edit, remove);
    item.append(meta, link, actions);
    bookmarkList.appendChild(item);
  }
}

function renderDownloads() {
  downloadList.innerHTML = "";
  if (downloadEntries.length === 0) {
    const empty = document.createElement("div");
    empty.className = "history-empty";
    empty.textContent = "No downloads yet.";
    downloadList.appendChild(empty);
    return;
  }

  for (const entry of downloadEntries) {
    const item = document.createElement("div");
    item.className = "history-item bookmark-item";
    if (entry.active) item.classList.add("download-active");

    const time = document.createElement("div");
    time.className = "history-time";
    time.textContent = entry.active ? "Active" : (formatTime(entry.timestamp) || entry.status || "Saved");

    const text = document.createElement("div");
    const title = document.createElement("div");
    title.className = "history-title";
    title.textContent = entry.filename || entry.path || "download";

    const detail = document.createElement("div");
    detail.className = "history-url";
    detail.textContent = entry.active
      ? (entry.progressText || "Downloading")
      : entry.status === "canceled"
      ? (entry.error || "Canceled")
      : entry.status === "failed"
      ? (entry.error || "Download failed")
      : (entry.path || entry.status || "");
    text.append(title, detail);

    if (entry.active) {
      const progress = document.createElement("div");
      progress.className = "download-progress";
      if (entry.progressIndeterminate) progress.classList.add("indeterminate");
      const fill = document.createElement("div");
      fill.className = "download-progress-fill";
      const pct = Math.max(0, Math.min(100, Number(entry.progress || 0) * 100));
      fill.style.width = entry.progressIndeterminate ? "36%" : `${pct}%`;
      progress.appendChild(fill);
      text.appendChild(progress);
    }

    const actions = document.createElement("div");
    actions.className = "row-actions download-actions";

    if (entry.active) {
      const cancel = document.createElement("button");
      cancel.className = "bookmark-remove";
      cancel.type = "button";
      cancel.textContent = entry.status === "canceling" ? "Canceling" : "Cancel";
      cancel.disabled = !entry.id || entry.status === "canceling";
      cancel.addEventListener("click", () => cancelDownload(entry.id));
      actions.appendChild(cancel);
    } else if (entry.resumeDataPath && entry.id) {
      const resume = document.createElement("button");
      resume.className = "bookmark-remove neutral";
      resume.type = "button";
      resume.textContent = "Resume";
      resume.addEventListener("click", () => resumeDownload(entry.id));
      actions.appendChild(resume);
    }

    const reveal = document.createElement("button");
    reveal.className = "bookmark-remove neutral";
    reveal.type = "button";
    reveal.textContent = "Reveal";
    reveal.disabled = !entry.path || entry.active || entry.status === "failed" || entry.status === "canceled";
    reveal.addEventListener("click", () => revealDownload(entry.path));
    actions.appendChild(reveal);

    item.append(time, text, actions);
    downloadList.appendChild(item);
  }
}

function renderHistory() {
  const filter = historyFilter.value.trim().toLowerCase();
  const entriesByURL = new Map(historyEntries.map((entry) => [entry.url, entry]));
  const clusters = historyClustersForEntries(historyEntries, entriesByURL);
  const matchesFilter = (entry) => {
    if (!filter) return true;
    return `${entry.title || ""} ${entry.url || ""} ${entry.host || ""}`.toLowerCase().includes(filter);
  };

  historyList.innerHTML = "";
  const visibleClusters = clusters
    .map((cluster) => ({
      ...cluster,
      entries: cluster.entries.filter(matchesFilter),
    }))
    .filter((cluster) => cluster.entries.length > 0);

  if (visibleClusters.length === 0) {
    const empty = document.createElement("div");
    empty.className = "history-empty";
    empty.textContent = historyEntries.length === 0 ? "No history yet." : "No matching history.";
    historyList.appendChild(empty);
    historyClusterMeta.textContent = "";
    return;
  }

  const source = historyClusterPayload.source === "ai" ? "AI" : "Local";
  const updated = historyClusterPayload.updatedAt ? ` • ${formatTime(historyClusterPayload.updatedAt)}` : "";
  historyClusterMeta.textContent = `${source} clusters • ${historyEntries.length} visits${updated}`;

  for (const cluster of visibleClusters) {
    const card = document.createElement("section");
    card.className = "history-cluster";

    const head = document.createElement("div");
    head.className = "history-cluster-head";
    const title = document.createElement("div");
    title.className = "history-cluster-title";
    title.textContent = cluster.label;
    const count = document.createElement("div");
    count.className = "history-cluster-count";
    count.textContent = `${cluster.entries.length}`;
    head.append(title, count);

    const reason = document.createElement("div");
    reason.className = "history-cluster-reason";
    reason.textContent = cluster.reason || "Grouped by topic and browsing intent.";

    const list = document.createElement("div");
    list.className = "history-cluster-list";

    for (const entry of cluster.entries.slice(0, 8)) {
      const item = historyItemForEntry(entry);
      list.appendChild(item);
    }

    card.append(head, reason, list);
    historyList.appendChild(card);
  }
}

function historyItemForEntry(entry) {
  const item = document.createElement("a");
  item.className = "history-item compact-history-item";
  item.href = entry.url;
  item.addEventListener("click", (event) => {
    event.preventDefault();
    openHistoryURL(entry.url);
  });

  const time = document.createElement("div");
  time.className = "history-time";
  time.textContent = formatTime(entry.timestamp);

  const text = document.createElement("div");
  const title = document.createElement("div");
  title.className = "history-title";
  title.textContent = entry.title || entry.host || entry.url;
  const url = document.createElement("div");
  url.className = "history-url";
  url.textContent = entry.url;
  text.append(title, url);
  item.append(time, text);
  return item;
}

function historyClustersForEntries(entries, entriesByURL) {
  const aiClusters = Array.isArray(historyClusterPayload.clusters)
    ? historyClusterPayload.clusters.map((cluster) => {
        const clusterEntries = Array.isArray(cluster.urls)
          ? cluster.urls.map((url) => entriesByURL.get(url)).filter(Boolean)
          : [];
        return {
          label: cluster.label || "AI cluster",
          reason: cluster.reason || "AI grouped these pages by topic.",
          entries: clusterEntries,
        };
      }).filter((cluster) => cluster.entries.length > 0)
    : [];
  if (aiClusters.length > 0) return withUnclustered(entries, aiClusters);
  return localHistoryClusters(entries);
}

function withUnclustered(entries, clusters) {
  const used = new Set();
  for (const cluster of clusters) {
    for (const entry of cluster.entries) used.add(entry.url);
  }
  const remaining = entries.filter((entry) => !used.has(entry.url));
  if (remaining.length > 0) {
    clusters.push({
      label: "Recent",
      reason: "Not included in the latest AI grouping.",
      entries: remaining,
    });
  }
  return clusters;
}

function localHistoryClusters(entries) {
  const rules = [
    { label: "Searches", terms: ["google.com/search", "search?", "q="], reason: "Search result and query pages." },
    { label: "Video", terms: ["youtube.com", "vimeo.com", "video"], reason: "Video and media sessions." },
    { label: "Code", terms: ["github.com", "stackoverflow.com", "docs.", "developer.", "npmjs.com"], reason: "Development references and repositories." },
    { label: "AI", terms: ["openai", "chatgpt", "claude", "anthropic", "codex"], reason: "AI tools, models, and assistant work." },
    { label: "Local", terms: ["localhost", "127.0.0.1", "trailbrowser://"], reason: "Local apps and internal TrailBrowser pages." },
  ];
  const buckets = rules.map((rule) => ({ ...rule, entries: [] }));
  const other = { label: "Recent", reason: "Recent pages that do not match a stronger topic.", entries: [] };

  for (const entry of entries) {
    const haystack = `${entry.title || ""} ${entry.url || ""} ${entry.host || ""}`.toLowerCase();
    const bucket = buckets.find((candidate) => candidate.terms.some((term) => haystack.includes(term)));
    (bucket || other).entries.push(entry);
  }

  return [...buckets, other].filter((bucket) => bucket.entries.length > 0);
}

historyFilter.addEventListener("input", renderHistory);
bookmarkFilter.addEventListener("input", renderBookmarks);
permissionFilter.addEventListener("input", renderPermissions);
clusterHistoryButton.addEventListener("click", refreshHistoryClusters);

importBookmarksButton.addEventListener("click", () => {
  window.location.href = "trailbrowser://import-bookmarks";
});

exportBookmarksButton.addEventListener("click", () => {
  window.location.href = "trailbrowser://export-bookmarks";
});

clearHistoryButton.addEventListener("click", () => {
  if (!window.confirm("Clear TrailBrowser history on this Mac?")) return;
  window.location.href = "trailbrowser://clear-history";
});

clearDownloadsButton.addEventListener("click", () => {
  if (!window.confirm("Clear TrailBrowser download history on this Mac? Files stay in Downloads.")) return;
  window.location.href = "trailbrowser://clear-downloads";
});

clearSiteDataButton.addEventListener("click", () => {
  if (!window.confirm("Clear cookies, cache, local storage, and other website data from TrailBrowser?")) return;
  window.location.href = "trailbrowser://clear-website-data";
});

clearAllDataButton.addEventListener("click", () => {
  if (!window.confirm("Clear history, searches, download history, site permissions, cookies, cache, and website storage? Bookmarks stay saved.")) return;
  window.location.href = "trailbrowser://clear-all-browsing-data";
});

clearPermissionsButton.addEventListener("click", () => {
  if (!window.confirm("Clear saved camera and microphone decisions?")) return;
  window.location.href = "trailbrowser://clear-permissions";
});

renderPermissions();
renderBookmarks();
renderDownloads();
renderHistory();
