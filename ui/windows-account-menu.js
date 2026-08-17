const CODEX_MUX_WINDOWS_API = "http://127.0.0.1:__CODEX_MUX_CONTROL_PORT__/v1";
const CODEX_MUX_WINDOWS_TOKEN = "__CODEX_MUX_CONTROL_TOKEN__";
let codexMuxWindowsLoginActive = false;

function CodexMuxWindowsProfileMenuOpenChange(setOpen) {
  return (nextOpen) => {
    if (!nextOpen && codexMuxWindowsLoginActive) return;
    setOpen(nextOpen);
  };
}

async function codexMuxWindowsRequest(path, options = {}) {
  const response = await fetch(`${CODEX_MUX_WINDOWS_API}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Codex-Mux-Token": CODEX_MUX_WINDOWS_TOKEN,
      ...(options.headers || {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `Request failed (${response.status})`);
  }
  return body;
}

function codexMuxWindowsWeeklyWindow(rateLimits) {
  const windows = [rateLimits?.primary, rateLimits?.secondary].filter(Boolean);
  windows.sort(
    (left, right) =>
      (left.windowDurationMins || 0) - (right.windowDurationMins || 0),
  );
  return windows.at(-1) || null;
}

function CodexMuxWindowsAccountAvatar({ imageUrl, label }) {
  const [failed, setFailed] = fcl.useState(false);
  if (imageUrl && !failed) {
    return (0, e7.jsx)("img", {
      src: imageUrl,
      alt: "",
      className: "size-7 shrink-0 rounded-full object-cover",
      referrerPolicy: "no-referrer",
      onError: () => setFailed(true),
    });
  }
  const initial = (label || "?").trim().slice(0, 1).toUpperCase() || "?";
  return (0, e7.jsx)("span", {
    className:
      "flex size-7 shrink-0 items-center justify-center rounded-full bg-token-foreground/10 text-xs font-medium",
    "aria-hidden": true,
    children: initial,
  });
}

function CodexMuxWindowsAccountMenu() {
  const [accounts, setAccounts] = fcl.useState([]);
  const [loading, setLoading] = fcl.useState(true);
  const [busy, setBusy] = fcl.useState(false);
  const [error, setError] = fcl.useState("");
  const [login, setLogin] = fcl.useState(null);
  const [codeCopied, setCodeCopied] = fcl.useState(false);
  const loginAccountId = login?.accountId || null;

  const refresh = fcl.useCallback(async () => {
    try {
      const result = await codexMuxWindowsRequest("/accounts");
      setAccounts(result.accounts || []);
      setError("");
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setLoading(false);
    }
  }, []);

  fcl.useEffect(() => {
    refresh();
    const events = new EventSource(
      `${CODEX_MUX_WINDOWS_API}/events?token=${encodeURIComponent(CODEX_MUX_WINDOWS_TOKEN)}`,
    );
    events.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data);
        if (payload.type !== "account-updated") return;
        if (payload.accountId === loginAccountId) {
          codexMuxWindowsLoginActive = false;
          setLogin(null);
        }
        refresh();
      } catch {}
    };
    const timer = setInterval(refresh, 30_000);
    return () => {
      clearInterval(timer);
      events.close();
    };
  }, [refresh, loginAccountId]);

  fcl.useEffect(() => {
    if (!login) return;
    const cancelLogin = (event) => {
      if (event.key !== "Escape") return;
      codexMuxWindowsLoginActive = false;
      setLogin(null);
    };
    window.addEventListener("keydown", cancelLogin, true);
    return () => window.removeEventListener("keydown", cancelLogin, true);
  }, [login]);

  const connected = accounts.filter(
    (account) => account.connected && account.enabled,
  );

  async function addSubscription(event) {
    event.preventDefault();
    event.stopPropagation();
    if (busy) return;
    codexMuxWindowsLoginActive = true;
    setBusy(true);
    setError("");
    try {
      const created = await codexMuxWindowsRequest("/accounts", {
        method: "POST",
        body: JSON.stringify({
          label: `Subscription ${Math.max(accounts.length, connected.length) + 1}`,
        }),
      });
      const result = await codexMuxWindowsRequest(
        `/accounts/${encodeURIComponent(created.account.id)}/login`,
        {
          method: "POST",
          body: JSON.stringify({ mode: "chatgptDeviceCode" }),
        },
      );
      const pending = result.login
        ? { ...result.login, accountId: created.account.id }
        : null;
      codexMuxWindowsLoginActive = pending != null;
      setCodeCopied(false);
      setLogin(pending);
      await refresh();
    } catch (requestError) {
      codexMuxWindowsLoginActive = false;
      setError(requestError.message);
    } finally {
      setBusy(false);
    }
  }

  async function continueLogin(event) {
    event.preventDefault();
    event.stopPropagation();
    const userCode = login?.userCode || "";
    const verificationUrl = login?.verificationUrl || login?.authUrl || "";
    try {
      if (userCode) {
        await navigator.clipboard.writeText(userCode);
        setCodeCopied(true);
      }
      if (verificationUrl) {
        const destination = new URL(verificationUrl);
        const trusted =
          destination.protocol === "https:" &&
          (destination.hostname === "chatgpt.com" ||
            destination.hostname === "auth.openai.com");
        if (!trusted) throw new Error("Untrusted verification URL");
        window.open(destination.href, "_blank", "noopener,noreferrer");
      }
    } catch (requestError) {
      setError(requestError.message || "Unable to continue sign-in.");
    }
  }

  const rows = connected.map((account) => {
    const weekly = codexMuxWindowsWeeklyWindow(account.rateLimits);
    const remaining = weekly == null
      ? null
      : Math.max(0, 100 - Number(weekly.usedPercent || 0));
    return (0, e7.jsxs)(
      "div",
      {
        className: "flex min-w-0 items-center gap-2 px-3 py-2",
        children: [
          (0, e7.jsx)(CodexMuxWindowsAccountAvatar, {
            imageUrl: account.profileImageUrl,
            label: account.label,
          }),
          (0, e7.jsxs)("span", {
            className: "flex min-w-0 flex-1 flex-col",
            children: [
              (0, e7.jsx)("span", {
                className: "truncate text-sm",
                children: account.planLabel
                  ? `${account.label} · ${account.planLabel}`
                  : account.label,
              }),
              (0, e7.jsx)("span", {
                className: "truncate text-xs text-codex-description",
                children: account.email || account.planType || "ChatGPT subscription",
              }),
            ],
          }),
          (0, e7.jsx)("span", {
            className: "shrink-0 text-xs text-codex-description tabular-nums",
            children: remaining == null ? "–" : `${Math.round(remaining)}% left`,
          }),
        ],
      },
      `codex-mux-windows-${account.id}`,
    );
  });

  if (loading) {
    rows.push(
      (0, e7.jsx)("div", {
        className: "px-3 py-2 text-sm text-codex-description",
        children: "Connecting subscriptions…",
      }, "codex-mux-windows-loading"),
    );
  }

  if (login) {
    rows.push(
      (0, e7.jsxs)(
        "button",
        {
          type: "button",
          className:
            "mx-1 flex items-center justify-between rounded-lg px-2 py-2 text-left text-sm hover:bg-token-foreground/5",
          onClick: continueLogin,
          children: [
            (0, e7.jsxs)("span", {
              className: "flex flex-col",
              children: [
                (0, e7.jsx)("span", { children: "Continue sign-in" }),
                (0, e7.jsx)("span", {
                  className: "text-xs text-codex-description",
                  children: codeCopied
                    ? `Code ${login.userCode || ""} copied`
                    : login.userCode
                      ? `Code ${login.userCode} · click to copy`
                      : "Open the ChatGPT verification page",
                }),
              ],
            }),
            (0, e7.jsx)(CodexMuxWindowsCopyIcon, { className: "size-4" }),
          ],
        },
        "codex-mux-windows-login",
      ),
    );
  }

  if (error) {
    rows.push(
      (0, e7.jsx)("div", {
        className: "px-3 py-2 text-xs text-danger",
        children: error,
      }, "codex-mux-windows-error"),
    );
  }

  if (!loading) {
    rows.push(
      (0, e7.jsxs)(
        "button",
        {
          type: "button",
          disabled: busy,
          className:
            "mx-1 flex items-center gap-2 rounded-lg px-2 py-2 text-left text-sm hover:bg-token-foreground/5 disabled:opacity-50",
          onClick: addSubscription,
          children: [
            (0, e7.jsx)(CodexMuxWindowsPlusIcon, { className: "size-4" }),
            busy ? "Adding subscription…" : "Add another subscription",
          ],
        },
        "codex-mux-windows-add",
      ),
    );
  }

  rows.push(
    (0, e7.jsx)(yH.Separator, {}, "codex-mux-windows-separator"),
  );
  return (0, e7.jsx)("div", {
    className: "flex w-full min-w-0 flex-col",
    children: rows,
  });
}

function CodexMuxWindowsPlusIcon(props) {
  return (0, e7.jsx)("svg", {
    viewBox: "0 0 20 20",
    fill: "none",
    "aria-hidden": true,
    ...props,
    children: (0, e7.jsx)("path", {
      d: "M10 4.25v11.5M4.25 10h11.5",
      stroke: "currentColor",
      strokeWidth: 1.5,
      strokeLinecap: "round",
    }),
  });
}

function CodexMuxWindowsCopyIcon(props) {
  return (0, e7.jsx)("svg", {
    viewBox: "0 0 20 20",
    fill: "none",
    "aria-hidden": true,
    ...props,
    children: (0, e7.jsxs)(e7.Fragment, {
      children: [
        (0, e7.jsx)("rect", {
          x: 6.25,
          y: 6.25,
          width: 9.5,
          height: 9.5,
          rx: 2,
          stroke: "currentColor",
          strokeWidth: 1.5,
        }),
        (0, e7.jsx)("path", {
          d: "M13.75 6.25V6A1.75 1.75 0 0 0 12 4.25H6A1.75 1.75 0 0 0 4.25 6v6c0 .97.78 1.75 1.75 1.75h.25",
          stroke: "currentColor",
          strokeWidth: 1.5,
          strokeLinecap: "round",
        }),
      ],
    }),
  });
}
