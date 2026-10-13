# Co-op edge cases and acceptance plan

October 12, 2026. **Proposed tests, not implemented tests or passing evidence.** The current probe's passing contracts do not satisfy these scenarios. Rules and approval IDs are in [co-op-design.md](co-op-design.md) and [design-review.md](design-review.md).

Modes: **A** = automated pure/session/transport-fault test with explicit doubles; **G** = actual game test on the pinned build, comparing with normal game controls; **2P** = two separate game processes on two PCs with their own copies; **H** = two humans assessing experience. Automated packet/crash tests can support but never replace G/2P outcome evidence.

Use disposable profiles, verified backups, pinned versions/configuration and separately retained logs. Record session/campaign/encounter/phase IDs, generation/revision, entity mappings, request/decision IDs and relevant pre/post conditions. Keep raw saves/logs and credentials private. No local native test executable while the Norton alert remains unresolved; existing native mocks run in CI.

## Ownership and campaign identity

| ID | Setup and stimulus | Required result | Modes |
|---|---|---|---|
| O01 Consecutive battles | Choose arbitrary primary X for A, Y for B, shared Z; A starts shared. Enter three distinct mission instances | A: X+Z, then X, then X+Z; B always Y plus opposite Z. No chassis, pilot, equipment, HP or allowance changes from assignment | A, G, 2P |
| O02 Repeated mission type | Enter two different regions both using the same mission class string | Different encounter IDs and exactly one rotation between them; class name is not identity | A, G, 2P |
| O03 Reload/reconnect | Save an entered battle; repeat entry/load callbacks; reconnect both seats in both orders | Same primaries, shared controller and ordinal. No new entity creation, rewards or allowance. Supported checkpoints only; unsupported reconnect is rejected visibly | A, G, 2P |
| O04 Final phases | Enter final surface, transition to cave, save/load in each supported phase | One encounter and unchanged owners across both phases; phase IDs differ. Surface end does not rotate/complete encounter. No assumption that normal engine reset allowance spans phases | A, G, 2P |
| O05 Canceled/prepared entry | Cancel before mission entry; separately crash after prepared selection, during first entry and after recorded entry | No canceled ordinal consumption; reconcile entered mission once. Ambiguous checkpoint stops rather than increments | A, G, 2P |
| O06 Reset/death/pilot swap | Reset turn, disable a primary mech, swap pilots between battles | Rotation/primary chassis identities unchanged. Native death/repair/pilot mechanics retained; no automatic control transfer | A, G, 2P |
| O07 Same-type entities | Use duplicate mech types in later supported squad; rename them and move pilots | Entity mapping remains unambiguous; names/types/local spawn order cannot steal ownership | A, G, 2P |

## Tactical command correctness

| ID | Setup and stimulus | Required result | Modes |
|---|---|---|---|
| T01 Interleave | At one player turn: A moves X, B attacks with Y, A attacks with X or shared Z | All legal actions execute in that sequence without a whole-player-turn token; ordinary attacks need no vote | A, G, 2P |
| T02 Simultaneous intents | Both submit different legal actions against revision r, with varied arrival delays | One admitted first. Other is stale/busy with preserved draft and fresh preview, not executed on old assumptions. Explicit valid resubmission succeeds | A, 2P |
| T03 Duplicate packet | Repeat same request before acknowledgement, during execution and after completion; reuse ID with altered body | Exactly one engine submission/outcome. Identical duplicate returns recorded status; altered payload is rejected. No extra action or charge | A, G, 2P |
| T04 Stale move | Preview destination; partner pushes actor, occupies route or changes terrain; submit old preview | Rejected before mutation with clear feedback. Re-preview can still submit any currently legal move | A, G, 2P |
| T05 Stale weapon | Preview target; partner kills/moves it, changes shield/HP, or changes a chained effect | Reject old revision, not retarget automatically. New legal target/effect preview can submit | A, G, 2P |
| T06 Unauthorized actor | Peer requests other primary, enemy, uncommandable friendly, wrong session or old connection generation | No engine call. Merely inspecting these entities remains allowed | A, G, 2P |
| T07 Allowance/phase | Submit spent movement, inactive attack, unpowered/out-of-charge weapon, illegal target, deployment/player/enemy phase mismatch | Same legal restrictions as normal game; no native call/flag repair or automatic retry. Ordinary later-turn actions allowed after native refresh | A, G, 2P |
| T08 Real exceptions | Use Double Shot stationary versus moved, Post_Move/Shifty after attack, action-restoring effects and movement/path modifiers | Accept exactly what native controls permit. No process-lifetime quota, fake reactivation or ability suppression. Unsupported configurations rejected before a test session begins | A, G, 2P |
| T09 Repair/limited effects | Normal repair and a repair-altering pilot; limited weapon at final charge; later reset/reload | Native allowance/status effects and charges consumed/restored only under native rules. Network retry grants nothing | A, G, 2P |
| T10 Multi-target attack | Preview first and second targets, cancel, then repeat while partner changes state | Canceled drafts mutate nothing; complete legal target tuple admitted as one command. Stale second stage rejected before firing | A, G, 2P |
| T11 Team combinations | Push/pull/swap/shield another player's mech; legal friendly fire/sacrifice; compare same sequence solo | Ownership validates issuer only. Same positions/damage/status/objective consequences as native play, no extra consent dialog | A, G, 2P |
| T12 Preview independence | Same seed/checkpoint and commands on two PCs, deliberately different hover/inspection/preview/cancel histories | Same gameplay outcomes and RNG-sensitive future outcomes at verified boundaries. A match of current visible tiles alone is insufficient | G, 2P |
| T13 Completion boundary | Execute delayed multi-stage effects, enemy chain/spawn/environment events with idle gaps | No next mutation admitted during a transient idle/candidate. Compare only after proven relevant work completes | A, G, 2P |
| T14 Failure window | Drop link/focus/heartbeat before submission, during press, after engine accepts but before acknowledgement | Both sessions stop admission, held input drains, no implicit local continuation or retried uncertain action. Known completed effects stay recorded; no rollback claim | A, G, 2P |
| T15 Input routes | Under healthy/stopped session try mouse, keyboard selection/repair/Undo/Reset/End Turn, held release tails and any supported controller | Every mutation requires authorization; inspection is usable. Unsupported controller modes rejected before start. No effect on other applications | A, G, 2P |
| T16 Network conditions | Introduce 50/150/500 ms delay, jitter, disconnects and duplicate/reordered application messages; test actual Internet connection when claiming online support | Stable ordering/deduplication, visible pending state, no optimistic game mutation or timed default vote. Bounded queues/payloads; wrong-seat/session requests rejected. LAN success alone is labeled LAN evidence | A, 2P |

