const state = {
  token: "",
  accounts: [],
  routing: { mode: "automatic", accountId: "" },
  loginAccountId: null,
  verificationUrl: "",
  userCode: "",
};

const elements = {
  accounts: document.querySelector("#accounts"),
  add: document.querySelector("#add-account"),
  refresh: document.querySelector("#refresh"),
  connection: document.querySelector("#connection"),
  connected: document.querySelector("#connected-count"),
  enabled: document.querySelector("#enabled-count"),
  threads: document.querySelector("#thread-count"),
  routingAccount: document.querySelector("#routing-account"),
  routingStatus: document.querySelector("#routing-status"),
  notice: document.querySelector("#notice"),
  dialog: document.querySelector("#login-dialog"),
  deviceCode: document.querySelector("#device-code"),
  loginStatus: document.querySelector("#login-status"),
  openVerification: document.querySelector("#open-verification"),
  copyCode: document.querySelector("#copy-code"),
};

function loadToken() {
  const fragment = location.hash.replace(/^#/, "");
  const fromHash = fragment.startsWith("token=")
    ? new URLSearchParams(fragment).get("token")
    : fragment;
  state.token = fromHash || sessionStorage.getItem("codexMuxToken") || "";
  if (state.token) sessionStorage.setItem("codexMuxToken", state.token);
  history.replaceState(null, "", location.pathname);
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Codex-Mux-Token": state.token,
      ...(options.headers || {}),
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
  return payload;
}

function weeklyWindow(account) {
  const windows = [account.rateLimits?.primary, account.rateLimits?.secondary].filter(Boolean);
  windows.sort((a, b) => (a.windowDurationMins || 0) - (b.windowDurationMins || 0));
  return windows.at(-1) || null;
}

function maskEmail(email) {
  if (!email || !email.includes("@")) return email || "Not connected";
  const [name, domain] = email.split("@");
  const visible = name.slice(0, Math.min(2, name.length));
  return `${visible}${"•".repeat(Math.max(3, name.length - visible.length))}@${domain}`;
}

function initials(account) {
  return (account.label || account.email || "S").trim().slice(0, 1).toUpperCase();
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function renderAccount(account) {
  const card = element("article", "account");
  const main = element("div", "account-main");
  const avatar = element("div", "avatar", initials(account));
  if (account.profileImageUrl) {
    const image = document.createElement("img");
    image.src = account.profileImageUrl;
    image.alt = "";
    avatar.replaceChildren(image);
  }
  const details = element("div", "account-details");
  const name = element("div", "account-name");
  name.append(element("strong", "", account.label));
  if (account.controller) name.append(element("span", "badge primary-badge", "Primary"));
  if (state.routing.accountId === account.id) name.append(element("span", "badge selected-badge", "Selected"));
  if (account.planLabel || account.planType) name.append(element("span", "badge", account.planLabel || account.planType));
  details.append(name);
  details.append(element("div", "identity", maskEmail(account.email)));

  const weekly = weeklyWindow(account);
  if (weekly) {
    const quota = element("div", "quota");
    const track = element("div", "track");
    const fill = element("span");
    fill.style.width = `${Math.max(0, Math.min(100, weekly.usedPercent || 0))}%`;
    track.append(fill);
    quota.append(track, element("small", "", `${Math.round(weekly.usedPercent || 0)}% used`));
    details.append(quota);
  } else if (account.connected) {
    details.append(element("div", "identity", "Usage information unavailable"));
  }
  if (account.error) details.append(element("p", "error", account.error));
  main.append(avatar, details);

  const actions = element("div", "account-actions");
  const auth = element("button", "icon-button", account.connected ? "Sign out" : "Connect");
  auth.type = "button";
  auth.addEventListener("click", () => account.connected ? logout(account) : login(account));
  const rename = element("button", "icon-button", "Rename");
  rename.type = "button";
  rename.addEventListener("click", () => renameAccount(account));
  const toggle = element("button", `switch${account.enabled ? " on" : ""}`);
  toggle.type = "button";
  toggle.title = account.enabled ? "Disable routing" : "Enable routing";
  toggle.setAttribute("aria-label", toggle.title);
  toggle.addEventListener("click", () => updateAccount(account.id, { enabled: !account.enabled }));
  actions.append(auth, rename, toggle);
  card.append(main, actions);
  return card;
}

function render() {
  elements.accounts.replaceChildren();
  if (!state.accounts.length) {
    elements.accounts.append(element("div", "empty", "No subscriptions found."));
  } else {
    state.accounts.forEach((account) => elements.accounts.append(renderAccount(account)));
  }
  elements.connected.textContent = state.accounts.filter((account) => account.connected).length;
  elements.enabled.textContent = state.accounts.filter((account) => account.enabled).length;
  elements.threads.textContent = state.accounts.reduce((sum, account) => sum + (account.threadCount || 0), 0);
  renderRouting();
}

function renderRouting() {
  const selectedId = state.routing?.mode === "manual" ? state.routing.accountId || "" : "";
  elements.routingAccount.replaceChildren(new Option("Automatic (recommended)", ""));
  state.accounts.forEach((account) => {
    const eligible = account.connected && account.enabled;
    const suffix = eligible ? "" : " (unavailable)";
    const option = new Option(`${account.label}${account.planLabel ? ` · ${account.planLabel}` : ""}${suffix}`, account.id);
    option.disabled = !eligible;
    elements.routingAccount.append(option);
  });
  elements.routingAccount.value = selectedId;
  if (selectedId) {
    const selected = state.accounts.find((account) => account.id === selectedId);
    const label = selected?.label || state.routing.label || "the selected subscription";
    elements.routingStatus.textContent = `New chats prefer ${label}. If it is unavailable or out of capacity, the router falls back automatically.`;
  } else {
    elements.routingStatus.textContent = "New chats are balanced automatically using capacity, reset timing, and current load.";
  }
}

function setConnection(mode, text) {
  elements.connection.className = `connection ${mode}`;
  elements.connection.lastChild.textContent = ` ${text}`;
}

function showNotice(message, mode = "error") {
  elements.notice.textContent = message;
  elements.notice.classList.toggle("hidden", !message);
  elements.notice.classList.toggle("success", Boolean(message) && mode === "success");
}

async function refresh({ quiet = false } = {}) {
  if (!state.token) {
    setConnection("offline", "Missing access token");
    showNotice("Open this manager from the Windows router launcher so it can authenticate to the local control service.");
    return;
  }
  try {
    const payload = await api("/v1/accounts");
    state.accounts = payload.accounts || [];
    state.routing = payload.routing || { mode: "automatic", accountId: "" };
    render();
    setConnection("online", "Router online");
    if (!quiet) showNotice("");
    if (state.loginAccountId) {
      const account = state.accounts.find((item) => item.id === state.loginAccountId);
      if (account?.connected) {
        elements.loginStatus.textContent = "Connected. You can close this window.";
        state.loginAccountId = null;
      }
    }
  } catch (error) {
    setConnection("offline", "Router unavailable");
    if (!quiet) showNotice(error.message);
  }
}

async function addAccount() {
  const label = window.prompt("Subscription label", `Subscription ${state.accounts.length + 1}`);
  if (label == null) return;
  try {
    elements.add.disabled = true;
    const payload = await api("/v1/accounts", { method: "POST", body: JSON.stringify({ label }) });
    await login(payload.account);
    await refresh({ quiet: true });
  } catch (error) {
    showNotice(error.message);
  } finally {
    elements.add.disabled = false;
  }
}

async function login(account) {
  try {
    const payload = await api(`/v1/accounts/${encodeURIComponent(account.id)}/login`, {
      method: "POST",
      body: JSON.stringify({ mode: "chatgptDeviceCode" }),
    });
    const login = payload.login || {};
    state.loginAccountId = account.id;
    state.userCode = login.userCode || "";
    state.verificationUrl = login.verificationUrl || login.authUrl || "";
    elements.deviceCode.textContent = state.userCode || "Code unavailable";
    elements.loginStatus.textContent = "Waiting for sign-in…";
    elements.openVerification.disabled = !state.verificationUrl;
    elements.dialog.showModal();
  } catch (error) {
    showNotice(error.message);
  }
}

async function logout(account) {
  if (!window.confirm(`Sign out ${account.label}?`)) return;
  try {
    await api(`/v1/accounts/${encodeURIComponent(account.id)}/logout`, { method: "POST", body: "{}" });
    await refresh();
  } catch (error) {
    showNotice(error.message);
  }
}

async function updateAccount(id, input) {
  try {
    await api(`/v1/accounts/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(input) });
    await refresh();
  } catch (error) {
    showNotice(error.message);
  }
}

async function updateRouting(accountId) {
  const previous = state.routing;
  elements.routingAccount.disabled = true;
  try {
    const payload = await api("/v1/routing", {
      method: "PATCH",
      body: JSON.stringify({ accountId }),
    });
    state.routing = payload.routing || { mode: "automatic", accountId: "" };
    await refresh({ quiet: true });
    const selected = state.routing.mode === "manual" ? state.routing.label : "Automatic routing";
    showNotice(`${selected} will be used for new chats.`, "success");
  } catch (error) {
    state.routing = previous;
    renderRouting();
    showNotice(error.message);
  } finally {
    elements.routingAccount.disabled = false;
  }
}

async function renameAccount(account) {
  const label = window.prompt("Subscription label", account.label);
  if (label == null || !label.trim() || label.trim() === account.label) return;
  await updateAccount(account.id, { label: label.trim() });
}

async function copyCode() {
  if (!state.userCode) return;
  await navigator.clipboard.writeText(state.userCode);
  elements.loginStatus.textContent = "Code copied. Complete sign-in in your browser.";
}

elements.add.addEventListener("click", addAccount);
elements.refresh.addEventListener("click", () => refresh());
elements.routingAccount.addEventListener("change", (event) => updateRouting(event.target.value));
elements.deviceCode.addEventListener("click", copyCode);
elements.copyCode.addEventListener("click", copyCode);
elements.openVerification.addEventListener("click", () => {
  if (state.verificationUrl) window.open(state.verificationUrl, "_blank", "noopener,noreferrer");
});

loadToken();
refresh();
setInterval(() => refresh({ quiet: true }), 5000);
