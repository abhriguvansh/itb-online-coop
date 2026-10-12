# Native command and input boundary audit

**October 12, 2026 — source investigation, not a new game test.** The reviewed native loader has an input-event consumption path before an event is returned to the game. Its exposed Lua bindings do not provide event submission or a complete player move-command API. This supports a bounded input-interception experiment using the existing installation; it does not yet justify claiming reliable action execution or requiring a new DLL.

## Provenance

The pinned loader's [maintainer guide](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/MAINTAINERS.md) points native-library development to `kartoFlane/IntoTheBreachLua`. The original author's repository linked by the README was inspected first, but the maintainer-designated fork is the authority for this audit.

The installed `SDL2.dll` SHA-256 is `7f0765d37a0b3f9946c501be04a55a8e8c63549710675de4311a4579fe8f432a`, identical to the file in the pinned loader checkout. Upstream's [last SDL2.dll update before that tag](https://github.com/itb-community/ITB-ModLoader/commit/276a70de3e47236602a209ad64d98d2780587984) names native-source PRs 10 and 11. PR 11 merged at `4ecc4a74ee62871fb8a91fd590330b9684553839`. The inspected fork head, `dcf22e726088f9f1ab788c693a59259450e31ef6`, differs from that revision only in README links. The relevant source files are identical.

This is binary identity plus an upstream source-history connection, **not** a reproducible-build proof or verification of every installed machine-code instruction. Source copies remain private under `.local/upstream/`. No native code was compiled, installed, or redistributed.

## Findings

