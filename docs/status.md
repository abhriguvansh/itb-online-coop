# Status — October 12, 2026

**Latest increment: probe 0.2.2 tested direct skill-effect movement and a controlled save/reload. Relocation persisted, but movement consumption and undo failed. Both direct movement paths remain unsuitable. Milestone 1 (legal programmatic actions and input gating) remains incomplete. Online co-op is not implemented.**

## Implemented

- Local Git repository with original source, tests, dependency pins, and project records.
- Probe 0.2.2 retains version logs, execution/build distinction, mission-phase observations, partial state capture, unavailable-field reporting, and candidate stability observations.
- Read-only normal Move trace: bounded logging, deduplicated preview state, separate execution states, allowance/undo reads, and a two-second change watch. [Trace evidence](move-trace.md).
- Opt-in one-tile movement diagnostic, immediate request validation, measured postconditions and fault lockout. It is a known failing engine experiment, not a legal movement executor. [Test record](movement-experiment.md).
- The selected diagnostic now submits a direct movement effect with path checks and strict undo postconditions. The earlier native path remains covered offline. [Effect test](effect-experiment.md).
- Bounded JSON log reader, deterministic observed-state digests and explicit-boundary field differences.
- Verified backup/staging tool and scoped probe install/uninstall with ownership and hash checks.
- A GitHub Actions workflow for offline checks; it does not launch the game.

## Actually checked

- Windows Steam build 13725832, game 1.2.93, loader 2.9.6, and modApiExt 1.25. Versions agree in the menu and runtime log. memedit was disabled for the observer baseline, then enabled at 1.2.2 for the movement experiment; Easy Edit remained disabled.
- The loader release checksum matched upstream metadata. Ten save files and four affected game files were backed up and hash-verified before installation. Private baseline manifest: `.local/backups/baseline-20261012-151451/manifest.json` on the originating machine.
- The reviewed loader was installed, and the owned probe was installed, removed, and updated while the game was closed. Full loader/save restoration is documented but has not been exercised.
- Eight mod files pass Lua 5.1 syntax parsing. Nineteen observer, 48 movement, ten trace contract tests and eleven log-analysis assertions pass. Contract execution uses Fengari/Lua 5.3 and engine doubles. Installer fixtures cover scoped installation/removal and legacy five-/seven-file upgrade removal.
- In the disposable `ITB_Coop_Probe` profile, Test Mech and a normal Archive mission produced real execution events, matching partial snapshots, damage, pushes, a collision, and normal attack consumption. Preview-only activity produced no corresponding execution events.
- One normal team turn continued through enemy attacks, planning, and spawning to the next player turn. The preserved log contains 92 records, including three queued-attack start/end pairs, with no capture failures or missing-hook records. The game's error file was empty. [Detailed evidence](feasibility.md#runtime-evidence--october-12-2026).
- After the observer test, the run was saved and the game closed. Steam showed Cloud up to date before and after that test; its settings were not changed. All four pre-existing normal-profile files matched their baseline hashes. Global loader/settings files and the disposable save changed as expected.
- With memedit enabled, a normal Cannon move changed movementSpent from false to true while remaining active. A scripted Artillery move reached (0,3) from (1,3) but left movementSpent false and emitted no Move execution hooks. The lab timed out to a fault and could not be rearmed. The final log contains exactly one request and one engine call. No allowance setter or automatic retry was used.
- The movement test was saved and closed by the user after injected menu clicks failed. All four normal-profile hashes still match. Cloud was up to date before this final launch; its status after the final exit was not rechecked. Raw evidence and all 18 pre-experiment save backups remain private.
- The subsequent 0.2.1 session moved Artillery normally along the same (1,3) → (0,3) route with the lab off. Undo changed false → true between build/start; movementSpent changed false → true between start/end. Eleven probe records, three trace points, no missing trace fields or errors. The game was saved and closed through the menu; Cloud showed up to date afterwards. All four normal-profile hashes matched. Seventeen pre-session save-area files and the logs remain private. This session began with Artillery back at the prior origin; persistence of the earlier scripted relocation remains unresolved.

The 0.2.2 effect experiment issued one `Board:AddEffect` using `SkillEffect:AddMove` on the same Artillery route. It reached (0,3), HP 2 and active, but movementSpent and undoPossible stayed false; the lab faulted. A directly observed Save and Quit / relaunch retained (0,3) and unused movement. Before-reload and after-reload logs contain ten and five records, respectively, with empty game error files. Both exits completed, Cloud showed up to date, and four normal-profile hashes matched. Seventeen save-area backups and both logs are private. The earlier normal UI move also resumed at its origin, so persistence cannot be blamed uniquely on scripted movement.

## Failures resolved

The first launch lacked an enabled modApiExt dependency. Both failing logs were preserved privately. Explicitly enabling modApiExt and the probe through Configure Mods, saving, and restarting fixed startup. The probe now defaults to disabled so setup can enable both together.

The initial profile check compared the displayed name with the internal folder key. Renaming the disposable profile left its folder key unchanged. Version 0.1.1 checks the loader-refreshed `Profile.visible_name` and requires a nonempty current-profile key. Offline tests cover wrong/missing names and the renamed-profile case; real tactical capture now passes that gate.

Movement setup corrected Artillery's internal type to `ArtiMech` and allowed leaving a clear forest while retaining a plain-ground-only destination. Neither setup session issued a scripted move. The later allowance-consumption failure is unresolved and preserved, not classified as a successful move.

## Remaining limits

`settled_candidate` appeared between portions of enemy activity, including before subsequent effects. It is a diagnostic observation, not evidence that all work has drained. memedit now supplies movement-spent reads, with one manual baseline comparison; this does not solve the action authorization boundary or prove full state capture.

Legal programmatic movement/attacks, pre-mutation input gating, AI/RNG reproduction, complete state restoration, transport, and two-instance synchronization are unproven. No complete cooperative mission has run. Separate-instance save/Cloud isolation and a second PC/tester have not been established.

Public portfolio destination: [abhriguvansh/itb-online-coop](https://github.com/abhriguvansh/itb-online-coop), explicitly approved on October 12, 2026. [Live CI results](https://github.com/abhriguvansh/itb-online-coop/actions/workflows/checks.yml) are the authority for each pushed revision; local checks alone are not evidence of a successful GitHub run. Source licensing is undecided; no game or upstream code is included.

## Single next engineering experiment

Audit the native player-command boundary after [both direct movement paths failed](effect-experiment.md). Determine whether the loader exposes the complete accept/commit operation or a narrow native extension is needed, and identify where input can be rejected before mutation. Specify the missing operation before implementing an extension. Do not repeat the same primitives, patch movementSpent to claim success, or add transport before legal execution and pre-mutation input gating are demonstrated.
