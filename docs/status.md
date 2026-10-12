# Status — October 12, 2026

**Latest working increment: Milestone 0 safe baseline and a real-game observer smoke test. Milestone 1 (legal programmatic actions and input gating) remains incomplete. Online co-op is not implemented.**

## Implemented

- Local Git repository with original source, tests, dependency pins, and project records.
- Probe 0.1.1 with version logs, execution/build distinction, mission-phase observations, partial state capture, unavailable-field reporting, and candidate stability observations.
- Bounded JSON log reader, deterministic observed-state digests and explicit-boundary field differences.
- Verified backup/staging tool and scoped probe install/uninstall with ownership and hash checks.
- A GitHub Actions workflow for offline checks; it does not launch the game.

## Actually checked

- Windows Steam build 13725832, game 1.2.93, loader 2.9.6, and modApiExt 1.25. Versions agree in the menu and runtime log. memedit and Easy Edit were disabled.
- The loader release checksum matched upstream metadata. Ten save files and four affected game files were backed up and hash-verified before installation. Private baseline manifest: `.local/backups/baseline-20261012-151451/manifest.json` on the originating machine.
- The reviewed loader was installed, and the owned probe was installed, removed, and updated while the game was closed. Full loader/save restoration is documented but has not been exercised.
- Five mod files pass Lua 5.1 syntax parsing. Nineteen Lua contract tests and eleven log-analysis assertions pass. Contract execution uses Fengari/Lua 5.3 and engine doubles. Installer fixtures pass scoped-install and refusal checks.
- In the disposable `ITB_Coop_Probe` profile, Test Mech and a normal Archive mission produced real execution events, matching partial snapshots, damage, pushes, a collision, and normal attack consumption. Preview-only activity produced no corresponding execution events.
- One normal team turn continued through enemy attacks, planning, and spawning to the next player turn. The preserved log contains 92 records, including three queued-attack start/end pairs, with no capture failures or missing-hook records. The game's error file was empty. [Detailed evidence](feasibility.md#runtime-evidence--october-12-2026).
- The test run was saved and the game closed. Steam showed Cloud up to date before and after; its settings were not changed. All four pre-existing normal-profile files still matched their baseline hashes. Global loader/settings files and the disposable save changed as expected.

## Failures resolved

The first launch lacked an enabled modApiExt dependency. Both failing logs were preserved privately. Explicitly enabling modApiExt and the probe through Configure Mods, saving, and restarting fixed startup. The probe now defaults to disabled so setup can enable both together.

The initial profile check compared the displayed name with the internal folder key. Renaming the disposable profile left its folder key unchanged. Version 0.1.1 checks the loader-refreshed `Profile.visible_name` and requires a nonempty current-profile key. Offline tests cover wrong/missing names and the renamed-profile case; real tactical capture now passes that gate.

## Remaining limits

`settled_candidate` appeared between portions of enemy activity, including before subsequent effects. It is a diagnostic observation, not evidence that all work has drained. Movement-spent state and queued targets were unavailable with memedit disabled. Those findings block using this observer as an action authorization boundary.

Legal programmatic movement/attacks, pre-mutation input gating, AI/RNG reproduction, complete state restoration, transport, and two-instance synchronization are unproven. No complete cooperative mission has run. Separate-instance save/Cloud isolation and a second PC/tester have not been established.

GitHub publication is pending destination/visibility approval. No remote has been created or pushed. The workflow is configured, not GitHub-tested. Source licensing is undecided; no game or upstream code is included.

## Single next engineering experiment

Demonstrate one validated programmatic standard move on the disposable profile. First establish a trustworthy movement-spent read and a supported pre-mutation trigger; reject wrong phase, inactive/already-moved pawns, unsupported status, and unreachable targets before invoking the documented engine path. Compare the exact destination and allowance consumption against normal UI movement. Do not add transport until legal execution and input gating are demonstrated.
