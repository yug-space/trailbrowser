const form = document.getElementById("search-form");
const query = document.getElementById("query");
const submit = document.getElementById("submit");
const segButtons = Array.from(document.querySelectorAll(".seg-btn"));

let mode = "google";

function currentValue() {
  return query.value.trim();
}

function refreshSubmitState() {
  submit.disabled = currentValue().length === 0;
}

function autoGrow() {
  query.style.height = "auto";
  query.style.height = `${query.scrollHeight}px`;
}

function openInput(value = currentValue()) {
  if (!value) return;
  window.location.href = `trailbrowser://open?input=${encodeURIComponent(value)}`;
}

function deepSearch(value = currentValue()) {
  if (!value) return;
  window.location.href = `trailbrowser://deep-search?q=${encodeURIComponent(value)}`;
}

function run() {
  if (mode === "ai") {
    deepSearch();
  } else {
    openInput();
  }
}

function setMode(next) {
  mode = next;
  segButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.mode === next);
  });
  query.focus();
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  run();
});

segButtons.forEach((button) => {
  button.addEventListener("click", () => setMode(button.dataset.mode));
});

query.addEventListener("input", () => {
  autoGrow();
  refreshSubmitState();
});

query.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    run();
  }
});

document.querySelectorAll("[data-open]").forEach((button) => {
  button.addEventListener("click", () => openInput(button.dataset.open));
});

autoGrow();
refreshSubmitState();
query.focus();