| Question | Evidence | Consequence / limit |
|---|---|---|
| Can a polled event be withheld from the game? | [sdl-hooks.cpp, SDL_PollEvent](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/sdl-hooks.cpp#L35) reads the original event, calls hooks, and only returns an unhandled event to the caller. A true hook result consumes it. | A source-backed pre-delivery interception point exists. Whether every gameplay input uses this route still needs a game test. |
| Does a later hook run first? | [sdl-utils.cpp](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/sdl-utils.cpp#L868) appends hooks to a vector; PollEvent iterates forward and stops at the first handler. | A probe installed after the loader UI cannot prevent effects already performed by an earlier Lua/UI handler. Native event suppression is not automatically a complete mod-input gate. |
| What happens if a hook throws? | [Lua EventHook wrapper](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/lua-functions.cc#L95) catches a Lua exception, reports it, and returns false. Loader [Event:dispatch](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/bootstrap/event.lua#L292) also continues after ordinary callback failures. | An exception does not safely block an action. A diagnostic must contain its own failures; a future multiplayer gate must stop the session without accidentally passing gameplay input. |
| Can Lua construct and submit an input event? | [Lua bindings](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/lua-functions.cc#L265) expose event construction, getters, event hooks, and an event loop. No event setters or queue-submission binding appears in the reviewed registration file. | Constructing `sdl.event()` is not evidence of a usable synthetic command. Do not invent a `pushEvent` Lua API. |
| Would editing a hook's event replay it? | PollEvent copies the event into a wrapper and does not copy it back to the original pointer before returning. The reviewed Lua event surface exposes getters only. | Mutation/replacement is not an available submission mechanism in this interface. |
| Does `sdl.eventloop:next()` submit events? | [EventLoop::next](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/sdl-utils.cpp#L875) calls SDL_PollEvent. | It consumes events. Do not run a second event-draining loop inside a tactical diagnostic. |
| What about native SDL_PushEvent? | [exports.def](https://github.com/kartoFlane/IntoTheBreachLua/blob/4ecc4a74ee62871fb8a91fd590330b9684553839/exports.def#L345) forwards PushEvent, PeepEvents, and state getters as DLL exports; only PollEvent is hooked there. | A DLL export is not a Lua binding or a game move command. Queue injection would still depend on selection, camera, UI state, and physical input state. It is not proven command execution. |
| Are mouse/keyboard state queries covered? | Mouse coordinates use SDL_GetMouseState; GetMouseState and GetKeyboardState are forwarded separately. | Consuming a queued event does not prove that polled state is blocked. Held keys/buttons and alternate input routes remain test cases. |
| Is there an earlier keyboard hook? | Loader [modui/root.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modui/root.lua#L327) dispatches onKeyPressing/onKeyReleasing before uiRoot:event. | Useful keyboard interception lead, but subscription order and exception behavior still matter. Mouse coverage is separate. |

The reviewed native registration file and memedit function surface did not identify a complete player-command accept/commit operation. This is a bounded negative finding, not proof that the closed-source game lacks such an operation. The two previously tested relocation primitives remain known failures of normal bookkeeping.

## Missing operation, before considering an extension

The needed behavior is a game-thread operation that takes a validated actor and destination and follows the engine's normal movement acceptance/finalization path. It must preserve movement consumption, action availability, native undo bookkeeping, effects, mission callbacks, and the game's save semantics. A rejected or stale request must not change gameplay. Completion must be distinguished from queuing and from a merely returned value.

These are **requirements, not implemented API names or discovered native addresses**. There is no justified function address, calling convention, structure layout, or extension implementation yet. A memory setter for movementSpent or an exported SDL function does not fill this gap.

Before adding a native component, resolve whether an existing supported interface can reach that operation. If none is found, a narrow extension needs exact-build identification, a verified native call site/signature, game-thread execution, an explicit supported input contract, lifecycle handling, and independent before/after comparison with a normal action. Do not call guessed addresses or replace the installed proxy to explore this speculatively.

An SDL event-submission bridge would be a different design: it would need local UI-state synchronization, coordinate translation, synthetic/physical input separation, and proof that each requested action enters the normal engine path exactly once. That is a research alternative, not the selected executor or a substitute for two real game instances.

## Next runnable experiment: bounded event-consumption lab

Use the existing loader to establish whether its source-backed interception point actually blocks the chosen mouse/keyboard actions on the disposable profile. Probe 0.3.0 completed the initial mouse test with a positive control; see [results and remaining coverage](input-gate.md). The steps below remain the test protocol; Tab and Escape now have bounded keyboard coverage through a verified scan-code helper; held-input and broader route coverage remain incomplete.

1. Back up and preserve current evidence. Start in the named disposable profile with the movement-effect lab off. Record one selected pawn, turn, grid, and action availability before arming.
2. Add a manually armed, visibly labeled, time-bounded input diagnostic. Retain the hook object for its lifetime. Keep context changes, exceptions, and emergency exit behavior explicit; it must not trap the user indefinitely. A diagnostic timeout is not an acceptable multiplayer fail-open policy.
3. Consume paired mouse down/up and relevant key down/up events, track suppressed presses through release, and log bounded scalar event metadata plus the rejection decision. Cover held inputs and release at the timeout boundary. Do not drain the event queue or modify gameplay fields.
4. Attempt a legal board move and end turn while blocked; compare before/after state and confirm no corresponding execution/phase transition. After disarming, repeat one normal action as a positive control so ignored injected input cannot masquerade as a successful gate.
5. Test repair, weapon shortcuts, undo, reset, menu routes, and focus changes separately. Identify any earlier loader handler or polled-state bypass. Unsupported controller paths remain outside the declared mouse/keyboard scope and cannot be claimed blocked.
6. Any unblocked mutation is a failed gate; preserve the event/state sequence and stop. Passing selected controls establishes only their bounded coverage, not full authorization or quiescence.

The initial gate and keyboard follow-up are complete within their stated scope. The next investigation is legal movement submission, including whether a UI-event bridge can reach normal commit handling without relying on selected units, fixed screen coordinates or untagged physical input. Transport remains deferred.

## Movement follow-up after the attack milestone

The pinned modApiExt scheduledMovePawns code is enemy-movement observation: it stores the starting position of a selected Vek and waits for the board to stop being busy. It does not submit a player move. The reviewed FireWeapon callers use equipped weapon slots; no source-backed Move slot was identified. Do not try undocumented slot numbers.

Loader [global.lua](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modapi/global.lua#L110) provides GetUiScale, getScreenRefs and screenPointToTile using current screen dimensions and GetBoardScale. [Board selection helpers](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modapi/board.lua#L133) read the selected pawn by checking IsSelected; they do not select it. These are concrete building blocks for validating a UI bridge's geometry and selection, not an input-submission API. No native extension was installed in this follow-up.

A bridge experiment must first round-trip its calculated tile centers through the loader's conversion, confirm the selected actor and unarmed movement mode, submit exactly one destination press/release through the ordinary game path, and require movement consumption plus native undo and execution hooks. It must reject a stale selection, changed phase, modal, resolution change or competing input. Save/reload must be checked because the prior normal-move persistence discrepancy remains unresolved. An assistant clicking a tile alone is only a baseline control; it is not a replay implementation.
