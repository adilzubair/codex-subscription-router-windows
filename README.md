# Codex Subscription Router for Windows

Use multiple Codex subscriptions from one isolated Windows desktop app. New threads are routed to an enabled subscription with available capacity, while existing threads remain attached to the subscription that owns them.

This is an independent, source-only project. It does not distribute the ChatGPT/Codex desktop app, OpenAI binaries, or your credentials.

## One-click install

Open **Windows PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/adilzubair/codex-subscription-router-windows/main/install-windows.ps1 | iex
```

The installer checks for the official Microsoft Store app, Git, Go, and Node.js; installs missing prerequisites with `winget`; builds the router locally; creates Desktop and Start Menu shortcuts; and launches an isolated router-enabled Codex app. The first launch copies roughly 1.8 GB from the locally installed official app.

If you prefer to review scripts before running them, download this repository, inspect `install-windows.ps1`, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

The official Windows app can also be installed directly with the command [documented by OpenAI](https://learn.chatgpt.com/docs/enterprise/windows-deployment):

```powershell
winget install --id 9PLM9XGG6VKS -s msstore
```

## Add subscriptions

1. Open **Codex Subscription Router** from the Desktop or Start Menu.
2. Open the native profile menu and choose **Add another subscription**.
3. Complete the device sign-in using the account whose subscription you want to add.
4. Repeat for each subscription.

For rename, enable/disable, logout, and detailed quota controls, open **Subscription Manager** from the Start Menu folder.

You do not normally switch subscriptions by hand. The router selects an eligible account for each new thread and keeps that thread sticky to its owner. Disabling an account prevents new work from being assigned to it.

## Update, recover, or uninstall

- **Update:** run the one-click command again, or open **Update Router** in the Start Menu folder. Updates preserve `%USERPROFILE%\.codex-mux` and retain one previous install as a rollback copy.
- **Native-menu compatibility issue:** use `launch-router.cmd` in the install folder. This starts the same router with the standalone manager and without modifying the copied ASAR.
- **Uninstall:** open **Uninstall Router** in the Start Menu folder. Subscription state is preserved by default. To erase it too, run `uninstall-windows.ps1 -PurgeAccountState` from the source checkout.
- **Official app:** the Microsoft Store installation is never modified and remains independently updateable.

## What is installed

| Location | Purpose |
| --- | --- |
| `%LOCALAPPDATA%\Programs\Codex Subscription Router` | Locally built launcher and router |
| `%LOCALAPPDATA%\Codex Subscription Router Source` | Git checkout used for updates |
| `%LOCALAPPDATA%\Codex Subscription Router Runtime` | Isolated copy of the official desktop runtime |
| `%USERPROFILE%\.codex-mux` | Router configuration and per-subscription private state |

The local control service binds only to `127.0.0.1`, uses a randomly generated control token, and restricts state paths with Windows ACLs. See [SECURITY.md](SECURITY.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Compatibility

The native profile-menu patch is version-sensitive because it adapts a local copy of the installed desktop bundle. The launcher verifies signatures and hashes, builds a fresh isolated runtime after official app updates, and refuses incompatible layouts rather than editing the Store package. See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the latest tested versions and known limitations.

## Development

```powershell
npm ci --ignore-scripts
npm run check
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build-windows.ps1
```

Build output is written to `dist\windows` and intentionally excluded from Git.

## Attribution and disclaimer

This Windows implementation is derived from Bennett Blackham's MIT-licensed [codex-subscription-router](https://github.com/b-nnett/codex-subscription-router). See [ATTRIBUTION.md](ATTRIBUTION.md) and [LICENSE](LICENSE).

ChatGPT, Codex, and OpenAI are trademarks of OpenAI. This project is not affiliated with, endorsed by, or supported by OpenAI. You are responsible for complying with the terms that apply to the official app and each connected account.
