# Legal movement through the native UI — 0.5.10

## Result

On October 12, 2026, two fresh-process tests moved Artillery from (0,3) to (0,2) through the game's normal input path. Both consumed movement, preserved HP 2 and the ability to attack, emitted Move execution start/end hooks, and established undo at (0,3). The first test used the game's Undo button: the mech returned to (0,3) with movement available. The process-level one-call lockout remained in place.

The second test followed that move with the existing Combat Mech punch: Hornet 101 lost two HP (3 to 1), moved (2,3) to (1,3), and Combat became inactive. After Save and Quit, Steam Cloud reported up to date. Relaunch retained **all observed pawn fields**, including Artillery's destination and spent movement, Combat's consumed action, and the Hornet's damage/push/queued target. No game-state setters or save edits were used to produce these results.

This completes a **bounded single-instance movement/attack/undo milestone**, not a general executor or playable co-op. The move is deliberately restricted to one actor, route, mission, profile, and calibrated layout. Two clear-ground tile health readings changed from 2 to 4 on reload: (0,3) and (2,3). All other captured fields matched. Full observed-state equality therefore failed; the discrepancy remains unresolved. This observation must not be silently excluded from future synchronization comparisons.

## Mechanism and diagnosis

`native/input_bridge.c` is original project code. It dynamically resolves public Lua 5.1 and SDL2 APIs and uses Windows mouse input in the foreground game process. It uses no game addresses, game-state writes, network listener, persistent service, or event-filter replacement. One session lasts at most five seconds and permits at most two presses: selection and destination. A separate 80 ms timer submits button release even if Lua frames stop advancing.

The Lua coordinator validates the command and layout, moves the pointer near the intended point, waits for a frame/coordinate agreement, then sends a distinct final pointer movement and waits again. It observes the selected actor and **Move skill index 0** before submitting the destination. Receiving input is never treated as completion: allowance, undo, HP, active state, position and execution hooks determine the observed result.

Two source findings explain the final correction:

- The loader dispatches mouse input using hover state refreshed on draw. The first motion leaving the lab button can be consumed using its previous hover state. In 0.5.9/0.5.10, the read-only hook registered after the loader saw the second motion and both button edges, and native selection succeeded. This supports the stale-hover diagnosis for that setup; it is not an audit of every possible UI layer.
- The pinned loader's [`BoardPawn.GetArmedWeapon`](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/modapi/pawn.lua#L387) maps index 0 to `Move`, 1/2 to weapons and 50 to repair. The earlier guard accepted only -1 and incorrectly rejected the successful movement selection. Runtime 0.5.10 recorded actor 2 with index 0.

The tested layout reports SDL drawable size 1920×1081, scale 3, although captured game images were 1920×1080. Calibrated coordinates are (708,323) and (792,260). Windows delivery sometimes landed one pixel away; a one-pixel tolerance is allowed only when Windows and SDL agree and the actual point maps to the intended tile. Other routes/layouts are rejected before native arming. The +34 vertical adjustment is empirical, not a general projection formula.

## Preserved failures

| Version | Actual outcome |
|---|---|
| 0.5.0 | Native module loaded; no suitable route, no input submitted. |
| 0.5.1–0.5.2 | Queued SDL events accepted but no native selection/move; faulted. |
| 0.5.3 | Windows press/release accepted after SDL warp; selection failed. Independent normal UI move/undo control passed. |
| 0.5.4 | Strict 1080-height calibration rejected the actual 1081 layout before input. |
| 0.5.5 | Calibrated lower-tile point with SDL warp still failed selection. |
| 0.5.6–0.5.7 | Windows motion delivered; strict cursor equality rejected/waited on one-pixel rounding. |
| 0.5.8 | Rounded cursor accepted, but first-motion handling still prevented selection. |
| 0.5.9 | Distinct second motion reached native handling; actor selected; incorrect weapon-state guard stopped destination submission. |
| 0.5.10 | Two complete movement passes, undo control, subsequent punch, persisted pawn outcomes. |

Failed attempts remained locked out until restart. Earlier direct `Move` and `AddEffect(AddMove(...))` failures remain documented separately and are not repaired by flag setters.

## Evidence and limits

