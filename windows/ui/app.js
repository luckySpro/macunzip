// MacUnZip Windows 版界面。所有文件操作都在 Rust 端完成，这里只负责交互。
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const $ = (id) => document.getElementById(id);

const THEMES = [
  ["system", "跟随系统", "#0a84ff"], ["blue", "经典蓝", "#007aff"], ["graphite", "石墨", "#737882"],
  ["green", "森林绿", "#2e9e5c"], ["teal", "湖水青", "#149ea8"], ["orange", "珊瑚橙", "#fa7845"],
  ["red", "玫瑰红", "#e6476b"], ["purple", "葡萄紫", "#8f5cd9"],
];
const EXT = { zip: ".zip", "seven-z": ".7z", "tar-gz": ".tar.gz", "tar-zst": ".tar.zst" };
const ICON = {
  folder: '<svg viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
  here: '<svg viewBox="0 0 24 24"><path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-3"/></svg>',
  plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
  extract: '<svg viewBox="0 0 24 24"><path d="M3 7h18v4H3zM5 11h14v9H5zM10 14h4"/></svg>',
  compress: '<svg viewBox="0 0 24 24"><path d="M7 3h7l4 4v14H7zM12 6v2m0 2v2m0 2v2"/></svg>',
};

let settings = null;
let mode = "extract";
let selected = null; // 当前选中的目录 id；null 表示原位置
let pending = [];
let compressFiles = [];
let passwordRequest = null;

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const save = () => invoke("save_settings", { settings });

function applyTheme() {
  const theme = THEMES.find((t) => t[0] === settings.theme) || THEMES[0];
  document.documentElement.style.setProperty("--accent", theme[2]);
}

// ---- 主界面 ----

function render() {
  document.querySelectorAll(".mode button").forEach((b) => b.classList.toggle("on", b.dataset.mode === mode));
  const extract = mode === "extract";
  $("drop-title").textContent = extract ? "将压缩包拖到这里" : "将要压缩的文件拖到这里";
  $("drop-icon").outerHTML = (extract ? ICON.extract : ICON.compress).replace("<svg", '<svg id="drop-icon"');
  $("formats").hidden = !extract;
  $("dest-label").textContent = extract ? "解压到" : "保存到";
  $("extract-toggles").hidden = !extract;
  $("drop-idle").hidden = pending.length > 0;
  $("drop-pending").hidden = pending.length === 0;
  $("pending-title").textContent = `${pending.length} 个压缩包待解压`;
  $("reveal-after").checked = settings.reveal_after;
  $("delete-after").checked = settings.delete_after_extract;
  renderChips();
}

function defaultId() {
  return mode === "extract" ? settings.default_folder : settings.compress.destination;
}

function renderChips() {
  const def = defaultId();
  const chip = (id, name, icon) => `
    <button class="chip ${selected === id ? "on" : ""}" data-id="${id ?? ""}">
      ${icon}<span>${esc(name)}</span>${def === id ? '<span class="star">★</span>' : ""}
    </button>`;
  $("chips").innerHTML =
    chip(null, "原位置", ICON.here) +
    settings.favorites.map((f) => chip(f.id, f.name, ICON.folder)).join("") +
    `<button class="chip add" id="add-chip">${ICON.plus}<span>添加</span></button>`;
}

$("chips").addEventListener("click", async (e) => {
  const button = e.target.closest(".chip");
  if (!button) return;
  if (button.id === "add-chip") return addFolder();
  selected = button.dataset.id || null;
  renderChips();
});

$("chips").addEventListener("contextmenu", (e) => {
  const button = e.target.closest(".chip:not(.add)");
  if (!button) return;
  e.preventDefault();
  const id = button.dataset.id || null;
  const items = [["设为默认位置", () => setDefault(id)]];
  if (id) items.push(["从常用目录移除", () => removeFolder(id)]);
  showMenu(e.clientX, e.clientY, items);
});

function setDefault(id) {
  if (mode === "extract") settings.default_folder = id;
  else settings.compress.destination = id;
  selected = id;
  save();
  render();
}

async function addFolder() {
  const path = await invoke("pick_folder", { title: "选择要加入常用目录的文件夹" });
  if (!path) return;
  const name = path.split(/[\\/]/).filter(Boolean).pop() || path;
  settings.favorites.push({ id: crypto.randomUUID(), name, path });
  await save();
  render();
  renderSettings();
}

function removeFolder(id) {
  settings.favorites = settings.favorites.filter((f) => f.id !== id);
  if (settings.default_folder === id) settings.default_folder = null;
  if (settings.compress.destination === id) settings.compress.destination = null;
  if (selected === id) selected = null;
  save();
  render();
  renderSettings();
}

function showMenu(x, y, items) {
  const menu = $("chip-menu");
  menu.innerHTML = "";
  for (const [label, fn] of items) {
    const b = document.createElement("button");
    b.textContent = label;
    b.onclick = () => { menu.hidden = true; fn(); };
    menu.appendChild(b);
  }
  menu.style.left = `${Math.min(x, innerWidth - 170)}px`;
  menu.style.top = `${y}px`;
  menu.hidden = false;
}
document.addEventListener("click", () => ($("chip-menu").hidden = true));
document.addEventListener("contextmenu", (e) => { if (!e.target.closest(".chip")) e.preventDefault(); });

