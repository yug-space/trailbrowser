const syncButton = document.getElementById("sync-cookies");
const homeButton = document.getElementById("open-home");
const engineSelect = document.getElementById("ai-engine");
const modelSelect = document.getElementById("ai-model");
const speedSelect = document.getElementById("codex-speed");
const speedField = document.getElementById("speed-field");

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
