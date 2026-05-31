const syncButton = document.getElementById("sync-cookies");
const homeButton = document.getElementById("open-home");
const modelSelect = document.getElementById("codex-model");
const speedSelect = document.getElementById("codex-speed");

modelSelect.value = window.__tbModel || "";
speedSelect.value = window.__tbEffort || "medium";

function setPref(key, value) {
  window.location.href = `trailbrowser://set-pref?key=${encodeURIComponent(key)}&value=${encodeURIComponent(value)}`;
}

modelSelect.addEventListener("change", () => setPref("codexModel", modelSelect.value));
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