document.querySelectorAll(".mode button").forEach((b) =>
  b.addEventListener("click", () => {
    mode = b.dataset.mode;
    selected = defaultId() ?? null;
    render();
  }),
);

$("reveal-after").onchange = (e) => { settings.reveal_after = e.target.checked; save(); };
$("delete-after").onchange = (e) => { settings.delete_after_extract = e.target.checked; save(); };

$("choose").onclick = async () => {
  const files = await invoke("pick_files", { archives: mode === "extract" });
  if (files.length) handle(files, selected);
};
$("pending-cancel").onclick = () => { pending = []; render(); };
$("pending-go").onclick = () => { handle(pending, selected); pending = []; render(); };

function handle(files, folderId) {
  if (mode === "extract") {
    invoke("extract", { files, dest: null, folderId: folderId ?? null, password: null }).catch(alertError);
  } else {
    const options = { ...settings.compress, destination: folderId ?? null };
    invoke("compress", { files, options, password: null, name: null, saveDefault: false }).catch(alertError);
  }
}

// ---- 拖放：可以拖到拖放区，也可以直接拖到某个目录上 ----

function elementAt(position) {
  const r = window.devicePixelRatio || 1;
  return document.elementFromPoint(position.x / r, position.y / r);
}
function clearTargets() {
  $("drop").classList.remove("over");
  document.querySelectorAll(".chip.target").forEach((c) => c.classList.remove("target"));
}
window.__TAURI__.webview.getCurrentWebview().onDragDropEvent(({ payload }) => {
  if (payload.type === "over" || payload.type === "enter") {
    clearTargets();
    const el = payload.position && elementAt(payload.position);
    const chip = el?.closest?.(".chip:not(.add)");
    if (chip) chip.classList.add("target");
    else $("drop").classList.add("over");
  } else if (payload.type === "drop") {
    const el = payload.position && elementAt(payload.position);
    const chip = el?.closest?.(".chip:not(.add)");
    clearTargets();
    handle(payload.paths, chip ? chip.dataset.id || null : selected);
  } else {
    clearTargets();
  }
});

// ---- 任务列表 ----

function renderJobs(jobs) {
  $("recent").hidden = jobs.length === 0;
  const icon = { running: "⟳", done: "✓", failed: "!" };
  $("jobs").innerHTML = jobs.slice(0, 4).map((j) => `
    <div>
      <span class="${j.state}">${icon[j.state]}</span>
      <span class="name" title="${esc(j.message || j.title)}">${esc(j.title)}</span>
      ${j.state === "running" ? '<span class="muted small">处理中</span>' : ""}
      ${j.state === "done" ? `<button class="link" data-path="${esc(j.result)}">在资源管理器中显示</button>` : ""}
      ${j.state === "failed" ? '<span class="failed small">失败</span>' : ""}
    </div>`).join("");
}
$("jobs").addEventListener("click", (e) => {
  const path = e.target.dataset?.path;
  if (path) invoke("reveal", { path });
});

// ---- 压缩面板 ----

function fillDestSelect(select, value, sameLabel) {
  select.innerHTML = `<option value="">${sameLabel}</option>` +
    settings.favorites.map((f) => `<option value="${f.id}">${esc(f.name)}</option>`).join("");
  select.value = value ?? "";
}

function openCompress(files) {
  compressFiles = files;
  const c = settings.compress;
  const first = files[0].split(/[\\/]/).pop();
  $("compress-count").textContent = files.length > 1 ? `${files.length} 项` : first;
  $("c-name").value = files.length === 1 ? first.replace(/\.[^.]+$/, "") : "归档";
  $("c-format").value = c.format;
  $("c-level").value = c.level;
  fillDestSelect($("c-dest"), c.destination, "与原文件同目录");
  $("c-password").value = "";
  $("c-exclude").checked = c.exclude_system_files;
  $("c-save").checked = false;
  updateCompressForm();
  $("compress-dialog").showModal();
}
function updateCompressForm() {
  const f = $("c-format").value;
  $("c-ext").textContent = EXT[f];
  const canEncrypt = f === "zip" || f === "seven-z";
  $("c-password").disabled = !canEncrypt;
  $("c-password-hint").textContent = canEncrypt ? "使用 AES-256 加密。密码不会保存。" : "这个格式不支持密码。";
}
$("c-format").onchange = updateCompressForm;
$("compress-dialog").addEventListener("close", () => {
  if ($("compress-dialog").returnValue !== "ok") return;
  const options = {
    format: $("c-format").value,
    level: $("c-level").value,
    destination: $("c-dest").value || null,
    exclude_system_files: $("c-exclude").checked,
  };
  const saveDefault = $("c-save").checked;
  if (saveDefault) settings.compress = options;
  invoke("compress", {
    files: compressFiles, options, password: $("c-password").value || null,
    name: $("c-name").value.trim() || null, saveDefault,
  }).catch(alertError);
});