## Undo, readiness and Reset

| ID | Setup and stimulus | Required result | Modes |
|---|---|---|---|
| U01 Simple native Undo | Owner moves, requests Undo at current revision | Native origin/allowance restored, one serialized action, readiness cleared. Nonowner cannot request it | A, G, 2P |
| U02 Cross-player Undo | A moves; B moves/attacks elsewhere; A asks Undo. Repeat with B affecting the vacated tile, pushing A, causing terrain/mission effects | First determine each solo-native result. Co-op preserves available native Undo without reversing B's committed action. If native disallows, reject and explain. Never restore a whole-board pre-A snapshot | G, 2P |
| U03 Matching readiness | A ready at r; B ready at r while board idle and both synced | End Turn exactly once; both confirmations clear. A double-click/duplicate ready packet cannot start two enemy phases | A, G, 2P |
| U04 Action invalidates | A ready at r; B commits action; B readies at r+1; inject A's delayed ready(r) | A is not ready for r+1; no end turn until fresh A approval. Inspection/pings/canceled previews do not clear readiness | A, 2P |
| U05 Ready/action race | Final ready and new action arrive together; also unready/disconnect at barrier | Authority orders events once: admitted action invalidates readiness, or already committed End Turn rejects late action. No silent auto-ready on disconnect | A, 2P |
| U06 Shared Reset | A requests, B declines; then both approve new valid request with normal allowance | Decline does nothing. Agreement invokes one normal reset per engine, not one reset per human; no extra allowance from reconnect | A, G, 2P |
| U07 Reset modifiers | Repeat with Temporal Reset and supported Reset_Bonus behavior; test unavailable reset and final phases | Match native controls and outcomes, including actual allowance/modifier behavior. Do not infer allowance from “one per co-op battle” | A, G, 2P |
| U08 Reset stale state | First approval at r, partner commits action, delayed second approval arrives; later perform valid Reset | Stale approval cannot reset new board. Successful reset cancels intents/previews/readiness/tactical votes and advances session generation; old packets remain rejected although game turn number rewinds | A, G, 2P |

## Voting, budgets and durable outcomes

