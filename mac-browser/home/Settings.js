const syncButton = document.getElementById("sync-cookies");
const homeButton = document.getElementById("open-home");

syncButton.addEventListener("click", () => {
  // Hand off to the native app, which runs the Chrome cookie importer.
  syncButton.disabled = true;
  syncButton.textContent = "Syncing…";
  window.location.href = "trailbrowser://sync-cookies";
  // The native importer shows its own result alert; re-enable shortly after.
  window.setTimeout(() => {
    syncButton.disabled = false;
    syncButton.textContent = "Sync Chrome Cookies";
  }, 2500);
});

homeButton.addEventListener("click", () => {
  window.location.href = "trailbrowser://home";
});