Private originals on the originating machine:

| File under `.local/evidence/` | Relevant records | SHA-256 |
|---|---|---|
| `ui-bridge-0.5.10-move-undo/modloader.log` | One move request, one selection, one destination, one Move execution pair, passed postconditions, undo observation and restored pawn state | `460ca1d7201ce79dd4ec9fd7d52aef6909161577a24fc069ce2a8dcff048aae8` |
| `ui-bridge-0.5.10-move-attack/before-reload.log` | Move result 28; attack result 36; settled candidate 37 | `4b5f376ab16582169b3f16dccd221883251a073b684346660f13a1d29e6a2f05` |
| `ui-bridge-0.5.10-move-attack/after-reload.log` | Settled candidate 6, compared with 37 above | `3c725efaa74cb4e38d4420f697f40198924b409b074a1a6ac99792baa9885bd7` |

Hashes identify retained evidence, not independent verification. Raw logs, saves, binaries, upstream headers and account details remain private. The final game error file was empty; all four normal-profile files matched their pre-experiment hashes. Steam Cloud showed up to date after the final exit. Single-instance checks do not establish two-PC save isolation.

The bridge requires foreground focus and an idle operator. It checks held input, process/window ownership, timeout, coordinate agreement and press budget, but cannot make a Windows focus check and input delivery atomic. A failed button release is recorded and prevents subsequent commands; OS-level release failure is not proven recoverable. This is a diagnostic bridge, not a production multiplayer authorization layer. Undo/reset remain observed, not blocked. No general route coverage, automated two-player ownership, transport, enemy-phase reproduction, complete quiescence or resynchronization is implemented.

## Build and tests

The portable build uses Zig 0.14.1 targeting 32-bit Windows, Lua 5.1.5 headers, and the SDL headers from native source revision `dcf22e726088f9f1ab788c693a59259450e31ef6`. Runtime is restricted to the tested SDL 2.0.10 ABI. `Prepare-NativeSdk.ps1` obtains pinned inputs under ignored `.local/`; it does not run or install them. Compiler and Lua archives have SHA-256 checks, and SDL headers are selected by exact Git revision.

```powershell
./tools/Prepare-NativeSdk.ps1
./tools/Build-Native.ps1 -ZigPath .local/native-ci/zig-x86_64-windows-0.14.1/zig.exe -LuaHeaders .local/native-ci/lua-5.1.5/src -SdlHeaders .local/native-ci/native-source/sdl
```

Output is `.local/native-build/itb_input.dll`. Compilation treats warnings as errors. No game launch or installation occurs. To install after reviewing the build and closing the game, uninstall the owned probe first, then pass `-NativeBridgePath .local/native-build/itb_input.dll` to `Install-Probe.ps1 -Mode Install`.

`npm test` covers Lua syntax, command guards and observer contracts using doubles; installer tests use inert files. The native CI job compiles the DLL and runs `tests/native_bridge.c` with `-RunMockTests` on a GitHub-hosted Windows runner. Its OS input function pointers start null in the test build and are replaced by mocks before each test, so there is no fallback to real mouse input. CI is not a real-game test and does not publish binaries.

During development Norton flagged a locally built unsigned `native-tests.exe`. The exact detection was not supplied; a false positive is **not established**. That executable was not rerun after the alert, no exclusion or security-setting change was made, and local validation continued with the DLL build and Lua tests. A separate syntax-only Zig invocation reported `FileNotFound`; it is not counted as a passed C check. Consult the exact GitHub revision's native job for executable contract results. No antivirus bypass is part of setup.

The installed game-tested DLL SHA-256 was `eabe2f049f590f7df518d2d2c5f8904266816b0f419fc1935ed01fc4b1c34cd7`. A later source-only test-isolation macro leaves production function selection unchanged; the build-script DLL was compiled but not reinstalled or represented as a new game test.

## Next milestone

Generalize validated movement beyond this calibration, establish exclusive command ownership while preserving intended synthetic input, block unsupported undo/reset, and resolve observation boundaries and the terrain-health discrepancy. Then demonstrate matching serialized actions on two actual game instances before exposing an online session. Keep the required battle-by-battle 2/1 mech ownership rotation; it is still a future session rule.
