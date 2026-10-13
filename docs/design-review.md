# Game design and implementation review

October 12, 2026. Audited source: `7d59b48d09f413970c8fd9c354b7c1ae372d388e`, probe 0.8.0. Review-only change; no gameplay implementation, game launch, installation or save mutation. The [ruleset](co-op-design.md) separates confirmed requirements from recommendations; the [acceptance plan](co-op-acceptance.md) is future work, not passing test evidence.

## Recommendation

Keep two persistent primary mechs and one shared mech alternating by distinct campaign encounter. Keep interleaved tactical actions, normal game balance, equal ordinary votes with a persisted 50/50 tiebreak, unanimous destructive decisions and same-state readiness. This design does not inherently require extra resources or different enemies. Its feasibility is conditional on complete legal execution, inspection without mutation, checkpoint identity and two-engine synchronization. None of those can be replaced by a successful isolated engine call.

No serious flaw justifies replacing the confirmed ownership or voting model. Several boundary rules do need approval. Most importantly, command serialization is compatible with free interleaving; alternating whole human turns is not. Technical host authority must never imply an extra human vote.

## Evidence ledger

Labels: **G** = previously game-verified within the linked record's scope; **S** = inspected source/official documentation, not a new game test; **O** = offline contract result; **P** = proposed behavior; **U** = unknown. References to installed game scripts are reproducible paths relative to the pinned game's `scripts/` directory; proprietary scripts remain local and are not copied into this repository.

