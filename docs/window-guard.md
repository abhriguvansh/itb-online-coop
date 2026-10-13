# Game-window input guard — 0.7.0 experiment

## Evidence status

Source implemented and local DLL compilation passed. The Lua suite passes 154 contracts plus 11 log-analysis assertions; installer fixtures pass. Native executable contracts run only on GitHub's Windows runner. Real-game results are pending. The established game evidence remains [0.6.0 movement](ui-movement.md); this experiment is not multiplayer authorization.

## Boundary

The earlier SDL event gate ran after the loader UI. The new original `native/window_guard.h` installs a callback on the exact game window, on its owning thread, using Microsoft's [SetWindowSubclass](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-setwindowsubclass). The callback filters ordinary client mouse and keyboard messages before the original window procedure. It forwards unrelated window messages and the close path. No global hook, driver, service, game address or gameplay setter is used.

The bridge already marks its mouse input with `MOUSEINPUT.dwExtraInfo`. The callback reads [GetMessageExtraInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessageextrainfo) and allows only marked mouse motion and left-button edges. The marker is a cooperative discriminator, not authentication against malicious software. Tagged keyboard input is still blocked. Raw input is discarded through [DefWindowProc cleanup](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-input). Controllers, touch, external mods and separately polled OS state are not proven covered.

Each movement command requires the window guard; missing installation, wrong thread/window, focus loss, held input or expiry prevents further submissions. Automatic command guards last at most five seconds. The optional **Guarded move + lock 20s** button submits one validated unused mech move and keeps the guard active for a 20-second diagnostic interval. All ordinary game-window clicks and keys, including the lab's own buttons, are blocked during that interval. This allows attempts at Undo, End Turn and shortcuts after the scripted move. It releases automatically; no user action is needed to unlock.

Suppressed presses remain tracked after expiry until their releases arrive; fresh presses then pass. Focus loss aborts the command and ends active filtering while preserving tracked release tails. Expiry is checked by window callbacks and regular status polls; a frozen game cannot run either, but the guard does not affect other applications. Callback code does not call Lua. The DLL is pinned for the process lifetime to prevent a dangling callback during Lua teardown; destruction removes the subclass. Counters describe blocked message classes and tagged passes without recording key text.

This is an opt-in, bounded diagnostic that releases on failure/timeout. A future multiplayer session needs a distinct stopped-session policy, ownership validation, controller policy, and confirmed blocking for every supported mutation route. Undo/reset are not yet claimed covered by this new guard. Never promote its mocked contracts into real-game evidence.

## Planned live check

Back up the disposable profile and normal-save hashes, install with the game closed, and confirm the new ABI loads. Prepare an unused supported mech using normal game controls. Arm the movement lab and select **Guarded move + lock 20s**. Require a completed tagged move with consumed movement, native execution hooks and undo bookkeeping while the guard remains active. Attempt Undo and menu/keyboard routes during the remaining interval; compare state after the move with guard-end state. After release, repeat Undo as a positive control. Preserve failures, close through Save and Quit, verify normal hashes and Cloud status. Reset needs an actually available reset and a paired control; a disabled button is not evidence.

Norton's earlier `native-tests.exe` alert remains unresolved. No local native test executable is run, no quarantine item is restored, and no antivirus exclusion is part of this workflow.
