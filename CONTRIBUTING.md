# Contributing

Contributions that improve Windows compatibility, routing correctness,
installer safety, tests, or documentation are welcome.

1. Fork the repository and create a focused branch.
2. Run `npm ci --ignore-scripts`.
3. Run `npm run check` before opening a pull request.
4. Describe the Windows, Store package, desktop app, and bundled CLI versions
   used for testing.

Do not commit OpenAI binaries, ASAR archives, generated runtimes, access tokens,
device codes, account identifiers, `.codex-mux`, or real conversation data.
Security reports belong in a private GitHub security advisory, as described in
`SECURITY.md`.
