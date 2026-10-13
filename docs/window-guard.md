# Game-window input guard — 0.7.1 experiment

## Evidence status

Game-verified on the disposable profile: one tagged Artillery move completed during the 20-second guard; a competing Undo click left the observed state unchanged; after expiry, Undo restored origin and movement allowance. This does not establish complete multiplayer authorization. Local DLL compilation and 154 Lua contracts plus 11 log-analysis assertions pass. Native executable contracts run only on GitHub's Windows runner; consult the exact revision's Actions result.

## Live evidence — October 12, 2026

The initial 0.7.0 run failed safely: tagged approach motion reached SDL, but final motion did not, leaving the Windows and SDL cursors different. No destination click or movement execution occurred. The lab timed out without changing the pawn, and the 20-second guard released. Windows motion coalescing was the working hypothesis, not a proven root cause.

Version 0.7.1 adds `MOUSEEVENTF_MOVE_NOCOALESCE` to bridge motion and a bounded trace of the first 16 mouse messages. It retains the strict marker check. The retry trace showed both tagged approach/final motions reaching the window, interleaved with untagged same-position motions which were blocked. No coordinate-based exception was added.

- Sequence 21 verified the fresh native preview for Artillery 2, (0,2) to (1,1). Sequences 24/27 recorded Move execution start/end. Sequence 31 confirmed movement consumed, HP 2 unchanged, active true and undo origin (0,2).
- Sequence 32 recorded two submitted clicks, two releases and eight tagged messages passed, with about 19 seconds left on the guard. Seven untagged mouse messages had already been blocked; these are not all competing user actions.
- A normal automated click on Undo during the remaining countdown did not undo the move. At expiry, sequence 33 recorded 13 blocked mouse messages and zero held tails. Its entire partial state equals the post-move settled candidate at sequence 30 (zero field differences).
- The next Undo click completed after guard expiry: sequence 34 is the undo hook, and sequence 35 shows only Artillery position (1,1) to (0,2) and movementSpent true to false changing in the partial snapshot. This supplies the positive control; it was not a second confirmed blocked attempt.
- The game was saved and closed normally. Steam showed Cloud up to date. The error file was empty and all four normal-profile files matched the pre-run hashes. The moved position was undone before saving; this run is not a new movement-persistence test.

Private evidence: `.local/evidence/window-guard-0.7.0-failed/modloader.log`, SHA-256 `aa2ead4a6dbf672d57196c1f471b6a9e0051581c16e820a92eb405827329b7dc`; successful retry `.local/evidence/window-guard-0.7.1/modloader.log`, SHA-256 `9941fc683f3c8c971ca0d14e69387000712f91f44701891577b3eca46d7d8dd1`. Tested DLL SHA-256 `2b52c5df0c8e07abb78e6f53429d0eaf8768445ab645694c304e20a7cc290aa3`. Raw logs and binaries remain untracked.

The new guard still needs live keyboard/menu, available Reset, held-across-expiry and focus-loss checks. Earlier SDL-gate evidence does not transfer automatically. The diagnostic trace records mouse message identifiers, coordinates and extra-info markers only; it does not record keyboard text.

## Boundary

The earlier SDL event gate ran after the loader UI. The new original `native/window_guard.h` installs a callback on the exact game window, on its owning thread, using Microsoft's [SetWindowSubclass](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-setwindowsubclass). The callback filters ordinary client mouse and keyboard messages before the original window procedure. It forwards unrelated window messages and the close path. No global hook, driver, service, game address or gameplay setter is used.

The bridge already marks its mouse input with `MOUSEINPUT.dwExtraInfo`. The callback reads [GetMessageExtraInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessageextrainfo) and allows only marked mouse motion and left-button edges. The marker is a cooperative discriminator, not authentication against malicious software. Tagged keyboard input is still blocked. Raw input is discarded through [DefWindowProc cleanup](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-input). Controllers, touch, external mods and separately polled OS state are not proven covered.

Each movement command requires the window guard; missing installation, wrong thread/window, focus loss, held input or expiry prevents further submissions. Automatic command guards last at most five seconds. The optional **Guarded move + lock 20s** button submits one validated unused mech move and keeps the guard active for a 20-second diagnostic interval. All ordinary game-window clicks and keys, including the lab's own buttons, are blocked during that interval. This allows attempts at Undo, End Turn and shortcuts after the scripted move. It releases automatically; no user action is needed to unlock.

Suppressed presses remain tracked after expiry until their releases arrive; fresh presses then pass. Focus loss aborts the command and ends active filtering while preserving tracked release tails. Expiry is checked by window callbacks and regular status polls; a frozen game cannot run either, but the guard does not affect other applications. Callback code does not call Lua. The DLL is pinned for the process lifetime to prevent a dangling callback during Lua teardown; destruction removes the subclass. Counters describe blocked message classes and tagged passes without recording key text.

This is an opt-in, bounded diagnostic that releases on failure/timeout. A future multiplayer session needs a distinct stopped-session policy, ownership validation, controller policy, and confirmed blocking for every supported mutation route. One Undo route now has paired evidence; Reset remains untested. Never promote its mocked contracts into real-game evidence.

## Planned live check

Back up the disposable profile and normal-save hashes, install with the game closed, and confirm the new ABI loads. Prepare an unused supported mech using normal game controls. Arm the movement lab and select **Guarded move + lock 20s**. Require a completed tagged move with consumed movement, native execution hooks and undo bookkeeping while the guard remains active. Attempt Undo and menu/keyboard routes during the remaining interval; compare state after the move with guard-end state. After release, repeat Undo as a positive control. Preserve failures, close through Save and Quit, verify normal hashes and Cloud status. Reset needs an actually available reset and a paired control; a disabled button is not evidence.

Norton's earlier `native-tests.exe` alert remains unresolved. No local native test executable is run, no quarantine item is restored, and no antivirus exclusion is part of this workflow.
