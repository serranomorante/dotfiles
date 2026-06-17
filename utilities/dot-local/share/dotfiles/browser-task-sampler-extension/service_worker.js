"use strict";

const ENDPOINT = "http://127.0.0.1:17643/v1/browser-task-snapshot";
const SCHEMA = "dotfiles.browser-task-sampler.v1";
const MIN_POST_INTERVAL_MS = 900;
const MAX_PROCESSES = 32;
const MAX_TAB_LOOKUPS = 48;

let lastPostAt = 0;

function nowISO() {
  return new Date().toISOString();
}

function trimText(value, limit) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  if (text.length <= limit) {
    return text;
  }
  return text.slice(0, Math.max(0, limit - 1)) + "...";
}

function sanitizeURL(value) {
  const text = String(value || "");
  if (!text) {
    return "";
  }
  try {
    const parsed = new URL(text);
    parsed.search = "";
    parsed.hash = "";
    return parsed.toString();
  } catch (_error) {
    return trimText(text, 220);
  }
}

async function detectBrowser() {
  try {
    if (self.navigator && self.navigator.brave && await self.navigator.brave.isBrave()) {
      return "brave";
    }
  } catch (_error) {
    // Brave exposes navigator.brave in normal pages; extension workers may not.
  }
  const userAgent = (self.navigator && self.navigator.userAgent) || "";
  if (/Brave/i.test(userAgent)) {
    return "brave";
  }
  if (/Chromium|Chrome/i.test(userAgent)) {
    return "chromium";
  }
  return "unknown";
}

async function getTab(tabId) {
  if (!chrome.tabs || typeof chrome.tabs.get !== "function") {
    return null;
  }
  try {
    return await chrome.tabs.get(tabId);
  } catch (_error) {
    return null;
  }
}

async function collectTabs(processes) {
  const tabIds = [];
  const seen = new Set();
  for (const process of Object.values(processes || {})) {
    for (const task of process.tasks || []) {
      if (typeof task.tabId !== "number" || seen.has(task.tabId)) {
        continue;
      }
      seen.add(task.tabId);
      tabIds.push(task.tabId);
      if (tabIds.length >= MAX_TAB_LOOKUPS) {
        break;
      }
    }
    if (tabIds.length >= MAX_TAB_LOOKUPS) {
      break;
    }
  }

  const tabs = new Map();
  await Promise.all(tabIds.map(async (tabId) => {
    const tab = await getTab(tabId);
    if (tab) {
      tabs.set(tabId, tab);
    }
  }));
  return tabs;
}

function normalizeTask(task) {
  return {
    tab_id: typeof task.tabId === "number" ? task.tabId : undefined,
    title: trimText(task.title, 160),
  };
}

function normalizeTab(task, tab) {
  return {
    tab_id: typeof task.tabId === "number" ? task.tabId : undefined,
    title: trimText((tab && tab.title) || task.title, 160),
    url: sanitizeURL(tab && tab.url),
    active: Boolean(tab && tab.active),
    audible: Boolean(tab && tab.audible),
    discarded: Boolean(tab && tab.discarded),
    pinned: Boolean(tab && tab.pinned),
    window_id: tab && typeof tab.windowId === "number" ? tab.windowId : undefined,
  };
}

function normalizeProcess(process, tabsById) {
  const tasks = (process.tasks || []).map(normalizeTask);
  const tabs = [];
  const seenTabs = new Set();
  for (const task of process.tasks || []) {
    if (typeof task.tabId !== "number" || seenTabs.has(task.tabId)) {
      continue;
    }
    seenTabs.add(task.tabId);
    tabs.push(normalizeTab(task, tabsById.get(task.tabId)));
  }
  return {
    id: Number(process.id) || 0,
    os_process_id: Number(process.osProcessId) || 0,
    type: String(process.type || ""),
    cpu_pct: Number(process.cpu) || 0,
    network_bps: Number(process.network) || 0,
    profile: trimText(process.profile, 80),
    tasks,
    tabs,
  };
}

async function postSnapshot(snapshot) {
  try {
    await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(snapshot),
    });
  } catch (_error) {
    // The local receiver may not be running yet; the next process update retries.
  }
}

async function publishStatus(status, reason) {
  await postSnapshot({
    schema: SCHEMA,
    status,
    reason: trimText(reason, 200),
    browser: await detectBrowser(),
    extension_id: chrome.runtime.id,
    captured_at: nowISO(),
    captured_at_unix_ms: Date.now(),
    user_agent: (self.navigator && self.navigator.userAgent) || "",
    processes: [],
  });
}

async function publishProcesses(processes) {
  const current = Date.now();
  if (current - lastPostAt < MIN_POST_INTERVAL_MS) {
    return;
  }
  lastPostAt = current;

  const tabsById = await collectTabs(processes);
  const normalized = Object.values(processes || {})
    .map((process) => normalizeProcess(process, tabsById))
    .sort((left, right) => right.cpu_pct - left.cpu_pct)
    .slice(0, MAX_PROCESSES);

  await postSnapshot({
    schema: SCHEMA,
    status: "ok",
    browser: await detectBrowser(),
    extension_id: chrome.runtime.id,
    captured_at: nowISO(),
    captured_at_unix_ms: current,
    user_agent: (self.navigator && self.navigator.userAgent) || "",
    processes: normalized,
  });
}

if (chrome.processes && chrome.processes.onUpdated) {
  chrome.processes.onUpdated.addListener((processes) => {
    void publishProcesses(processes);
  });
} else {
  void publishStatus("processes-unavailable", "chrome.processes API is not exposed by this browser build");
}

chrome.runtime.onInstalled.addListener(() => {
  void publishStatus(
    chrome.processes && chrome.processes.onUpdated ? "installed" : "processes-unavailable",
    ""
  );
});

chrome.runtime.onStartup.addListener(() => {
  void publishStatus(
    chrome.processes && chrome.processes.onUpdated ? "started" : "processes-unavailable",
    ""
  );
});
