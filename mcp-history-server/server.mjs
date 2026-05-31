#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

function defaultSupportDir() {
  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", "TrailBrowser");
  }

  const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share");
  return path.join(dataHome, "trailbrowser");
}

const DEFAULT_SUPPORT_DIR = defaultSupportDir();
const HISTORY_FILE = process.env.TRAILBROWSER_HISTORY_FILE ||
  path.join(DEFAULT_SUPPORT_DIR, "history.jsonl");
const STATE_FILE = process.env.TRAILBROWSER_STATE_FILE ||
  path.join(DEFAULT_SUPPORT_DIR, "state.json");

const MAX_LIMIT = 200;
const SENSITIVE_QUERY_NAMES = [
  "token",
  "secret",
  "password",
  "passwd",
  "pass",
  "auth",
  "session",
  "sid",
  "key",
  "credential",
  "code",
];

function clampLimit(limit, fallback = 25) {
  if (!Number.isFinite(limit)) return fallback;
  return Math.max(1, Math.min(MAX_LIMIT, Math.trunc(limit)));
}

function readHistory() {
  if (!fs.existsSync(HISTORY_FILE)) return [];

  const lines = fs.readFileSync(HISTORY_FILE, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  const entries = [];
  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      if (entry && typeof entry.url === "string") {
        entries.push(normalizeEntry(entry));
      }
    } catch {
      // Ignore malformed partial lines from an interrupted write.
    }
  }

  return entries;
}

function normalizeEntry(entry) {
  const redactedUrl = redactUrl(entry.url);
  return {
    timestamp: String(entry.timestamp || ""),
    title: String(entry.title || ""),
    url: redactedUrl,
    host: String(entry.host || hostFromUrl(redactedUrl) || ""),
    source: "TrailBrowser",
  };
}

function hostFromUrl(value) {
  try {
    return new URL(value).host;
  } catch {
    return "";
  }
}

function redactUrl(value) {
  try {
    const url = new URL(value);

    // Query string.
    for (const [name] of url.searchParams) {
      if (isSensitiveQueryName(name)) {
        url.searchParams.set(name, "[redacted]");
      }
    }

    // Credentials embedded in the URL (https://user:pass@host).
    if (url.username) url.username = "[redacted]";
    if (url.password) url.password = "[redacted]";

    // Fragment: tokens often ride in the hash (OAuth implicit flow, #access_token=…).
    if (url.hash.length > 1) {
      const frag = new URLSearchParams(url.hash.slice(1));
      let changed = false;
      for (const [name] of frag) {
        if (isSensitiveQueryName(name)) {
          frag.set(name, "[redacted]");
          changed = true;
        }
      }
      if (changed) url.hash = `#${frag.toString()}`;
    }

    return url.toString();
  } catch {
    return String(value || "");
  }
}

function isSensitiveQueryName(name) {
  const lower = String(name || "").toLowerCase();
  return SENSITIVE_QUERY_NAMES.some((marker) => lower.includes(marker));
}

function latestFirst(entries) {
  return [...entries].sort((a, b) => String(b.timestamp).localeCompare(String(a.timestamp)));
}

function jsonText(value) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(value, null, 2),
      },
    ],
  };
}

function readState() {
  let state = {};
  if (fs.existsSync(STATE_FILE)) {
    try {
      state = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    } catch {
      state = {};
    }
  }

  return {
    running: isTrailBrowserRunning(),
    appStateFileRunning: Boolean(state.running),
    appStateUpdatedAt: state.updatedAt || null,
    historyFile: HISTORY_FILE,
    stateFile: STATE_FILE,
    cookiesExposed: false,
  };
}

function isTrailBrowserRunning() {
  for (const processName of ["TrailBrowser", "trailbrowser"]) {
    try {
      execFileSync("pgrep", ["-x", processName], { stdio: "ignore" });
      return true;
    } catch {
      // Try the next platform-specific binary name.
    }
  }
  return false;
}

const server = new McpServer({
  name: "trailbrowser-history",
  version: "1.0.0",
});

server.tool(
  "browser_status",
  "Report TrailBrowser runtime status and history file location. Cookies are never exposed.",
  {},
  async () => jsonText(readState()),
);

server.tool(
  "history_recent",
  "Return recent TrailBrowser history entries from the local history file.",
  {
    limit: z.number().int().min(1).max(MAX_LIMIT).optional(),
  },
  async ({ limit }) => {
    const entries = latestFirst(readHistory()).slice(0, clampLimit(limit));
    return jsonText({ count: entries.length, entries });
  },
);

server.tool(
  "history_search",
  "Search TrailBrowser history by URL, title, or host.",
  {
    query: z.string().min(1),
    limit: z.number().int().min(1).max(MAX_LIMIT).optional(),
  },
  async ({ query, limit }) => {
    const needle = query.toLowerCase();
    const entries = latestFirst(readHistory())
      .filter((entry) => {
        return entry.url.toLowerCase().includes(needle) ||
          entry.title.toLowerCase().includes(needle) ||
          entry.host.toLowerCase().includes(needle);
      })
      .slice(0, clampLimit(limit));

    return jsonText({ query, count: entries.length, entries });
  },
);

server.tool(
  "history_by_domain",
  "Return TrailBrowser history entries for one host/domain.",
  {
    domain: z.string().min(1),
    limit: z.number().int().min(1).max(MAX_LIMIT).optional(),
  },
  async ({ domain, limit }) => {
    const needle = domain.toLowerCase();
    const entries = latestFirst(readHistory())
      .filter((entry) => entry.host.toLowerCase() === needle ||
        entry.host.toLowerCase().endsWith(`.${needle}`))
      .slice(0, clampLimit(limit));

    return jsonText({ domain, count: entries.length, entries });
  },
);

server.tool(
  "history_top_domains",
  "Return the most frequently visited domains in TrailBrowser history.",
  {
    limit: z.number().int().min(1).max(100).optional(),
  },
  async ({ limit }) => {
    const counts = new Map();
    for (const entry of readHistory()) {
      if (!entry.host) continue;
      counts.set(entry.host, (counts.get(entry.host) || 0) + 1);
    }

    const domains = [...counts.entries()]
      .map(([domain, visits]) => ({ domain, visits }))
      .sort((a, b) => b.visits - a.visits || a.domain.localeCompare(b.domain))
      .slice(0, clampLimit(limit, 20));

    return jsonText({ count: domains.length, domains });
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