| Evidence | Finding and limitation |
|---|---|
| G: [0.8.0 guard record](window-guard.md) | Protected Cannon move completed. Focus loss/heartbeat expiry kept local input blocked; explicit exit restored Undo/Tab controls. One game process at a time; not network authorization or peer recovery. |
| G: [movement](ui-movement.md), [attack](attack-experiment.md), [move trace](move-trace.md) | Normal UI movement and simple Undo work in selected scenarios. One standard punch consumed action and matched observed outcomes. Direct Move/effect attempts failed bookkeeping. Four terrain-health readings differed in the later reload comparison; general equivalence remains unresolved. |
| S: [Pawn reference](https://github.com/itb-community/ITB-ModLoader/wiki/%5BVanilla%5D-Pawn#fireweapon) | `FireWeapon` can act even when a pawn's turn is over. API availability is not action authorization. Its documented Boolean return disagreed with a numeric live return on this build. |
| S: [Board reference](https://github.com/itb-community/ITB-ModLoader/wiki/%5BVanilla%5D-Board#getreachable) | Reachability is a path/range query. The reference is incomplete in places; `IsBusy` does not establish a complete engine/callback drain guarantee. |
| S: [loader hooks wiki](https://github.com/itb-community/ITB-ModLoader/wiki/Mod-Loader-Hooks#savedataupdatedhook), [pinned bootstrap](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/bootstrap/modApi.lua), [phase/save wrappers](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/misc.lua#L103) | Source has mission-phase, SaveGame and pre/post-load events; wiki coverage is not exhaustive. SaveGame invokes hooks and later refreshes globals. None promises atomic persistence across engine save, sidecar journal and peer. |
| S: installed `missions/final/mission_final.lua:3–24`; loader phase wrapper above | `Mission_Final` explicitly links `Mission_Final_Cave`. This is a real phase relationship, not a new independent mission selection. A phase hook must not rotate the shared mech. Surface start also selects a random boss on Hard/Unfair. |
| S: installed `text.lua:181–228,266–276,367–368,609–625,761–776`; `text_tooltips.lua:112–132`; `pilots.lua`; `advanced/ae_pilots.lua` | Text/definitions identify reputation spending, core-install Undo, donations, lost unspent reputation, perfect-island rewards, carryover, default Reset and its extra allowance. Ability identifiers include Double Shot, post-attack movement, repair replacement and Reset_Bonus. Some tooltip tables are fallback/legacy; exact current localized descriptions and adapter behavior require game controls, not assumptions from text alone. |
| S: installed `weapons_deploy.lua:16–83`; `missions/grass/mission_artillery.lua:40–79`; `advanced/ae_weapons.lua` (TwoClick/GetSecondTargetArea/GetFinalEffect definitions) | Deployables and a player-team support artillery exist beyond squad IDs 0–2. Multi-target weapons have staged target logic. No current co-op entity mapping or general multi-target adapter exists. |
| S: installed `spawner_backend.lua:142,209–245`; loader [drop generation](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/drops.lua) | Scripted random selection occurs in spawn/drop paths. Native AI and other random state remain outside the observation schema. Same command order is not proof of determinism. |
| S: [mod utilities](https://github.com/itb-community/ITB-ModUtils/tree/21bcb56ba674aaaa6a940118b1cd527dfd38401b), especially `scripts/alter.lua`, `hooks.lua`, `compat.lua` as audited in [feasibility](feasibility.md) | Effect-building and execution hooks differ. A start hook is too late to be assumed a universal cancellable pre-action boundary; preview hooks are not executed actions. |
| S: [official game overview](https://subsetgames.com/itb.html), [official Advanced Edition page](https://subsetgames.com/itb_ae.html), [developer patch announcement](https://store.steampowered.com/oldnews/?appgroupname=into+the+breach&appids=590380&enddate=1659337200&feed=steam_community_announcements) | Telegraphed threats underpin tactical planning. Advanced Edition adds squads, pilots, missions, equipment and Unfair; content toggles do not revert its balance changes. These sources do not measure co-op difficulty. |

The game source is version 1.2.93/build 13725832; upstream revisions and binary provenance are in [dependencies.json](../dependencies.json). Source inspection identifies leads and constraints, not guarantees about engine internals. The public loader/wiki is not a multiplayer API. Only primary developer/community-maintainer documentation and inspected code support technical conclusions here; unrelated forum anecdotes were not promoted to evidence.

## Current implementation gaps

Priority: **P0** = architecture/design prerequisite before expanding gameplay; **P1** = before an actual two-PC playable mission; **P2** = campaign continuation; **P3** = polish/optional. Risk describes uncertainty or potential corruption, not effort estimates.

Audited implementation references: [movement validation/submission](../mod/scripts/movement.lua), [attack validation/submission](../mod/scripts/attack.lua), [UI bridge and heartbeat](../mod/scripts/ui_bridge.lua), [native bridge](../native/input_bridge.c), [window filter](../native/window_guard.h), [partial snapshot schema](../mod/scripts/snapshot.lua), [settling heuristic](../mod/scripts/settle.lua), [observer lifecycle](../mod/scripts/probe.lua), [diagnostic UI](../mod/scripts/movement_ui.lua), [native mocked contracts](../tests/native_bridge.c), [UI contracts](../tests/ui_bridge.lua), [test runner](../tests/run.cjs) and [CI configuration](../.github/workflows/checks.yml). File/function references in the table identify these inspected implementations, not hypothetical APIs.

| Feature | Current implementation and evidence | Proposed behavior | Priority | Technical risk |
|---|---|---|---|---|
| Stable players and transport | No listener, identity/session handshake or network tests; full tracked inventory contains probe/adapter code only | Two stable authenticated session seats; bounded ordered messages; same host/guest submission path | P0 design, P1 delivery | High: runtime communication path unselected |
| Primary/shared ownership | `movement.lua` hardcodes IDs 0–2 and Rift Walker types; no human owners | Persistent two primaries + third alternating; dynamic entity registry | P0 model, P1 enforcement | High: local IDs are not cross-instance identity |
| Battle identity/rotation | `probe.lua` clears observation epoch on contexts; no persisted encounter record | Mission-instance ledger; final phase group; no reload/reset advance | P0 | High: entry/save ordering and phase mapping untested |
| Interleaved ordering | Local `pending` flags and process lockouts in `movement.lua`/`attack.lua`; no command sequence or dedup journal | A → B → A allowed, one in-flight mutation, revision-bound requests/results | P0/P1 | High: duplicate/uncertain execution |
| Legal movement | `movement.lua:context/validate/request`, `ui_bridge.lua:start/update`; G bounded paths and O [movement tests](../tests/movement.lua) | Full supported game legality, repeated legal moves across turns, native allowance semantics | P1 | High: fixed mission/layout, status exclusions, pilot exceptions |
| Attack/repair | `attack.lua` is one fixed punch at fixed actor/target/turn, once per process; [attack tests](../tests/attack.lua) | All initial squad attacks plus normal repair in a shared protected lifecycle | P1 | High: general targeting, charges, post-effects absent |
| Protected action lifecycle | `window_guard.h`, `input_bridge.c`, `ui_bridge.lua`; G focus/lease latch | One session state governs every adapter; command failures stop both peers | P0/P1 | High: attack path not integrated with native session fault state |
| Independent inspection/previews | Native ordinary input broadly blocked; bridge manipulates actual selection/cursor at fixed 1920×1081 | Local inspection and owned command previews with stale feedback, no mutations | P0 investigation/P1 | High: preview side effects and bypass routes |
| Complete mutation coverage | G selected Undo/Reset/Tab/Escape routes; held inputs, repair shortcuts/controllers not fully covered | Every supported mutation authorized before engine entry | P1 | High: no blanket protection claim |
| Ready/End Turn | Manual single-player button only, phase observation in `probe.lua` | Both same-revision ready; one end-turn operation and complete phase barrier | P1 | High: late action/ready race, enemy effects |
| Native movement Undo | G paired simple Undo; `onPawnUndoMove` merely observed | Owner request, current native eligibility, no whole-board rollback | P1 target; exception needs approval | High: cross-mech dependencies untested |
| Shared Reset | G button blocking + normal reset control; observer invalidates epoch | Unanimous revision-bound request, native allowance/pilots, monotonic session generation | P1 target | High: restored save state vs session journal |
| State revisions/settling | `snapshot.lua` partial, local IDs; `settle.lua` three unchanged idle samples; [probe tests](../tests/probe.lua) | Revision barrier with complete enough state and verified completion | P0 | Critical: known hidden-state omissions and mid-phase candidates |
| AI/RNG/environment sync | Observed hooks only; no dual execution | Demonstrated equivalent execution or proven sufficient authoritative outcome replication | P0 feasibility, P1 mission | Critical: neither approach established |
| Campaign voting | No vote/decision/RNG implementation or tests | Equal votes, persisted single draw, strict exceptions | P0 schema, P2 UI/adapters | High: durability, stale budget/options, rerolls |
| Campaign resources/rewards | No replicated menus or transactions; excluded by snapshot | One economy; atomic ordered decisions; no duplicated rewards | P2 | High: native UI and persistence |
| Saves/reconnect | Backup/installer tools; profile gate; no co-op save/restore | Canonical host checkpoint + journal; supported-boundary continuation | P0 identity design, P2 continuation | Critical: cross-file crash window, hidden engine state |
| Extra units/special abilities | Observer enumerates board pawns; executor only 3 exact types; special movement rejected | Creator/mission provenance ownership; engine abilities preserved | P1 for selected mission allies; otherwise P2 | High: spawn identity and deferred effects |
| Guest progression/Cloud | Four host normal-profile hashes verified; no guest or Cloud isolation test | Separate profiles; no unlock merge promise; prevent unsupported side effects | P1 isolation/P2 progression | High: platform/profile effects distinct |
| Co-op UI/pings/loans | Local diagnostic buttons only | Clear owners/readiness/status/votes; advisory pings; optional consensual loans | P1 essentials; P2 votes; P3 loans | Medium; input routing prerequisite is high |

### Important code conflicts and smallest corrections

1. **Host campaign authority and unspecified primary assignment:** supersede the old prose with the confirmed specification. Keep a technical host, apply equal votes. No existing network code must be rewritten.
2. **One command per mech/process, fixed IDs and fixed turn:** retain as explicitly labeled diagnostic safeguards. Put future ownership/revisions/dedup in a separate session layer; do not remove the safeguards until a replacement is tested. They cannot become player action quotas.
3. **Whole-window block vs independent previews:** keep failure containment but separate validated co-op UI requests from native game mutation. Test a permitted inspection route before claiming usability. A permissive bypass would undo the achieved safety boundary.
4. **Local Escape exit:** today's state 3 restores normal input and requires restart for bridge use. In real multiplayer this must first invalidate the network session and block further peer admission. Free single-player changes after exit cannot be silently rejoined as the old co-op state. UI Escape should eventually cancel drafts normally; leaving the session needs an explicit visible action. Exact routing is unimplemented.
5. **Separate attack lab:** `attack.lua:context` checks SDL gate/lab state but does not check the native protected session; it calls `FireWeapon` directly and handles its own fault. Ordinary clicks cannot currently reach it under the guard, but this is not defense for a future network caller. All adapters must pass through the same session validator/fault path before networking.
6. **Heuristic snapshots:** preserve their honest `proofOfQuiescence=false` label. Do not rename log `sequence`/`epoch` into authoritative revisions. Add a verified boundary and expanded state schema; classify terrain discrepancies before deciding whether any field can be excluded.

No new hard engine impossibility was established by this review. The known negative evidence is narrower: permissive primitives failed normal bookkeeping; execution hooks are not guaranteed cancellable; native preview/input and save transactions are not exposed as a complete network interface. “Unknown” does not mean impossible, but it is a release gate.

## Five principal risks

1. **Two engines diverge despite matching visible board fields.** RNG, AI planning, queued effects, script state, pilot/weapon state and off-board entities are missing. Unequal preview histories may matter. Compare controlled two-instance runs before committing to replay architecture; no hidden-state repair through guessed setters.
2. **Actions bypass legality or execute twice.** Direct APIs can exceed allowances; real pilots can also legally exceed simplistic quotas. Use authoritative dedup/revisions and native semantics, with at-most-once uncertain submission handling. Test all supported actions, not just movement.
3. **A load/reset/phase transition changes ownership or rerolls decisions.** Type IDs and hook counts are insufficient. Use durable encounter and decision ledgers, monotonic session generations, and checkpoint reconciliation. Atomic engine/journal persistence is unproven.
4. **Protection makes the game unusable or leaks mutations.** The current guard blocks useful inspection and needs peer-aware failure handling. Fixed projection, focus dependence, held tails and alternate input routes constrain the first supported build. Stop both clients on failure without consuming Reset.
5. **Equal votes and equal two-mech turns still feel unequal.** A specialist mech can dominate the puzzle; a disabled sole mech can leave a player waiting; repeated votes or losing streaks can frustrate. Keep owner agency, concise transaction votes and advisory suggestions. Measure experience before adding loans or adjusting difficulty.

## Balance and participation assessment

**Design inference, not a measured co-op result:** two players may catch more threats, but conversation and outdated plans may also increase errors and turn duration. Shared-mech rotation changes the issuer of actions, not the legal tactical solution space, provided all ally interactions and action interleavings are preserved. Do not add enemy health/spawns or grant compensating moves. Easy/Normal/Hard/Unfair provide existing choices; compare squads/pilots and player experience before blaming co-op for difficulty differences.

Support-oriented mechs can be interesting because displacement/shielding enables the whole plan; a high-damage mech is not automatically the more engaging role. Conversely a heavily upgraded shared mech may command most discussion. Team resource votes reduce unilateral favoritism but do not eliminate quarterbacking. Encourage proposals (“can you push this?”), private previews and owner confirmation for ordinary actions. Do not require teammates to approve every shot or penalize legal sacrificial plays.

The fixed 50/50 rule is reasonable for ordinary alternatives, but **per-decision fairness does not guarantee equal wins over a run**. Do not secretly compensate for streaks, use host priority or reweight future flips. A complete deployment/loadout proposal can be internally coherent; separately flipping every tile or upgrade can produce incoherent combinations and too much waiting. Purchases must be mutually exclusive transactions with live budget validation. Permanent losses hidden inside a proposal require the strict unanimous category.

For later squad comparisons, start with Rift Walkers' direct movement/damage/push decisions, then examine smoke-oriented Rusting Hulks and fire/teleport-oriented Flame Behemoths (installed `squad.lua` and `text.lua:974–978`). These create different dependencies between one player's setup and another's payoff; they are not reasons to rebalance damage. Double Shot rewards a stationary plan while post-attack movement changes action order, so a pilot can be strong or awkward depending on the mech and board. Do not impose a universal pilot ranking or claim all combinations are equally engaging. More expert planning could exploit a synergy better; that remains a human-playtest hypothesis.

## Human playtesting

No second PC/tester is confirmed. Do not ask anyone to buy the game for this review. A paper discussion or single-PC design rehearsal may identify unclear rules, but neither demonstrates native online play. Actual acceptance needs two PCs/accounts/copies and the supported mod configuration.

1. **Technical gate first:** complete one supported mission on two copies with independent inspection, all supported actions, ready/Reset/Undo behavior, enemy phase and terminal outcome. Compare logs at verified boundaries. On a divergence, stop and classify; do not score that session as a balance experiment.
2. **First experience sessions:** recruit one similarly experienced pair and one mixed-experience pair if available; with only one pair, label findings preliminary. Play consecutive battles so each controls the shared mech. Repeat with swapped primary choices/setup on a separate run. Include both a displacement/support-heavy role and direct damage role when supported. Use Normal first; later compare the pair's preferred vanilla difficulty, not a custom scaling rule.
3. **Campaign voting session:** when menu adapters exist, deliberately include matched votes, split votes among 3+ options, yes/no rejection, competing purchases, unanimous disposal refusal and leaving a store with reputation. Ask whether each consequence was understood before voting. Do not manufacture RNG outcomes in a real run to create a fairness story.
4. **Participation stress cases:** a constrained deployment/objective map, an extra mission ally, a disabled one-mech player's unit, and eventually summon/ability-heavy squads and Advanced Edition environments. Record whether a loan would have helped; do not revive mechs as a test accommodation. Test after-reset discussion and a temporarily disconnected participant separately.
5. **Collect brief private responses from each player after each battle:** agency/engagement 1–5, understanding of ownership/votes 1–5, frustration 1–5, longest unwanted wait, whether they felt pressured to follow instructions, one useful contribution unrelated to kills, and one blocked tactical idea. After a battle pair, ask which role they preferred and why. Keep teammates' initial responses separate to reduce social pressure.

With consent, log timestamps for planning, submission, resolution, stale rejection, ready/unready, vote open/resolve and stopped sessions. Distinguish engine/network wait from voluntary discussion. Count lost intentions, confusing restrictions, and repeated voting subjects, not kills/damage as fairness. Compare battle-pair enjoyment and turn times with a rough solo baseline of similar difficulty; different randomized missions and practice effects prevent a causal claim of “co-op is X% easier.”

**Go/no-go:** any unauthorized/duplicate action, rerolled committed vote, extra reward/reset, wrong ownership rotation or desync is a correctness blocker. A reproduced legal tactic denied by the mod is a compatibility defect, not balance. Repeated long unwanted waits, low agency or misunderstood votes trigger UI/loan design review. Do not tune enemies from a small sample. Fixed numerical engagement targets should be set after a pilot session provides a baseline.

## Decisions for approval

The two primary mechs, alternating third, equal 50/50 ordinary vote and confirmed unanimity categories are settled. The following fill gaps; defaults remain proposals until approved.

| ID / decision | Options and recommended default | Benefit / cost | Complexity | When needed |
|---|---|---|---|---|
| R1 First shared controller | **Agree at setup; one persisted fair draw if no preference**; alternatives: always a named player or fixed host | No permanent host privilege; one setup choice | Low after persistence | Before ownership implementation |
| R2 Primary reassignment | **Fixed for first release; optional mutual swap between battles later**; alternative: allow immediately | Attachment/simple persistence; delays flexibility | Low to defer, medium to support | Scope now, feature later |
| R3 Battle boundary | **Entered mission selection plus linked phases is one encounter; final surface+cave count once**; alternative: only successful completions advance | Resists reload/phase exploits; requires reliable instance mapping | Medium/high | Before ownership implementation |
| R4 First playable scope | **Pinned base-content Rift Walkers/Normal, no action-altering pilots, one fully supported mission**; alternative: broader squads/AE immediately | Earlier honest playable test; restricted configuration | High either way, much higher breadth | Before gameplay expansion |
| R5 Undo/Reset release gate | **Target native owner Undo and unanimous Reset in first playable mission**; alternative: explicitly restricted technical demo while these remain blocked | Preserves defining mechanics; may delay milestone | High | Before calling a build playable |
| R6 Voting transaction size and exceptions | **Complete loadout/deployment proposals or small purchase baskets; unanimity for all disposals, lost-reputation departure, final-island commitment and final carryover/overwrite**; alternatives: finer votes, narrower disposal classification | Less noise, prevents hidden permanent losses; more proposal validation | Medium/high | Classification now, menu work later |
| R7 Extra-unit ownership | **Creator controller; unowned mission ally first to one-mech player, then fewer controlled entities with persisted tie-break**; alternative: every mission ally explicitly assigned by mutual choice | Predictable participation; summons still need provenance | Medium/high | Before a mission with controllable allies |
| R8 Loans | **Defer, retain an encounter-override design**; alternative: prioritize voluntary two-sided loans | Lower initial complexity; disabled one-mech player may wait | Medium | Can wait for playtest evidence |
| R9 Persistence/reconnect | **Canonical host save, dedicated profiles, no progression merge or mid-mission recovery initially**; alternatives: checkpoint reconnect or host migration from outset | Smallest honest continuity model; session interruption is costly | High/critical | Identity policy now; recovery before campaign continuation |

R6 does not let unanimity replace ordinary competing choices. Its extra exceptions address explicit forfeiture/retirement/overwrite; ordinary purchases, mission options and valid deployments still follow the user's 50/50 rule. R9 does not promise immunity from local Steam achievement effects; that is a technical isolation test.

## Development priorities after approval

### Must resolve before the next gameplay milestone

- Approve the boundary/default decisions above. Keep the confirmed rules fixed.
- Define session/player/entity/encounter/action/decision identities, monotonic revisions and reset generations; specify persistence/crash states before adapters depend on them.
- Investigate safe independent inspection, preview side effects and the complete command boundary. Resolve/classify observed reload differences and expand state coverage; demonstrate a trustworthy phase completion barrier.
- Choose synchronization only after evidence: two-instance deterministic replay experiments covering different preview histories and enemy/environment phases. If replay fails, investigate whether sufficient authoritative outcome/state restoration is actually possible. Do not assume a hybrid repairs hidden state.
- Design ownership/rotation persistence and vote dedup together even though campaign UI is deferred. No combat RNG for voting.

### Needed before the first genuinely playable co-op mission

- Real supported transport and two game instances; session pairing/config checks, dynamic ownership mapping, serialized same-path requests and duplication/stale rejection.
- Demonstrate the selected connection path between the actual testers, including realistic delay and interruption. LAN-only experiments are useful evidence but do not establish an Internet-ready mod; NAT traversal/relay choice, secure pairing and runtime transport support are unselected. No firewall or Cloud configuration changes are authorized by this review.
- Owned movement, all three standard attacks, Repair, deployment and any mission ally; preserve legal cross-mech effects. Independent inspection/previews, visible ownership, stale feedback and connection status.
- Native Undo and shared Reset per R5; same-state ready/end-turn; enemy/environment phase synchronization and one complete mission outcome.
- Peer-aware stop-on-failure/disconnect, explicit safe exit, validated alternate input/held-release paths and profile/Cloud isolation. No automatic desync Reset or silent single-player continuation.

### Can wait for campaign functionality

- Campaign voting UI and adapters, shared resource/purchase/reward transactions, loadout proposals and island selection.
- Full multi-battle rotation and final-phase lifecycle acceptance, checkpoint continuation and carryover. Their identity models are P0; live campaign integration is later.
- Wider pilot, weapon, summon and mission coverage. Any special case present in the selected first mission moves forward to P1; it cannot simply be ignored.
- Guest progression policy beyond no merging, authenticated checkpoint reconnect and host migration research if desired.

### Can wait for polish

- Coin-flip animation, richer suggested-move overlays, refined panel styling, optional primary swaps/control loans, wider display/controller/mod compatibility.
- Basic clarity cannot wait for polish. Unsupported input/configurations must be visibly rejected before starting.

## Review verification

`npm test` rerun during this review: 11 Lua files parsed as 5.1, 174 Lua contracts under Fengari/Lua 5.3, 11 log assertions passed. Inspected native mocks and CI configuration; no local native executable was run. New acceptance scenarios are specifications only. Historical live records were reviewed, not rerun. Only documentation and project instructions change; no claims of new gameplay functionality follow from this review.
