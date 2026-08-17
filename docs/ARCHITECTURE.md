# Windows architecture

## Data flow

```text
Isolated Codex desktop app
        |
        | CODEX_CLI_PATH
        v
codex-mux.exe  <---->  local manager on 127.0.0.1
        |
        +---- per-account Codex process + private home
        +---- per-account Codex process + private home
        +---- ...
```

The desktop app launches `codex-mux.exe` using the same app-server protocol it
uses for the bundled Codex CLI. The multiplexer owns a private Codex child for
each connected subscription, chooses an eligible account for new threads, and
records thread ownership so later requests stay with the same account.

## Isolated desktop runtime

The launcher locates the newest `OpenAI.Codex` MSIX package, verifies the
OpenAI Authenticode signature, hashes its ASAR, and copies the `app` directory
to `%LOCALAPPDATA%\Codex Subscription Router Runtime`. The Store package is
read-only input and is never changed.

Native-menu mode repacks only that private ASAR copy. The cached runtime name
includes the source hash, control port, and token hash, so an official app
update or control-token change creates a new isolated runtime. The untouched
mode skips ASAR patching and exposes account management in the local browser UI.

## Local state and security boundaries

- Router state lives in `%USERPROFILE%\.codex-mux`.
- Each subscription gets a separate private Codex home and credential store.
- The manager binds to loopback only and requires a random 256-bit bearer token.
- The launcher applies SID-based Windows ACLs to the state directory and token.
- The UI receives the token only inside the isolated profile/runtime.
- No account credentials are written to the repository or build output.

## Update behavior

The one-click installer fast-forwards a clean local source checkout, rebuilds
from pinned npm dependencies, stops only processes whose executable paths belong
to this router, stages the new payload, and retains the prior payload at
`Codex Subscription Router.previous`. Per-account state is outside the install
directory and is not replaced.
