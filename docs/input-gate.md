# Temporary input gate — probe 0.3.0

## Result: bounded mouse coverage demonstrated

On October 12, 2026, the existing loader hook consumed a move click and an End Turn click during a manually armed 30-second window. The full **partial observation** at arming and timeout was identical: player turn 2, grid 4, nine pawns, and no unavailable fields. No execution or phase event appeared between those records. After automatic release, the same destination click executed a normal Artillery move, consumed movement, and established undo. This is evidence for the tested mouse path, not complete multiplayer authorization.

The test used the existing Windows Steam build 13725832, game 1.2.93, loader 2.9.6, modApiExt 1.25 and calibrated memedit 1.2.2. Profile display name was `ITB_Coop_Probe`; mission was `Mission_Artillery`. The movement-effect lab stayed off. No native library, event queue, gameplay field or save was patched.

| Step | Recorded result |
|---|---|
| Select Artillery, local ID 2 | At (0,3), HP 2, active, movement unused. |
| Arm using **Block input 30s** | Sequence 6 records the partial starting state. |
| Click the reachable forest at (0,2), then End Turn | Sequences 7–10 record two consumed mouse-down/up pairs. Neither action executed. End Turn was not separately repeated as an unblocked positive control. |
| Attempt injected `r` | Sequence 11 records only a consumed text-input event. No key-down/up records appeared. This does **not** validate the repair shortcut or physical keyboard gate. |
| Automatic timeout | Sequence 12 reports `timeout`, five consumed events, and an identical partial state. |
| Repeat the same destination click | Build/start/end at sequences 13/15/17. End position (0,2), HP 2, active, movementSpent true, undoPossible true, undo origin (0,3). |
| Save and Quit | Game closed normally. Steam Cloud showed up to date before launch and after exit. Four normal-profile files matched their pre-test hashes. |

The retained log contains 18 probe records and the game error file is empty. Private evidence is under `.local/evidence/input-gate-0.3.0/`; 17 hash-verified save-area backups and the prior probe are under `.local/backups/input-gate-0.3.0-before/`. Raw log SHA-256: `6cf3c4b50783e15618f22ba516267d33c1af92ea22d0598fb758c07f172ca819`. Raw logs and saves are excluded from Git.

## Implementation and limits

`input_gate.lua` retains its native event-hook object and subscribes to the loader's early keyboard events. It intercepts mouse down/up, wheel, text input and early key down/up while armed. Mouse motion and quit deliberately pass. The earlier loader UI still runs before the native hook, allowing the diagnostic button to disarm manually; this also means earlier mod handlers are outside this gate's guarantee. Read the [source audit](native-boundary.md) for ordering and polled-state limitations.

The gate checks the disposable profile, game version, supported tactical context and idle observation before arming. It cannot overlap the movement lab. Its frame update expires the gate after 30,000 loader-clock milliseconds; event handling also checks expiry. Suppressed presses remain tracked through timeout/manual disarm so their repeats and releases are consumed. Context resets clear this tracking. Event logs are capped at 128 while suppression continues. No event userdata is retained across callbacks.

This diagnostic deliberately releases on context/clock failure. Callback exceptions are contained; the failing event is consumed if the gate was active, then the lab releases. Clock reset, held input, callback faults, log limits and lifecycle behavior have offline contracts only. A frozen process cannot run the timer. These behaviors are **not** a production multiplayer failure policy.

Matching partial observations cannot prove unchanged RNG, hidden callbacks, UI state or complete engine state. Keyboard shortcuts, held physical inputs, undo, reset, repair, weapon selection, menus, focus transitions, other mods and controllers still require separate tests. The current result does not justify enabling networking or claiming all unauthorized actions are blocked.

## Repeat and next test

With the disposable profile and supported mission loaded, keep the effect lab off. Select an unused mech and note a reachable tile. Click **Block input 30s**, attempt the destination and End Turn, let the timer expire, and repeat the destination click. Preserve the original log and compare the start/end observations and subsequent normal Move trace.

Next test physical keyboard down/up with an actual keyboard or a verified delivery method, including a harmless shortcut positive control, then a held key released across timeout. Expand undo/reset/menu coverage with matched unblocked controls. Stop and preserve evidence if any gameplay mutation bypasses the gate. Legal programmatic action commitment remains a separate unresolved blocker; do not repeat failed relocation primitives or repair their flags to declare success.