// ---- 密码与提示 ----

$("password-dialog").addEventListener("close", () => {
  const req = passwordRequest;
  passwordRequest = null;
  if ($("password-dialog").returnValue !== "ok" || !req) return;
  invoke("extract", { files: req.files, dest: req.dest, folderId: null, password: $("pw-input").value }).catch(alertError);
});

function alertError(message) {
  $("alert-title").textContent = "出错了";
  $("alert-message").textContent = String(message);
  if (!$("alert-dialog").open) $("alert-dialog").showModal();
}

function handleRequest(req) {
  if (req.kind === "pending") {
    mode = "extract";
    pending = req.files;
    render();
  } else if (req.kind === "compress") {
    openCompress(req.files);
  } else if (req.kind === "password") {
    passwordRequest = req;
    $("pw-file").textContent = `“${req.files[0].split(/[\\/]/).pop()}”已加密`;
    $("pw-wrong").hidden = !req.wrong;
    $("pw-input").value = "";
    if (!$("password-dialog").open) $("password-dialog").showModal();
  } else if (req.kind === "error") {
    $("alert-title").textContent = req.title;
    $("alert-message").textContent = req.message;
    if (!$("alert-dialog").open) $("alert-dialog").showModal();
  }
}

// ---- 设置 ----

function renderSettings() {
  $("s-double").value = settings.double_click_extract ? "extract" : "open";
  fillDestSelect($("s-default-folder"), settings.default_folder, "原位置（压缩包所在目录）");
  $("s-format").value = settings.compress.format;
  $("s-level").value = settings.compress.level;
  fillDestSelect($("s-cdest"), settings.compress.destination, "与原文件同目录");
  $("s-favorites").innerHTML = settings.favorites.map((f) => `
    <div class="fav">${ICON.folder}<span>${esc(f.name)}</span><span class="path" title="${esc(f.path)}">${esc(f.path)}</span>
    <button type="button" data-remove="${f.id}">移除</button></div>`).join("");
  $("s-themes").innerHTML = THEMES.map(([id, name, color]) => {
    const bg = id === "system" ? "conic-gradient(#ff453a,#ff9f0a,#ffd60a,#30d158,#0a84ff,#bf5af2,#ff453a)" : color;
    return `<button type="button" class="swatch ${settings.theme === id ? "on" : ""}" data-theme="${id}" title="${name}" style="background:${bg}"></button>`;
  }).join("");
}
$("open-settings").onclick = async () => {
  renderSettings();
  const status = await invoke("update_status");
  $("s-version").textContent = `版本 ${status.current}` + (status.latest && status.latest !== status.current ? `，最新版本 ${status.latest}` : "");
  $("settings-dialog").showModal();
};
$("s-double").onchange = (e) => { settings.double_click_extract = e.target.value === "extract"; save(); };
$("s-default-folder").onchange = (e) => { settings.default_folder = e.target.value || null; save(); render(); };
$("s-format").onchange = (e) => { settings.compress.format = e.target.value; save(); };
$("s-level").onchange = (e) => { settings.compress.level = e.target.value; save(); };
$("s-cdest").onchange = (e) => { settings.compress.destination = e.target.value || null; save(); render(); };
$("s-add-folder").onclick = addFolder;
$("s-defaults").onclick = () => invoke("open_default_apps");
$("s-favorites").addEventListener("click", (e) => { const id = e.target.dataset?.remove; if (id) removeFolder(id); });
$("s-themes").addEventListener("click", (e) => {
  const id = e.target.dataset?.theme;
  if (!id) return;
  settings.theme = id;
  applyTheme();
  renderSettings();
  save();
});

// ---- 首次启动 ----

$("w-defaults").onclick = () => invoke("open_default_apps");
$("welcome-dialog").addEventListener("close", () => {
  settings.double_click_extract = $("w-double").value === "extract";
  settings.onboarded = true;
  save();
});
$("welcome-dialog").addEventListener("cancel", (e) => e.preventDefault());

// ---- 强制升级 ----

function applyUpdate(status) {
  $("update-blocker").hidden = !status.required;
  if (!status.required) return;
  $("update-text").textContent = `当前版本 ${status.current} 已停止支持，请升级到 ${status.latest || "最新版本"} 后继续使用。`;
  $("update-notes").textContent = status.notes || "";
  $("update-go").onclick = () => status.url && invoke("open_url", { url: status.url });
}

// ---- 启动 ----

(async () => {
  settings = await invoke("get_settings");
  applyTheme();
  selected = settings.default_folder ?? null;
  render();
  renderJobs(await invoke("get_jobs"));
  applyUpdate(await invoke("update_status"));
  await listen("jobs", (e) => renderJobs(e.payload));
  const takeRequests = async () => (await invoke("take_requests")).forEach(handleRequest);
  await listen("request", takeRequests);
  await takeRequests();
  await listen("update", (e) => applyUpdate(e.payload));
  if (!settings.onboarded) {
    $("w-double").value = settings.double_click_extract ? "extract" : "open";
    $("welcome-dialog").showModal();
  }
})();
