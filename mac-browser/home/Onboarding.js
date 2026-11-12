const syncButton = document.getElementById("sync-cookies");
const getStarted = document.getElementById("get-started");
const skip = document.getElementById("skip");

syncButton.addEventListener("click", () => {
  syncButton.disabled = true;
  syncButton.textContent = "Syncing…";
  window.location.href = "trailbrowser://sync-cookies";
  window.setTimeout(() => {
    syncButton.disabled = false;
    syncButton.textContent = "Sync Chrome Cookies";
  }, 2500);
});

function finish() {
  window.location.href = "trailbrowser://home";
}

getStarted.addEventListener("click", finish);
skip.addEventListener("click", finish);
