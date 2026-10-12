# Skill-effect movement experiment — 0.2.2

**Result: effect submission relocates the pawn and the position survived one save/reload, but it still does not consume movement or establish undo. This is a failed legal-movement path.**

## Exact scope

October 12, 2026; one Windows Steam instance, game 1.2.93/build 13725832, loader 2.9.6, modApiExt 1.25, calibrated memedit 1.2.2. Same disposable profile, standard Rift Walkers, Normal difficulty, no advanced content or Easy Edit, `Mission_Artillery`, player turn 2.

Version 0.2.2 selects the `effect` diagnostic in `init.lua`; the earlier native path remains in the module and offline regression tests. Both start disarmed and share the existing profile, mission, phase, terrain, pawn, reachability, freshness, and pending-action checks. The UI now says **Enable effect lab**. It is not a multiplayer input gate.

After validating one adjacent move, the effect path obtains `Board:GetPath`, requires exactly the origin and destination, builds one `SkillEffect`, calls `AddMove(route, FULL_DELAY)`, and submits it once with `Board:AddEffect`. It does not call `Move:GetSkillEffect`, replace global `Pawn`, inject imitation skill hooks, set allowance/undo flags, force a save, or fall back to `BoardPawn:Move`. Consequently this tests the movement primitive, not the entire normal Move commitment wrapper.

The pinned loader's [standard ground-move builder](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/skills.lua#L28) uses this movement primitive. [Board documentation](https://github.com/itb-community/ITB-ModLoader/wiki/%5BVanilla%5D-Board#addeffect) describes AddEffect as a void-returning effect submission. A nil return is therefore recorded, not treated as proof of failure or success. These sources do not promise player-action bookkeeping.

## Real-game result

Artillery ID 2, (1,3) → (0,3), the same route as the earlier native and normal-move tests:

| Check | Before submission | After five-second outcome check | After Save and Quit / relaunch |
|---|---|---|---|
| Position | (1,3) | (0,3) | (0,3) |
| Movement spent | false | **false — failure** | false |
| Undo possible | false | **false — failure** | Not captured by reload candidate |
| Undo origin | (1,3) | (1,3) | Not captured by reload candidate |
| Health / active | 2 / true | 2 / true | 2 / true |

Records 7–8 contain exactly one request and one successful, nil-returning effect submission. Record 9 observes the destination; record 10 reports failed postconditions and faults/disarms the lab. No retry was issued. The fault prevents further arming until process restart; that behavior remains covered offline. There were no Move execution hooks, as expected for direct primitive submission outside modApiExt's skill wrapper. Hook absence alone is not the failure: unchanged movement allowance and unavailable undo are.

The first log has 10 probe records; the reload log has five, including the reloaded candidate at sequence 5 and no lab actions. Both game error files are empty; neither log has capture failures or missing-hook records. Reload persistence passes only for the observed position, health, activity, and unchanged allowance. It does not establish a complete saved action.

## Correction to the earlier persistence interpretation

Before this effect experiment, resuming the preceding **normal UI move** also restored Artillery to (1,3) with movement unused. Thus the earlier native move's return to its origin cannot be attributed specifically to its scripted path. Normal move finalization, undo handling, and save timing need a separately controlled comparison. The effect experiment above did retain its changed position across a directly observed Save and Quit / relaunch. No cloud conflict was shown. Do not infer a general save rule from these few sessions.

## Evidence and protection

Seventeen save-area files were backed up and hash-verified before the scoped installation while the game was closed. Both exits used the game's Save and Quit button. Final window inventory confirmed closure; Steam showed Cloud up to date before launch, between launches, and after the final exit. No Cloud settings changed. All four normal-profile files matched their pre-test hashes.

Private evidence: `.local/evidence/effect-0.2.2/`, subfolders `before-reload` and `after-reload`, containing full logs and reports, plus normal-profile hash checks. Before-reload log SHA-256: `68806947722356210ba96c0f0b58debec7c089177501b18dc8ef46d99cf6af0c`. After-reload SHA-256: `d66a627bcc1deb7175e148536a42f3d9c9b8fa6002fb97124fe23bc2acd0ef37`. Raw evidence, saves, and binaries stay out of GitHub.

Offline checks: eight Lua 5.1 syntax parses, 19 observer / 48 movement / ten trace contracts, eleven report assertions, and installer fixtures. Seven new movement contracts check effect submission, validation before submission, path shape, exceptions/no fallback, missing undo, wrong undo origin, and the distinction between observed postconditions and persistence. These tests use engine doubles.

## Repeat and next investigation

Back up first, install 0.2.2 while closed, select the supported disposable scenario, and use **Enable effect lab** followed by one available mech button. Wait for the outcome check; preserve the failure log before relaunching. Save and Quit, relaunch with the lab off, compare the first candidate, then close and preserve that second log. Do not repeat this known-failing primitive as a candidate legal executor.

Two direct movement primitives have now failed allowance/undo equivalence. The next investigation is the native player-command boundary: determine whether the existing loader exposes the complete accept/commit operation or whether a narrow native extension is required. Audit input interception alongside that boundary, and specify the missing operation before writing an extension. Do not add bookkeeping setters merely to make this experiment pass, and do not add transport while legal action execution remains unresolved.
