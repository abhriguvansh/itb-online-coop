# Into the Breach — Native Online Co-op Research

An incremental investigation into two players running their own Windows copies of Into the Breach and cooperating on one three-mech squad against the game's AI.

**Current version: 0.1.0, an observer-only capability probe. Online co-op is not implemented. The probe has passed offline tests; loading it in the real game remains unverified.**

The first engineering question is whether the real game exposes reliable action execution, input control, and enough state to keep two instances aligned. This repository records evidence and runnable experiments before choosing a networking design.

## What exists

- A Lua mod that registers source-backed execution and mission-phase hooks.
- Versioned JSON diagnostic records through the loader's `LOG` function.
- Partial tile, pawn, turn, and grid observations, with unavailable fields identified.
- A deliberately labeled `settled_candidate` heuristic: three unchanged observations, at least 100 ms apart, with the board and observed pawns reporting idle.
- A local log summary and field-level comparison tool. Matching digests cover only the observed fields.
- A targeted probe installer with ownership checks, a verified backup/staging workflow, offline tests, and a GitHub Actions configuration.

There is no action replay, input gate, transport, deterministic replay claim, or automatic resynchronization. Undo/reset are merely observed in this diagnostic build. The probe cannot be used as a multiplayer session.

## Baseline

The inspected Steam build is `13725832`; its executable contains version `1.2.93`. The candidate loader is [ITB-ModLoader v2.9.6](https://github.com/itb-community/ITB-ModLoader/releases/tag/v2.9.6), with its bundled modApiExt `1.25`. Exact source revisions and the release checksum are in [dependencies.json](dependencies.json). Compatibility in the running game is still pending.

Obtain the loader separately from its upstream release. This repository contains no game files, loader binaries, upstream source copies, saves, or credentials. `mod/` contains only this project's five Lua source files.

## Test the project code

Node.js and PowerShell are used only for development; the game mod itself is Lua.

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm test
.\tests\install.ps1
npm run check:tracked
```

The current offline suite validates Lua 5.1 syntax, executes 18 Lua contract tests under Fengari's Lua 5.3 VM, checks log parsing/diffing, and exercises the installer against inert temporary files. It does **not** run the game's Lua 5.1 engine, native extensions, or real game hooks. CI has been configured but has not run on GitHub.

## Prepare a real-game test

1. Close Into the Breach. Resolve its Steam installation and your actual Documents folder. Preserve your normal profile.
2. Download the exact pinned loader ZIP. From the repository, prepare verified backups and an installation file plan:

   ```powershell
   .\tools\Prepare-Baseline.ps1 -GamePath 'YOUR GAME FOLDER' -LoaderArchive 'PATH TO ITB-ModLoader-2.9.6.zip'
   .\tools\Install-Probe.ps1 -GamePath 'YOUR GAME FOLDER' -Mode Plan
   ```

   Preparation writes only under ignored `.local/`. It backs up saves and affected game files, verifies hashes, and stages the loader. It does not install or launch anything. It refuses to replace an existing staged baseline.

3. Review the private `manifest.json` and [restore instructions](docs/test-plan.md#restore). Installing the loader replaces the game's `lua5.1.dll`, `SDL2.dll`, and `scripts/modloader.lua`; it also adds native libraries and Lua support files. Starting it rewrites `resources/resource.dat`. **Installation approval is required by this project's handoff before proceeding.** No unfamiliar installer script is needed.
4. After approval, extract the reviewed upstream ZIP into the game folder as upstream documents, then install only this probe:

   ```powershell
   .\tools\Install-Probe.ps1 -GamePath 'YOUR GAME FOLDER' -Mode Install
   ```

5. Launch one game instance through Steam. Create/select the disposable profile named exactly **`ITB_Coop_Probe`**, enable **ITB Co-op Capability Probe** in the loader's mod menu, and use Rift Walkers with standard equipment. Do not continue the normal profile's timeline. Follow [the smoke test](docs/test-plan.md#first-real-game-smoke-test).

The profile check restricts this probe's tactical logging. It does not isolate Steam Cloud or stop the loader from touching game resources. Cloud state has not been verified; do not run two instances or two PCs against these saves yet. No Cloud settings are changed by these tools.

## Read the results

Copy the game's `modloader.log` into `.local/evidence/` before another launch can replace it.

```powershell
npm run report -- '.local/evidence/first-launch.log'
npm run report -- --diff '.local/evidence/left.log' 12 '.local/evidence/right.log' 18
```

The numbers select explicit `settled_candidate` record sequences. Verify equivalent scenarios and action boundaries yourself; the tool does not map pawn IDs between PCs. Logs are parsed as JSON, never executed. Save full originals locally, and review any excerpts before publishing.

## Uninstall

```powershell
.\tools\Install-Probe.ps1 -GamePath 'YOUR GAME FOLDER' -Mode Uninstall
```

This removes only unchanged files owned by this probe. It refuses to remove edited files or unexpected content. It leaves the loader and other mods in place. For the loader and saves, use the [separate restore procedure](docs/test-plan.md#restore).

## Project records

- [Status and next experiment](docs/status.md)
- [Capability evidence and blockers](docs/feasibility.md)
- [Architecture decisions](docs/architecture.md)
- [Repeatable tests and restoration](docs/test-plan.md)
- [Dependency and license notes](THIRD_PARTY.md)

The Git history is intended to show implementation and QA decisions as the experiment develops. Public release and source licensing are not yet selected. This is an independent fan project, unaffiliated with Subset Games.
