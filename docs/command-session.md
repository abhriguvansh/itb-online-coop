# Shared command experiment — October 13, 2026

Approval baseline: `4aaac65`; runtime remains probe 0.8.0. This increment is original source and offline tests only. Nothing is installed, launched or connected to incoming messages. No saves, Cloud/firewall settings or security settings changed. The locally flagged native executable was neither built nor run.

## Smallest runnable experiment

Today: `npm test` runs `tests/command_session.lua`. It creates the real `movement.lua` and `attack.lua` modules inside `experiments/command_session.lua`, with engine and bridge doubles. A guest-owned Artillery move completes through the selected UI path, then a host-owned fixed Combat Mech punch completes through the existing attack lab. Both share one admission path, one pending slot, one revision counter and one failure latch. This is runnable integration code, not a two-client or game result.

Next end-to-end target: on two real, safely isolated game instances, use actual ordered transport to submit a guest action, interleave a host action, complete the enemy/environment/planning phase, then submit another legal player action. Compare relevant state and subsequent outcomes while deliberately varying hover/preview/cancel histories. Native Undo/Reset may be absent and blocked in this explicitly restricted experiment. Expand to a fully supported mission afterwards. Neither this offline sequence nor the restricted experiment establishes representative balance or enjoyment.

## What changed

- The factory owns both diagnostic objects privately; it exposes submission, update, hook forwarding, stop and an unsupported checkpoint operation. No direct punch request is handed to a listener. Existing runtime buttons remain untouched and do not use this experimental factory yet.
- Requests name bounded session/encounter/phase/action/entity IDs, an observed revision, a caller-provided partial-state witness and explicit origin/target coordinates. The trusted harness supplies peer identity. This is not authentication; future transport must bind identity to its connection rather than trust a message's player field.
- A copied registry supports more than three entities, explicit commandability and ownership. The fixture includes Combat, Cannon, Artillery and the controllable Archive Artillery ally. An omitted or newly seen friendly stops admission. Registry inclusion does not claim adapters support that ally's actions; they reject it. A future test mission may exclude allies; the existing fixture cannot silently omit one.
- Duplicates never dispatch again. Reusing an ID with changed content conflicts. Busy/stale requests remain rejected even when replayed later: retain the UI draft, obtain a fresh preview and explicitly resubmit with a new ID. No auto-queue or retry. Records cap at 128 without eviction; reaching the bound stops this non-resumable experiment.
- Original profile/version/mission/phase, movement legality, UI-preview, one-move-per-mech and one-punch-per-process safeguards remain in the real modules. The punch remains actor 0 at (3,3), target 101 at (2,3), standard weapon slot 1 and the original effect/health checks. Unsupported payloads cannot choose arbitrary attacks.
- Guard failure, unmapped friendlies, uncertain dispatch, diagnostic timeout, update/hook errors or evidence failure stop both paths. The coordinator does not itself release protected input or reverse an engine action. Its latch cannot implement the native guard: live wiring must verify that guard before admission, propagate lifecycle events into `stop`, and audit the diagnostics' own bridge cleanup behavior.
- Completion requires existing diagnostic hook/postcondition evidence. Revision advances after its pending action clears with that evidence. It means partial diagnostic observation, not a proved engine completion barrier or peer agreement.

`mod/`, native code and installer payloads are unchanged. No version bump implies a runtime update. The experiment is excluded from installation until protection, lifecycle and inspection routing can be integrated and tested together.

## Inspection investigation and remaining interface work

Source-verified: the pinned loader's [`modApiExtGetSkillEffect`](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/extensions/modLoaderExtensions/mods/modApiExt/scripts/alter.lua#L475) sets a nested-call flag, invokes the underlying weapon builder, broadcasts skill-build callbacks and rewrites the constructed effect with execution-hook scripts. The installed `scripts/weapons_prime.lua`, `Prime_Punchmech:GetSkillEffect` (line 57 onward), constructs an effect using board-dependent reads. These are not evidence that arbitrary preview calls are harmless. Constructing an effect is also not submitting it; this inspection found no proof that ordinary hover executes that effect.

The present guard blocks native inspection input along with commands. This increment does not solve that interaction. A safe adapter must let each human inspect vanilla-visible tiles, actors and relevant teammate actions without permitting their mutations; tag drafts/previews to observed state and invalidate them on changes. Do not simply call arbitrary `GetSkillEffect`, expose hidden state or release the guard around hover. Snapshot display is a possible first component, but not a substitute for usable action previews.

For verification, vary idle inspection, same-target repeated hover, different targets, cancel and teammate-preview histories on equivalent starting states. Retain every recorded field, including unresolved terrain-health differences. Compare both action boundaries and subsequent enemy/spawn/environment outcomes; equal visible snapshots alone do not prove RNG or hidden-state equivalence.

## Persistence boundary

Records are process-local and bounded. `checkpoint()` returns `nil, 'unsupported-non-resumable-experiment'`; there is no resume operation or campaign RNG. A future persistence adapter needs append-only accepted/outcome records and checkpoint association carrying exact build/configuration, session/encounter/entity identities, revision and engine-save identity. A write acknowledgement must not imply atomic engine-save commitment. Ambiguous associations stop recovery. Durable campaign votes, rotation journals and general recovery are deferred until tactical proof.

## Verification and limits

Local `npm test`: 12 mod/experiment files parse as Lua 5.1; 200 Lua contracts pass under Fengari/Lua 5.3, including 26 new shared-session contracts; 11 log-analysis assertions pass. These exercise original Lua diagnostics, but game state, native input, protection and observations are doubles. They cover interleaved guest/host diagnostics, request copying, duplicates/conflicts, ownership, stale/busy intents, validation-time observation changes, fixed attack restrictions, ally omission, guard overlap/loss, uncertainty, bounded records and evidence/read failures.

Inert `tests/install.ps1` fixtures passed without changing the installer or its payload. The tracked-file guard and whitespace checks also passed before publication. Native contract execution remains CI-only while the local antivirus finding is unresolved.

No new game test ran. Earlier single-instance 0.8.0 protection and movement/attack results remain the latest live evidence. No second safely isolated instance or tester has been established. Runtime wiring, independent usable inspection, authenticated ordered transport, real entity mapping, full phase completion and two-instance equivalence remain blockers. A caller-provided witness compares only the fields the caller actually observed; it cannot fill known snapshot gaps. In particular, independent effect/terrain changes during execution and hidden engine state still require a stronger completion/equivalence boundary.

**Single next action:** implement and validate a protected-session inspection adapter before wiring this coordinator into the installed probe. Keep live deployment/testing separate from this source-only approval.
