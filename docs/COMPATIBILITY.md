# Compatibility

## Tested baseline

| Component | Tested version |
| --- | --- |
| Windows | Windows 11 x64 |
| Microsoft Store package | `OpenAI.Codex_26.810.7004.0_x64__2p2nqsd0c76g0` |
| Desktop app | `26.810.52044` |
| Bundled Codex CLI | `0.148.0-alpha.9` |
| Go | 1.26 or newer |
| Node.js | 22.12 or newer |

The router, manager, local control API, Windows build, isolated runtime copy,
ASAR repack, native subscription list, and add-subscription flow have been
validated against this baseline.

## Version-sensitive behavior

The native profile-menu integration recognizes specific structures in the
desktop JavaScript bundle. After an official app update, the patcher either
creates a newly verified runtime or stops with a compatibility error. It never
falls back to blindly changing unknown code.

If that happens, run `launch-router.cmd` from the install directory to use the
standalone manager without native-menu injection, then open a GitHub issue with
the Store package and desktop versions. Do not attach an ASAR or OpenAI binary.

## Known limitation

Computer Use still needs a repeatable full Windows end-to-end smoke-test matrix.
Core chat, repository work, routing, and account-management paths are the tested
scope. Treat Computer Use as preview compatibility until that matrix is complete.
