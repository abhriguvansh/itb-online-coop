# Normal movement bookkeeping trace — 0.2.1

**Game-verified observation, October 12, 2026:** normal UI movement made undo available before the effect-start callback and consumed movement by the effect-end callback. This identifies differences from the failed native `BoardPawn:Move` experiment. It does not supply a legal programmatic executor or a cancellable input boundary.

## Scope and implementation

One Windows Steam instance: game 1.2.93, build 13725832, loader 2.9.6, modApiExt 1.25, calibrated memedit 1.2.2. Disposable `ITB_Coop_Probe` profile, standard Rift Walkers, Normal difficulty, advanced content off, `Mission_Artillery`, player turn 2. Easy Edit remained disabled. The movement lab stayed off throughout this session; the normal game controls performed one Artillery move.

`move_trace.lua` reads copied scalar state at Move build/start/end hooks and watches for subsequent changes for two seconds after execution hooks. It restricts itself to this profile, game version, mission, and local squad IDs 0–2. Unchanged build states are deduplicated while the latest preview target remains separately recorded. Each context has a 128-record limit plus one limit notification. Missing getters are labeled; diagnostic exceptions stop the trace. The trace changes no effects, invokes no actions/setters, and retains no native userdata.

## Observed sequence

Artillery, local ID 2, moved **(1,3) → (0,3)** through the normal game controls, matching the previous failed native experiment's route. Health remained 2 and the pawn remained active to attack. Coordinates are zero-based.

| Record / stage | Position | Movement spent | Undo possible | Undo position |
|---|---|---|---|---|
| 6 / build | (1,3) | false | false | (1,3) |
| 8 / onSkillStart | (1,3) | false | true | (1,3) |
| 10 / onSkillEnd | (0,3) | true | true | (1,3) |
| 11 / later candidate | (0,3) | true | Not captured by candidate schema | Not captured by candidate schema |

Start and end both reported elapsed time 206318 ms; build reported 206305 ms. These timestamps cannot measure animation duration or establish a general scheduling guarantee. Board and pawn busy reads were false at all three trace points. No changed-state update appeared during the subsequent watch. All requested trace fields were available.

The session produced 11 probe records: three trace records, one Move start/end pair, two candidates, one registration, two load notifications, and one context change. No trace error/limit, capture failure, or missing-hook record occurred. The game error file was empty. No lab request or scripted movement call was recorded.

On resuming this session, Artillery was back at (1,3), movement unused, despite the prior experiment observing it at (0,3) before the user's reported Save and Quit. This is a persistence discrepancy requiring a controlled follow-up; it does not by itself identify whether the native action, save boundary, or another transition caused it. No reset or undo was issued during this trace session.

Follow-up in 0.2.2: this session's normal UI move also resumed at the origin. That removes any basis for attributing the earlier discrepancy specifically to scripted relocation. The subsequent effect submission retained its position across a controlled reload but still failed movement/undo bookkeeping. [Updated comparison](effect-experiment.md).

## Source evidence and interpretation

- The pinned loader's [Move effect builder](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/skills.lua#L28) constructs a path-based `SkillEffect:AddMove` for standard ground movement. The visible Lua builder does not explicitly set movement allowance or undo state.
- modApiExt's [effect wrapper](https://github.com/itb-community/ITB-ModUtils/blob/21bcb56ba674aaaa6a940118b1cd527dfd38401b/scripts/alter.lua#L475) distinguishes build callbacks from scripts inserted around execution. Building an effect is not evidence that it was accepted as a player command.
- memedit supplies [GetUndoLoc](https://github.com/itb-community/memedit/blob/24fb9af025d06fa225f645cb482f992208f17e04/functions/pawn.lua#L406) and [IsMovementSpent](https://github.com/itb-community/memedit/blob/24fb9af025d06fa225f645cb482f992208f17e04/functions/pawn.lua#L667). This trace uses their reads only.

The observations bracket two distinct changes: undo availability between build and start, and movement consumption between start and end. They do not identify the exact native function responsible. In this run, an execution-start hook was already too late to reject the action before all bookkeeping changed. A build hook also cannot authorize commands: previews use it.

The next bounded experiment is to compare the source-backed skill-effect submission path with this baseline, checking movement, undo, and save/reload persistence independently. Any incomplete bookkeeping remains a failure; do not patch allowance flags to label it successful. A supported complete commitment API has not been identified in the reviewed material. Separately, pre-mutation input interception must be demonstrated before a multiplayer session can exist. No transport is being added at this stage.

## Preservation and repeat procedure

Seventeen save-area files were backed up and hash-verified before installing 0.2.1 while the game was closed. After this test, Save and Quit completed through the game menu, the process exited, and Steam showed Cloud up to date. All four normal-profile files matched their pre-test hashes. Cloud settings were unchanged; this is not a two-instance isolation test.

Private evidence is retained at `.local/evidence/move-trace-0.2.1/`, including the full loader log, game/error logs, report, and normal-profile checks. Full-session SHA-256: `5c69450097c799daa9b17d3b257dbc1f241d2d8221e2fa3ac7766929c898e4d7`. A hash identifies the retained evidence; it does not independently validate the observations. No raw logs or saves are published.

To repeat on the same supported baseline:

1. Close the game, preserve the current logs, and back up the disposable saves. Install 0.2.1 with the scoped installer and enable calibrated memedit for bookkeeping reads.
2. Select the exact disposable profile and a normal Archive artillery mission. Leave **Enable move lab** untouched. Choose an active standard Rift Walker with movement available and a legal empty adjacent target.
3. Select and move it through normal game controls. Wait at least two seconds, then inspect Move build/start/end trace states. Record missing reads and all differences; do not assume this session's ordering.
4. Save and Quit, preserve logs before relaunching, check normal-profile hashes and Cloud status. A controlled reload is an additional persistence test; it was not performed after the normal move in this session.

Offline coverage: ten trace contracts, alongside 19 observer and 41 movement contracts, eight Lua 5.1 syntax checks, eleven report assertions, and installer fixtures for current and legacy five-/seven-file payloads. These use engine doubles, not the native game runtime.
