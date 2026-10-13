# Into the Breach — Native Online Co-op Research

[![Probe checks](https://github.com/abhriguvansh/itb-online-coop/actions/workflows/checks.yml/badge.svg)](https://github.com/abhriguvansh/itb-online-coop/actions/workflows/checks.yml)

An incremental investigation into two players running their own Windows copies of Into the Breach and cooperating on one three-mech squad against the game's AI.

**Current source: 0.11.0. A player-operated move chooser now submits a legal movement through the protected TCP path. The guest executed it, but the host's gameplay heartbeat had expired: the paired interactive test stopped without retry and did not pass. Playable human-selected online co-op is not yet available.**

The prior 0.10.0 fixed scripted sequence passed in two independent real game instances: movement, punch, protected native End Turn with unused-unit confirmation, full enemy phase, then another legal move. That evidence remains separate from the new [interactive experiment and runtime-liveness blocker](docs/command-session.md#interactive-movement--probe-0110-october-13).

The [guard experiment](docs/window-guard.md) separates the bridge's tagged mouse input from ordinary game-window input before the loader UI. Protected sessions stay blocked after failure until explicit exit; the older timed diagnostic remains available separately.

Cannon moved three tiles and Artillery moved two through the game's normal UI path. Both retained their ability to attack, and all observed pawn fields survived save/reload. Four terrain-health readings changed, so full-state equality remains unresolved. Earlier tests verified normal Undo and a subsequent Combat Mech punch. [Movement evidence, failures and limits](docs/ui-movement.md).

That earlier movement evidence is a bounded path diagnostic on one Windows game instance, with one command per mech per launch and a fixed tested display layout. The earlier direct relocation methods failed normal bookkeeping; those [native Move](docs/movement-experiment.md) and [effect](docs/effect-experiment.md) failures are retained. The [attack record](docs/attack-experiment.md) documents the original validated punch.

**October 13 scripted network increment:** the [shared command session](docs/command-session.md#network-coordinated-phase-proof--probe-0100-october-13) uses fixed ownership, same-state readiness, duplicate/stale rejection and stop-on-uncertainty. Both actual games rejected eight early commands. All 26 partial-state candidates and 26 ordered execution/phase payloads match each other and the preserved vanilla reference. Full-state equality and general determinism remain unproven. Next: require fresh readiness from both actual game runtimes before dispatching an interactive move; a connected TCP bridge alone is insufficient.

The approved design is two persistent primary mechs, one per player, plus a third whose controller alternates each battle. Ordinary campaign disagreements use a persisted 50/50 choice between the two final votes; destructive exceptions need unanimity. Both humans can interleave legal actions and must be ready before End Turn. Restricted runtime ownership and readiness are tested with scripted peers; campaign voting, rotation and general multiplayer interaction are not implemented.

## What exists

The [native-boundary audit](docs/native-boundary.md) identifies an existing event-consumption path and its ordering/error limitations. The [input-gate test](docs/input-gate.md) blocked a destination click and an End Turn click; the same move succeeded after automatic release. Physical Tab blocking and a blocked menu click now have bounded evidence; broader input coverage remains unproven. The original native input bridge now supplies the narrowly tested movement path described above.

- An opt-in four-command TCP experiment with connection-bound peer roles, two-peer observation barriers, same-state End Turn readiness and no action retries.
- An experimental two-move chooser with owned-mech selection, destination validation, cancel and explicit confirmation. Ordinary clicks remain blocked from game input. Its two-replica completion is unverified; a real one-sided execution failure is preserved.
- A manually armed, 30-second input gate restricted to the disposable test profile.
- A Lua mod that registers source-backed execution and mission-phase hooks.
- A bounded, read-only trace of normal Move effects, movement allowance, and undo state.
- A manually armed movement experiment with full-path checks, fresh native-preview confirmation, outcome checks, and a fault lockout; disabled by default.
- Versioned JSON diagnostic records through the loader's `LOG` function.
- Partial tile, pawn, turn, and grid observations, with unavailable fields identified.
- A deliberately labeled `settled_candidate` heuristic: three unchanged observations, at least 100 ms apart, with the board and observed pawns reporting idle.
- A local log summary and field-level comparison tool. Matching digests cover only the observed fields.
- A targeted probe installer with ownership checks, a verified backup/staging workflow, offline tests, and a GitHub Actions configuration.

There is no general action replay, production multiplayer input authorization, general determinism claim or automatic resynchronization. Undo/Reset remain blocked during the restricted protected session. The fixed network fixture is not a playable co-op release.

## Baseline

The tested Steam build is `13725832`, game `1.2.93`, with [ITB-ModLoader v2.9.6](https://github.com/itb-community/ITB-ModLoader/releases/tag/v2.9.6) and its bundled modApiExt `1.25`. Main-menu versions and runtime logs agree. Exact source revisions and the release checksum are in [dependencies.json](dependencies.json). This is one tested baseline, not a compatibility claim for other versions.

Obtain the loader separately from its upstream release. This repository contains no game files, loader binaries, upstream source copies, saves, or credentials. `mod/` contains only this project's Lua source files. The movement experiment additionally requires the loader's bundled, calibrated memedit 1.2.2; observation alone does not. The trace marks unavailable bookkeeping reads when memedit is absent.

## Test the project code

Node.js and PowerShell run the development checks and restricted network harness; the game mod itself is Lua.

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm test
.\tests\install.ps1
npm run check:tracked
```

The local suite parses 16 Lua files as Lua 5.1 and runs 221 core Lua contracts under Fengari/Lua 5.3, six mailbox framing contracts, seven coordinator contracts, plus 11 log-analysis assertions and inert installer fixtures. The separate native CI job builds the original DLL and runs C contracts with mocked OS input. Neither job runs the game. [GitHub Actions results](https://github.com/abhriguvansh/itb-online-coop/actions/workflows/checks.yml) identify which checks passed for each revision.

## Prepare a real-game test

1. Close Into the Breach. Resolve its Steam installation and your actual Documents folder. Preserve your normal profile.
2. Download the exact pinned loader ZIP. From the repository, prepare verified backups and an installation file plan:

   ```powershell
   .\tools\Prepare-Baseline.ps1 -GamePath 'YOUR GAME FOLDER' -LoaderArchive 'PATH TO ITB-ModLoader-2.9.6.zip'
   .\tools\Install-Probe.ps1 -GamePath 'YOUR GAME FOLDER' -Mode Plan
   ```

   Preparation writes only under ignored `.local/`. It backs up saves and affected game files, verifies hashes, and stages the loader. It does not install or launch anything. It refuses to replace an existing staged baseline.

3. Review the private `manifest.json` and [restore instructions](docs/test-plan.md#restore). Installing the loader replaces the game's `lua5.1.dll`, `SDL2.dll`, and `scripts/modloader.lua`; it also adds native libraries and Lua support files. Starting it rewrites `resources/resource.dat`. The originating machine has completed this reviewed installation; repeat the review for another installation. No unfamiliar installer script is needed.
4. Extract the reviewed upstream ZIP into the game folder as upstream documents. Build the original bridge using the [pinned build procedure](docs/ui-movement.md#build-and-tests), then install only this probe:

   ```powershell
   .\tools\Install-Probe.ps1 -GamePath 'YOUR GAME FOLDER' -Mode Install -NativeBridgePath '.local/native-build/itb_input.dll'
   ```

5. Launch one game instance through Steam. Create/select a disposable profile whose displayed name is exactly **`ITB_Coop_Probe`**. Its internal folder key may differ after renaming; the probe checks the displayed name from the loader's profile data.
6. Open **Mod Content → Configure Mods**, expand **Mod Loader Extensions**, enable **modApiExt**, and enable **ITB Co-op Capability Probe**. Leave memedit and Easy Edit off for this baseline. Close the dialog to save, then restart the game. The probe defaults to disabled: explicitly selecting both entries avoids the fresh-configuration dependency failure encountered during testing.
7. Use Rift Walkers, standard equipment, Normal difficulty, and advanced content off. Do not continue the normal profile's timeline. Follow [the smoke test](docs/test-plan.md#first-real-game-smoke-test). Leave the movement lab off for observation. For the current movement lab, enable/calibrate memedit and read the exact supported route and layout in [the movement record](docs/ui-movement.md). To inspect the historical effect-path failure, use the separate [effect procedure](docs/effect-experiment.md#repeat-and-next-investigation), which changes the disposable timeline and requires memedit. The older native-move procedure describes version 0.2.0.

The profile check restricts this probe's tactical logging. It does not isolate Steam Cloud or stop the loader from touching game resources. Steam showed Cloud **Up to date** before and after the single-instance test; no Cloud settings were changed. The later two-guest experiment uses separate virtual disks and disposable saves, with no host shares or guest Steam login; two authenticated Steam sessions remain untested. The four pre-existing normal-profile files matched their backup hashes after the test.

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

The [public GitHub repository](https://github.com/abhriguvansh/itb-online-coop) records implementation and QA decisions as the experiment develops. No packaged release or source distribution license has been selected. This is an independent fan project, unaffiliated with Subset Games.
