# Test plan

## Evidence labels

Record source revision, API/hook, exact action, observed result, limitations, and confidence for every capability. `PASS (offline)` never means `PASS (game)`. Capture failures are failures to investigate before expanding scope.

## First real-game smoke test

Prerequisites: reviewed loader installation, verified private backups, one running instance, a selected disposable profile named exactly `ITB_Coop_Probe`, and only the loader's required extensions plus this probe. Use mouse/keyboard. The profile gate does not isolate Cloud, game resources, or the loader itself. Do not change Cloud settings or run concurrent copies as part of this first test.

1. Start the game via Steam after installation. Confirm the main-menu game version and loader version. Create/select the disposable profile through the game's profile menu. In **Mod Content → Configure Mods**, expand **Mod Loader Extensions**, enable **modApiExt** and **ITB Co-op Capability Probe**, close the dialog, and restart. Other extensions remain disabled. Display-name matching is deliberate: renaming a profile does not rename its folder key.
2. Start Rift Walkers with standard weapons, no optional content or extra gameplay mods. Use a simple mission. A Test Mech board is sufficient for the very first hook check, but never counts as a complete mission or a verified shared starting scenario.
3. In `modloader.log` in the game folder, find `ITBCOOP` records for `observer_registered` and `probe_loaded`. Confirm probe `0.2.2` (the original observer record used `0.1.1`), loader `2.9.6`, game `1.2.93`, and the test profile flag. Keep the movement lab off for this observation test. Initial `probe_loaded` can say false before the loader refreshes profile data on main-menu entry. Tactical `context_changed` records must say true. `runtimeVerified=false` is a conservative load-time declaration, not a test result; use preserved evidence for verification.
4. Let deployment/animations finish. Observe a `settled_candidate` with a partial state. Compare turn, grid, tile positions and pawn health with the actual board. Record every unavailable field. Missing memedit fields are expected; a failed base getter is a finding to investigate.
5. Hover and preview movement/attacks repeatedly without committing. The next candidate may report build-call counts. No player-action execution record should be attributed to mere preview activity. Separate AI/planning and tip-image activity when interpreting the log.
6. Commit one legal short move manually. Expect execution `onSkillStart`/`onSkillEnd` with weapon `Move`, then a fresh candidate. Check destination, active state and available move/attack indicators. If movementSpent is unavailable, record it as unknown; do not infer it from position.
7. Commit a standard Rift Walker attack manually. Expect the corresponding execution records. Record damage, push/collision results and action consumption visibly and in observed fields. Do not count the callback alone as successful legal execution.
8. End a team turn manually. Capture next-turn, environment/plan/spawn and queued-skill observations where they occur. Log absence as well as presence. This test observes phases; it does not reproduce AI or RNG.
9. Quit and preserve the full game and loader logs under a new `.local/evidence/` folder. Run `npm run report -- LOG_PATH`. Keep a short test record beside the log containing the build, dependency pins, scenario, actions and observations.

Success for the first increment: the real game loads the observer, preview and execution evidence are distinguishable, and a partial snapshot corresponds to the board. **This smoke test passed on October 12, 2026; it does not complete Milestone 1.** See the record in `feasibility.md`. Test Mech automatically restores action availability: validate normal action consumption in a normal mission as well.

If startup crashes, stop. Preserve `error.txt`, `log.txt` and `modloader.log` before restoring. If only snapshot capture fails, preserve the first `capture_failed` and the surrounding events. Do not repeatedly launch over the sole copy of failing logs.

## Next experiments after the smoke test

| Experiment | Required checks | Current status |
|---|---|---|
| Validated programmatic movement | Active player pawn, movement unused, supported statuses, exact reachable target, distance, post-move location, allowance consumption | Both native Move (0.2.0) and direct effect (0.2.2) failed allowance consumption. The effect position persisted across one reload. [Current procedure and evidence](effect-experiment.md) |
| Normal move bookkeeping trace | Build/start/end reads, movement allowance, undo state, latest preview, bounded logging | 0.2.1 real-game trace completed with the lab off. [Procedure and limits](move-trace.md) |
| Validated programmatic standard attack | Player phase, active pawn, powered standard weapon, uses, legal target, smoke/frozen/grappled behavior as applicable, damage/push/collision, action consumption | Not implemented/run |
| Input gating | Mouse press/release, keyboard hotkeys, end turn, repair, undo, reset, menu-triggered actions; pre-mutation rejection | Native source audit complete; bounded gate and positive-control procedure in [native-boundary.md](native-boundary.md#next-runnable-experiment-bounded-event-consumption-lab). Not implemented/run |
| Stable boundaries | Animation speed, delayed scripts, queued effects, disappearing pawns, environment callbacks, repeated reloads | Candidates observed in game, including during enemy activity; not an authorization boundary |
| Two real instances | Separate verified saves, equivalent scenario, explicit ID mapping, guest and host through one order, illegal/duplicate/stale rejection | Blocked on Milestone 1 and isolation |
| One cooperative mission | Both humans contribute; repair, AI, spawns, environment, objectives, win/loss and disconnect behavior | Not started |

Compare repeated runs with different preview histories before assuming deterministic replay. No packet-exchange or matching-initial-board test can close the two-instance milestone.

## Restore

The private backup manifest records original relative paths and SHA-256 hashes. Do not put that manifest or its save copies on GitHub.

1. Close the game. Preserve failing logs and any new disposable-profile evidence first.
2. Remove this probe using `Install-Probe.ps1 -Mode Uninstall`. If it refuses because files were edited, preserve and review those edits; do not force deletion.
3. For the loader, use the file plan to identify its additions and replacements. Restore the backed-up `lua5.1.dll`, `SDL2.dll`, `scripts/modloader.lua` and `resources/resource.dat` to their exact original locations and verify their hashes. Review any existing `.bak` file before touching it. The upstream uninstall batch was inspected; it removes several loader directories and renames bundled originals. It has **not** been run by this project. Do not blindly apply it after unrelated mods have been installed.
4. Remove only reviewed loader-added files from the manifest, preserving unrelated mods and newly created evidence. There is no automated full-loader restore command yet. If a manifest path has changed since installation, inspect it before replacement/removal. Steam's Verify Integrity can restore base game files, but does not reliably remove every added mod file.
5. The normal saves were only copied, not edited by the preparation step. Leave them alone unless restoration is actually needed. Before restoring saves, close Steam/game, review Cloud conflict behavior, preserve the current save directory separately, and copy only the intended backup. Do not merge normal and test profiles automatically.

Probe uninstall/reinstall was exercised against the live installation while closed. Full loader and save restoration remains a documented procedure, not a completed recovery drill. The accepted baseline scope is identified game/build, verified backups, pinned loader, disposable-profile selection, and a successfully loaded probe.
