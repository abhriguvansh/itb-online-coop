# Movement experiment — October 12, 2026

**Result: native relocation works, but legal movement is not established.** Probe 0.2.0 called `BoardPawn:Move` once. It reached the exact destination and returned true, but movement allowance remained unused and no normal Move execution hooks appeared. The lab detected that failure and disabled further lab actions.

## Tested baseline

One Windows Steam instance, build 13725832, game 1.2.93, loader 2.9.6, modApiExt 1.25 and calibrated memedit 1.2.2. Easy Edit stayed disabled. The displayed profile was `ITB_Coop_Probe`; its internal folder key remained `Alpha`. Rift Walkers, standard equipment, Normal difficulty, advanced content off, `Mission_Artillery`, player turn 2. IDs and coordinates below are local IDs and zero-based board coordinates.

Before enabling memedit, all 18 current save files and the previous probe/configuration were preserved privately with hashes. The installed memedit binary matched the reviewed loader staging copy. Updates changed only owned probe files while the game was closed; the existing memedit configuration was explicitly enabled. No Cloud or firewall settings changed.

## Comparison with normal movement

| Check | Normal UI baseline | Scripted native Move |
|---|---|---|
| Pawn | Cannon, ID 1, `TankMech` | Artillery, ID 2, `ArtiMech` |
| Requested / observed position | (2,4) → (1,5), matched | (1,3) → (0,3), matched |
| Movement spent | false → true | false → false |
| Active after movement | true | true |
| Health | 3 → 3 | 2 → 2 |
| Undo | UI exposed Undo Move | pawn getter remained false; the visible Undo button belonged to the earlier Cannon move |
| Move execution hooks | start/end observed | none observed |
| Diagnostic outcome | baseline getter agrees with normal UI movement | `move_failed`: `postconditions-not-observed` |

These are different mechs and routes on the same turn, not an exact paired replay. The baseline establishes the allowance getter's response to one normal move. The scripted test's position matched visually and in the partial snapshot. Remaining active is an observed field; no post-script attack was executed, so full attack availability is not independently proven.

The corrected scripted session contains 10 records: registration, two loads, one context change, two candidate observations, arming, one request, one true engine return, and one failure. Records 7–10 describe the request, return, changed snapshot and failed postconditions. No `onSkillStart`, `onSkillEnd`, `capture_failed`, or `missing_hook` appeared in that session. `error.txt` was empty. Clicking Enable after the fault left the lab disabled and produced no second request or engine call. This verifies fault lockout; it is **not** a successful already-moved rejection test, because movement was never consumed.

The user saved and closed the test game after injected menu clicks were ignored. All four pre-existing normal-profile files still matched the pre-experiment hashes. Steam showed Cloud up to date before the final launch; its status was not rechecked after the final exit. No simultaneous-instance isolation claim follows from these checks.

## Corrections and retained evidence

The first diagnostic used the wrong Artillery type name (`RangeMech`); live observations established `ArtiMech`. The initial terrain restriction also excluded leaving an unburning forest. The corrected version permits a clear road/forest origin while keeping the destination restricted to plain ground. Offline tests cover the forest-origin exception, a burning forest rejection and a forest-destination rejection. No scripted call occurred during those setup checks.

Private evidence is retained under `.local/evidence/movement-0.2.0/`: `manual-baseline/`, `terrain-rejection/`, and `native-move-failure/`. The last contains the complete loader log, report, game/error logs, and normal-profile hash comparison. Backups are under `.local/backups/movement-0.2.0-before/`. These files and game screenshots are excluded from GitHub. This document is the reviewed public record.

The final complete loader log SHA-256 is `763e8ab39a61b4f211f300b4abbd691aeae3f82ca835ae25c13ace422b6ebe60`. It identifies the retained evidence; it does not independently prove the observations.

## Reproduce the experiment

This procedure deliberately reproduces a failed engine path and changes the disposable save. It is not a playable feature.

1. Preserve saves/configuration and use the pinned game/loader baseline. Enable modApiExt, this probe, and the bundled memedit 1.2.2, then restart. The lab refuses to arm if memedit is unavailable or uncalibrated; do not run an unreviewed calibration procedure to bypass that check.
2. Select the disposable displayed profile `ITB_Coop_Probe`. Enter a normal `Mission_Artillery` with standard Rift Walkers, after deployment and during a quiet player turn. The lab does not support Test Mech, other missions, custom movement, special movement abilities or arbitrary squad IDs.
3. Keep the lab off while collecting one normal UI movement baseline. Compare position, movement-spent, health and activity before/after. Preserve logs before another launch replaces them.
4. Click **Enable move lab**. A supported unmoved mech needs an empty, adjacent, reachable plain-ground destination and clear road/forest origin. The lab rejects hazards/items, unsupported statuses, occupied or unreachable destinations, wrong phase/context and missing getters. Unavailable buttons may show the last attempted candidate's rejection reason.
5. Click one displayed move. The request is revalidated before the single native call. Let the outcome check finish without other gameplay input. A true return alone is not a pass. Record exact destination, movement allowance, health, activity and hook presence; do not patch state to satisfy the check.
6. On the known failure, verify Enable cannot rearm, preserve logs and save/quit. A restart clears only the lab fault, not the changed game state. Do not retry the failed path as if it were a legal executor.

The 41 offline movement tests cover validation, pending locks, outcome checks and faults against doubles. The successful-outcome and already-spent cases in those tests are hypothetical engine responses, not real-game successes.

## Next blocking experiment

Trace the normal move commitment path that pairs the movement effect with allowance and undo bookkeeping. The pinned loader's [Move skill implementation](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/skills.lua#L28) builds a `SkillEffect` using `AddMove`, while modApiExt [wraps skill effects](https://github.com/itb-community/ITB-ModUtils/blob/21bcb56ba674aaaa6a940118b1cd527dfd38401b/scripts/alter.lua#L475) to observe execution. Those are source leads, not proof that directly submitting an effect performs normal action bookkeeping. Find and test a supported complete commitment path before extending attacks or transport. Do not simply set movementSpent to turn this result into a pass.