| ID | Setup and stimulus | Required result | Modes |
|---|---|---|---|
| V01 Match | Both select option X from legal options X/Y/Z | X resolves once with no random draw and no tie animation; both display same result | A, 2P, H |
| V02 Split/3+ choices | A selects X, B selects Z where Y is also offered | Only X or Z may win, with one equally weighted selection; Y is impossible | A, 2P |
| V03 Fair mapping | Inject random bit 0 then 1 for ordered frozen votes; swap player slots/options. Separately exercise production dedicated RNG over many independent decision IDs | Both bit branches map symmetrically to submitted choices, no modulo/time/host bias. Statistical test over e.g. 10,000 independent IDs uses a predeclared tolerance/test; a distribution check alone is not proof and must not “repair” unlucky streaks. Deterministic unit tests are not flaky random CI gates | A |
| V04 Combat RNG isolation | Identical game checkpoint/commands with and without numerous vote resolutions and UI coin reveals | Vote-only operations do not consume/seed game RNG; subsequent native outcomes match the controlled baseline | A, G, 2P |
| V05 Duplicate/reopen | Deliver repeated votes/results; close/reopen menu; resubmit unchanged rejected purchase; reconnect/reload | Same semantic decision ID/result, one draw/application. A split no-buy result cannot be rerolled by reopening unchanged context | A, G, 2P |
| V06 Crash boundaries | Crash before second vote, before durable resolution, after resolution, during application, after game save but before journal completion | Resume known durable result without reroll only where checkpoint association proves safe. Otherwise mark uncertain and stop; never duplicate purchase/reward or silently retry application | A, G, 2P |
| V07 Stale options | Option disappears, reward replaced, budget changes or old inventory index reused before closure/application | Reject/invalidate stale decision, preserve history and explain. No silent selection substitution; new decision only for changed context/options | A, G, 2P |
| V08 Unanimous exception | A approves sale/pilot loss/abandon/Reset, B rejects; repeat both approve | Disagreement has no effect and consumes no random draw. Agreed action applied once after live validation | A, G, 2P |
| V09 Competing purchases | Each proposes a different item/basket, individually affordable but not jointly affordable | Resolve one transaction first; charge only winning legal proposal once. Recompute remaining budget/options before next purchase, never negative balance or duplicated inventory | A, G, 2P |
| V10 Composite proposal | Loadout/deployment contains conflicting tiles, unavailable weapon, unpowered requirement or hidden disposal | Invalid proposal never becomes a legal option. Destructive component requires unanimity; no partial ordinary-vote purchase/loadout application | A, G, 2P |
| V11 Missing voter | Peer disconnects before voting; old vote packet arrives from replaced connection | Suspend without timeout/substitute vote. Reconnect identity/options checked; obsolete connection rejected. Both players see pending status | A, 2P, H |
| V12 Result display | Matching vote, split vote, RNG streak, replayed resolved decision and skipped animation | Display the one persisted winner and whether tie occurred. Animation never draws again or delays required input. No compensating streak weighting | A, 2P, H |

## Entities, saves and experience

| ID | Setup and stimulus | Required result | Modes |
|---|---|---|---|
| S01 Extra units | Create two same-type deployables from different players; spawn a mission ally and a noncommandable friendly | Creator-derived owners mapped consistently on both PCs; mission ally uses approved assignment rule; no three-entity cap or command rights for protected NPC solely due to team flag | A, G, 2P |
| S02 Removal/revival | Destroy, remove/off-board, revive or phase-transition a supported entity | Original native state/identity preserved where appropriate; recycled local IDs cannot inherit stale commands. No unauthorized extra resource refresh | A, G, 2P |
| S03 Loan if approved | One-mech player's actor disabled; request a loan while action pending, then at safe boundary; one party refuses/then both agree | Pending/refused transfer does nothing. Accepted override changes command rights only, cancels stale intents, expires at encounter end and leaves next rotation intact | A, G, 2P, H; deferred |
| S04 Checkpoint pairing | Mix older game save/new journal, wrong campaign, wrong builds/mods, wrong player credentials; load valid pair | Reject mismatches before mutations. Valid pair restores exact owners/revision/decisions. No guest progression merge or identity inferred from display name | A, G, 2P |
| S05 Reward replay | Complete mission/reward, duplicate acknowledgement, reconnect and reload supported checkpoint | One canonical reward outcome; inventory/XP/reputation/reset state equal native baseline, no rewards per human | A, G, 2P |
| S06 Profile/Cloud isolation | Run supported two-PC flow with backups and recorded normal-profile hashes; exercise save/exit/Cloud sync | Co-op writes stay in intended profiles/checkpoints; normal data preserved. Inspect platform achievement side effects separately; do not claim profile isolation proves Steam isolation | G, 2P |
| S07 Carryover | Finish/lose canonical run; choose one survivor unanimously; begin linked run | Preserve native survivor rules, not two survivors; new campaign identity/setup. Refused destructive overwrite leaves old checkpoint intact | A, G, 2P |
| H01 Agency | Consecutive battles, swapped roles, mixed/equal experience; include disabled primary and support role | Both report meaningful decisions and clear control/votes. Collect separate ratings and examples; kills/damage are not fairness metrics | H |
| H02 Tactical parity | Players attempt known solo combinations, cross-mech undo, ally sacrifice, rapid A → B → A and split deployment plans | No unexplained forbidden tactic; classify unsupported cases visibly. Measure stale-action friction and waiting rather than changing game balance | G, 2P, H |

## Exit criteria by milestone

- **Design approved:** approval IDs resolved or explicitly deferred; all confirmed rules represented in the session design. No production implementation inferred from this document.
- **First two-PC mission:** relevant O/T/U/S cases for the supported configuration pass, including real enemy/environment phase and mission outcome. V campaign-menu tests may wait, but action dedup, identity, input permissions and checkpoint association cannot be replaced by mocks.
- **Campaign-capable:** consecutive real missions, final-phase identity, campaign voting transactions, resources, loadout/deployment decisions, supported save/continuation and carryover pass on two PCs.
- **Wider compatibility:** repeat with supported special pilots/abilities, summons, multi-target/limited weapons, new missions/difficulties and layouts. Keep excluded cases explicitly listed; adding a configuration is a tested capability expansion, not a label change.

Every result must distinguish implementation-contract success, single-game behavior, two-instance synchronization and human experience. Matching partial digests is useful diagnostic evidence, never proof of complete hidden state or safe recovery.
