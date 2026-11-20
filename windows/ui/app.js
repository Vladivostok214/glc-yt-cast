const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const card = document.getElementById("popover-card");
const statusLabel = document.getElementById("status-label");
const connectToggle = document.getElementById("connect-toggle");
const btnSettings = document.getElementById("btn-settings");
const btnClose = document.getElementById("btn-close");

const ipPanel = document.getElementById("ip-panel");
const ipInput = document.getElementById("ip-input");
const btnSaveIp = document.getElementById("btn-save-ip");

const bodyPanel = document.getElementById("body-panel");
const searchInput = document.getElementById("search-input");
const btnSearch = document.getElementById("btn-search");
const btnClear = document.getElementById("btn-clear");
const navPanel = document.getElementById("nav-panel");

let isConnected = false;
let isInternalToggle = false;
let lastSearchTime = 0;
const SEARCH_COOLDOWN_MS = 650;

function syncWindowHeight() {
  requestAnimationFrame(() => {
    const h = Math.ceil(card.getBoundingClientRect().height) + 20;
    invoke("set_popover_height", { height: h }).catch(() => {});
  });
}

function setStatus(text, cls = "") {
  statusLabel.textContent = text;
  statusLabel.className = "status-label" + (cls ? " " + cls : "");
}

function setConnectedUI(connected, ip = null) {
  isConnected = connected;
  isInternalToggle = true;
  connectToggle.checked = connected;
  isInternalToggle = false;

  if (connected) {
    setStatus("En línea", "status-online");
    if (ip) ipInput.value = ip;
    ipPanel.classList.remove("open");
    bodyPanel.classList.add("open");
    syncWindowHeight();
    setTimeout(() => searchInput.focus(), 40);
  } else {
    bodyPanel.classList.remove("open");
    navPanel.classList.remove("open");
    syncWindowHeight();
  }
}

async function doConnect(forceIp = null) {
  setStatus(forceIp ? `Conectando a ${forceIp}...` : "Conectando...", "status-connecting");
  try {
    const ip = await invoke("connect_tv", { forceIp });
    setConnectedUI(true, ip);
  } catch (_) {
    setConnectedUI(false);
    setStatus("Sin conexión (⚙️)");
  }
}

connectToggle.addEventListener("change", async () => {
  if (isInternalToggle) return;
  if (connectToggle.checked) {
    await doConnect(null);
  } else {
    await invoke("disconnect_tv");
    setConnectedUI(false);
    setStatus("Desconectado");
    setTimeout(() => invoke("hide_popover"), 220);
  }
});

btnSettings.addEventListener("click", () => {
  const isOpen = ipPanel.classList.toggle("open");
  syncWindowHeight();
  if (isOpen) {
    setTimeout(() => ipInput.focus(), 40);
  }
});

btnSaveIp.addEventListener("click", async () => {
  const newIp = ipInput.value.trim();
  if (!newIp) return;
  ipPanel.classList.remove("open");
  syncWindowHeight();
  await doConnect(newIp);
});

ipInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    btnSaveIp.click();
  }
});

btnClose.addEventListener("click", () => {
  invoke("hide_popover");
});

function submitSearch() {
  const text = searchInput.value.trim();
  if (!text) return;
  lastSearchTime = Date.now();
  invoke("cast_query", { query: text });
  navPanel.classList.add("open");
  syncWindowHeight();
  searchInput.blur();
}

btnSearch.addEventListener("click", submitSearch);

searchInput.addEventListener("input", () => {
  btnClear.classList.toggle("hidden", !searchInput.value);
});

btnClear.addEventListener("click", () => {
  searchInput.value = "";
  btnClear.classList.add("hidden");
  searchInput.focus();
});

searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    submitSearch();
  } else if (e.key === "ArrowUp" || e.key === "ArrowDown") {
    e.preventDefault();
    searchInput.blur();
    sendDpad(e.key === "ArrowUp" ? 19 : 20);
  }
});

function sendDpad(keycode) {
  if (!isConnected) return;
  if ((keycode === 23 || keycode === 66) && Date.now() - lastSearchTime < SEARCH_COOLDOWN_MS) {
    return;
  }
  invoke("send_dpad_key", { keycode });
}

document.querySelectorAll(".nav-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    const code = Number(btn.dataset.key);
    sendDpad(code);
  });
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (ipPanel.classList.contains("open")) {
      ipPanel.classList.remove("open");
      syncWindowHeight();
    } else {
      invoke("hide_popover");
    }
    return;
  }

  const activeTag = document.activeElement?.tagName;
  if (activeTag === "INPUT") return;

  if (!isConnected) return;

  switch (e.key) {
    case "Enter":
      e.preventDefault();
      sendDpad(23);
      break;
    case "ArrowUp":
      e.preventDefault();
      sendDpad(19);
      break;
    case "ArrowDown":
      e.preventDefault();
      sendDpad(20);
      break;
    case "ArrowLeft":
      e.preventDefault();
      sendDpad(21);
      break;
    case "ArrowRight":
      e.preventDefault();
      sendDpad(22);
      break;
    case "Backspace":
      e.preventDefault();
      sendDpad(4);
      break;
  }
});

listen("open-ip-config", () => {
  ipPanel.classList.add("open");
  syncWindowHeight();
  setTimeout(() => ipInput.focus(), 50);
});

// Inicializar estado al abrir
(async () => {
  try {
    const [connected, savedIp] = await invoke("get_connection_state");
    if (savedIp) ipInput.value = savedIp;
    setConnectedUI(connected, savedIp);
    if (!connected) setStatus("Desconectado");
  } catch (_) {
    syncWindowHeight();
  }
})();
