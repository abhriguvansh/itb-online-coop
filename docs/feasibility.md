# Capability evidence

Reviewed October 12, 2026. **No capability below has been verified in a running game during this project.** Offline tests validate only our code's behavior against explicit doubles.

| Capability | Source/API | Smallest completed check | Result and limit | Confidence |
|---|---|---|---|---|
| Loader/version baseline | Loader v2.9.6, installed exe/Steam manifest | Read version string, hash archive and bundled original DLLs | Exe contains 1.2.93, build 13725832; both original DLLs match. Actual launch pending. | Source/file verified; runtime unknown |
| Observe executed move/attack | modApiExt `onSkillStart`, `onSkillEnd`, queued variants | Inspect injected scripts; exercise callbacks in doubles | Source inserts scripts around execution effects. `Move` uses the same skill path. Empty effects and tip images need runtime checks. Hooks do not provide a cancellable command boundary. | Source verified + offline contract tested |
| Distinguish previews | `onSkillBuild` versus execution hooks | Ten build callbacks produce zero execution records in a double | The probe counts build calls separately. Real hover/preview histories have not been tested. | Offline tested; engine behavior pending |
| Execute legal move | Vanilla `BoardPawn:Move(Point)`; `Move:GetTargetArea`, `Board:GetReachable` | Read wiki and loader movement override | Raw Move ignores normal range and can choose a nearby tile. Need active/movement-spent/target/status validation plus before/after checks. No action wrapper shipped. | Source/documentation only |
| Execute legal attack | Vanilla `BoardPawn:FireWeapon(Point, index)` | Read docs and memedit scanner call sites | Can fire after a pawn's turn. A true return is not complete legality evidence. Must validate player phase, active state, power, charges, target, and status; prove action consumption and pushes. No action wrapper shipped. | Source/documentation only |
| Gate local input | Loader `onKeyPressing`; native `sdl.eventHook` and UI event consumption | Inspect short-circuit event dispatch and UI handling | Keyboard cancellation exists in source. Mouse coverage, controller exclusion, undo/reset/menu shortcuts, event order and reentrancy are untested. No gate implemented. | Source lead; end-to-end blocking unknown |
| Detect settled state | `onMissionUpdate`, `Board:IsBusy`, `pawn:IsBusy`, `modApi:elapsedTime` | Busy/missing state resets; stable samples and context resets tested | Three unchanged idle samples 100 ms apart produce `settled_candidate`. Hidden callbacks/effects can outlive this heuristic. Never used to accept commands. | Offline tested; quiescence unproven |
| Read partial state | Vanilla Board/Pawn/Game getters; optional memedit getters | Snapshot contracts, unavailable fields, ordering, failed busy reads | Records tiles, visible pawn state, turn/team/grid. Read errors are explicit. No full export/import or cross-PC entity mapping. | Source-backed adapter; runtime pending |
| Enemy/environment phases | `onNextTurn`, environment/plan/spawn hooks; queued skill hooks | Verify hook definitions; observer wiring tested | Phase notifications are observable source entry points. They do not control AI, spawn choices or RNG. Replay and authoritative restoration unproven. | Source verified; synchronization unknown |

## Pinned evidence

- Loader [bootstrap/modApi.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/bootstrap/modApi.lua) defines phase hooks and shortcut events; lines 148–162 mark key events as short-circuiting.
- Loader [modui/root.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modui/root.lua#L327) consumes SDL events based on callback returns. This is an interception lead, not a complete authorization gate.
- modApiExt [scripts/alter.lua](https://github.com/itb-community/ITB-ModUtils/blob/21bcb56ba674aaaa6a940118b1cd527dfd38401b/scripts/alter.lua#L475) distinguishes effect building from injected execution scripts; [scripts/compat.lua](https://github.com/itb-community/ITB-ModUtils/blob/21bcb56ba674aaaa6a940118b1cd527dfd38401b/scripts/compat.lua#L31) identifies Move within that path.
- modApiExt [scripts/hooks.lua](https://github.com/itb-community/ITB-ModUtils/blob/21bcb56ba674aaaa6a940118b1cd527dfd38401b/scripts/hooks.lua) creates `onSkillStart`/`onSkillEnd` events. Event subscriptions persist across loader reloads; the probe subscribes once and resets its own observation epoch on load/context changes.
- [Vanilla Pawn docs](https://github.com/itb-community/ITB-ModLoader/wiki/%5BVanilla%5D-Pawn#move) describe Move and FireWeapon's permissive behavior. The loader's [movement target override](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/skills.lua#L58) supplies a range-based candidate for standard movement.
- [Vanilla Board docs](https://github.com/itb-community/ITB-ModLoader/wiki/%5BVanilla%5D-Board) document observed tile getters and IsBusy. They make no promise that it drains every pending callback.
- memedit [functions/pawn.lua](https://github.com/itb-community/memedit/blob/24fb9af025d06fa225f645cb482f992208f17e04/functions/pawn.lua#L667) defines IsMovementSpent; queued-target and weapon getters are in the same file. Its [address table](https://github.com/itb-community/memedit/blob/24fb9af025d06fa225f645cb482f992208f17e04/__addresses.lua) includes 1.2.93. The observer does not require enabling memedit; absent reads remain unavailable.
- Loader [modapi/data.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modapi/data.lua) defines profile lookup; [modapi/init.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modapi/init.lua) shows the loader's resource.dat backup/restoration on launch.

## Missing state

RNG state, engine effect/callback queues, full mission script state, spawn plans, weapon power/charges, pilot abilities, off-board pawns, and campaign state are excluded. Queued targets and movement-spent state may also be unavailable without memedit. Tiles do not cover all specialized terrain/item/objective properties. Visible state is not sufficient to certify equality of full simulation state.

State SHA-256 is computed offline over sorted JSON keys. Equality means only equality of captured fields, including missing-field markers. It is neither a full-state hash nor a resynchronization method. Explicit local pawn IDs remain local until an independently validated mapping exists.

## First blocking experiment

Load the probe on a disposable profile; compare preview-only activity with one manually committed standard move and one standard attack. Preserve the log and confirm snapshot fields against the visible board. Only then implement one carefully validated programmatic action. If Lua lacks a needed pre-commit boundary or state function, specify that exact gap before investigating a narrow native extension.
