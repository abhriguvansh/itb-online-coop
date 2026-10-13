# Co-op gameplay specification — review draft

Reviewed October 12, 2026 against probe 0.8.0 at `7d59b48`. **Feature development is paused pending design approval.** This document specifies the intended product; it does not claim those features exist. [Implementation audit and decisions](design-review.md); [acceptance scenarios](co-op-acceptance.md).

**C = confirmed by the user. R = recommendation awaiting approval. U = unresolved engineering evidence.** Recommendations never override confirmed rules. Historical experiments retain their original results.

## 1. One squad, two equal participants

**C:** Two people run separate Windows copies of Into the Breach. They share one three-mech squad, one campaign, one set of resources and the normal AI opposition. Native online play, independent local rendering, no streaming substitute. Preserve vanilla rules, progression and difficulty. No extra actions, health, rewards, mechs, spawn scaling or private economies.

**C:** Each player chooses one primary mech for the run. The third mech alternates controller every battle. These are command rights, not private ownership of pilots or equipment. Prime/Brute/Science are examples, not mandatory classes or squad composition.

**R1:** At setup, both approve the primary assignments and shared mech; agree on the first shared-mech controller or use a one-time persisted fair draw if they have no preference. The host has no automatic first-battle entitlement. After that, alternate strictly. Over every complete pair of battles each controls two squad mechs once; an odd-length run inevitably leaves a one-battle difference. Rotation equalizes opportunities, not action count or enjoyment.

**R:** Give each squad chassis a persistent session entity key, mapped to each engine's local pawn identity at every supported load/phase boundary. Never identify it by pilot name, class, display name or current tile. Two mechs may share a type. Pilots can move between mechs without transferring primary command rights. Upgrades, XP, equipment, charges and status stay with their original game entities. Normal game repair/revival between missions remains normal game behavior, never an effect of changing ownership.

**R2:** Keep primary assignments fixed for the initial release. A mutually approved between-battle reassignment can come later, only while no action, vote or deployment is pending. No automatic primary reassignment after a pilot dies or a chassis is disabled.

## 2. What counts as a battle

**C:** Loading, reconnecting, resetting a turn and final-mission subphases must not advance shared-mech rotation.

**R3:** A battle is one committed campaign mission selection and all phases belonging to that encounter. Normal region missions and island HQ encounters each count once when entered. The final island's surface and cave form one battle. Test Mech, previews, deployment retries and loading screens do not count. Count entered encounters, not victories: a completed mission with failed objectives still consumed its ownership assignment. A campaign-ending defeat has no next battle in that run.

Proposed lifecycle:

1. Resolve the campaign choice and persist a prepared encounter record tied to that decision, campaign ID, island/region and mission instance.
2. On the first verified entry into deployment/mission for that record, atomically mark it entered and assign the next battle ordinal and controller. Show the assignment before deployment. A canceled selection before entry consumes no ordinal.
3. Repeated entry callbacks resolve to the same record. After a crash, reconcile the prepared record with the loaded mission; uncertainty stops continuation rather than incrementing again.
4. A linked next-phase callback retains the encounter ID and controller, changing only its phase ID. A final-surface end hook does not close the encounter. Close it only after the terminal phase and campaign outcome are reconciled.
5. A subsequent distinct, entered encounter takes the next ordinal. Persist the ordinal and exact assignment, not merely a toggle in a callback.

**Source basis:** Installed `missions/final/mission_final.lua` names `Mission_Final_Cave` as `NextPhase`. The pinned loader's [`altered/misc.lua`](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/misc.lua#L103) provides previous/next mission objects at phase creation. Its [`Mission:GetSaveData`](https://github.com/itb-community/ITB-ModLoader/blob/1c683d4fc29267044b6928be14d5270ae92ac43c/scripts/mod_loader/altered/missions.lua#L396) relates mission objects to `GAME.Missions` and region records. These are useful mapping inputs, not proven persistent network IDs.

**U:** Verify how those instance/region mappings survive actual campaign reloads. `mission.ID` such as `Mission_Artillery` is a mission type and can repeat. Neither that string, a Lua object address, nor the probe's observation epoch is a battle ID. Persist our encounter key beside verified campaign metadata; reject ambiguous mappings. Reset can restore game data but must not rewind the session's monotonic action/decision history.

## 3. Tactical agency and ordering

**C:** Both participate throughout the player phase. Any legal A → B → A action sequence is allowed. Ordinary move, attack and repair commands require only the issuing player's command rights and the game's legality checks. Friendly pushes, swaps, shielding, repair effects, friendly fire and sacrifices remain legal regardless of the affected unit's controller. Authority is checked on the actor, not on every affected target.

**R:** Serialize mutations, not human turns. Both can inspect and plan at once; exactly one gameplay command executes at a time across both engines. The host is an ordering coordinator and participates through the same request path as the guest. No host-only fast path. Do not hold a human control token for an entire mech or player turn.

Every request carries session ID, connection generation, stable player ID, unique request ID, encounter/phase ID, authoritative revision, actor entity key, command type, equipped weapon identity and all chosen targets. Transport messages contain bounded data, never Lua code or executable effect scripts.

On receipt, deduplicate before execution; confirm sender, connection, phase, revision, actor ownership, current engine allowance, powered weapon/charges and the complete current target selection. Admit one command into an execution barrier. After execution, compare both clients at a demonstrated completion boundary, then publish the new revision and acknowledgement. A receipt acknowledgement alone does not mean the game executed it.

Two otherwise legal requests based on the same revision do not execute simultaneously. **R:** Accept the first valid arrival; return the second as stale after the first resolves. Preserve its draft for a fresh preview and explicit resubmission, without replaying the old intent automatically. This conservatively adds an occasional click, not a restriction on legal action order. Measure host latency advantage; improve ordering only if contention proves material.

**C/R:** Inspect any tile, enemy or ally freely. Only controlled entities can be selected for command submission. Inspecting a teammate's mech, suggesting a target or pinging a tile does not grant its command rights. Previews and selection are client-local, revision-tagged, and not replicated as gameplay actions. Invalidate obsolete previews visibly; revalidate immediately before submission. Two-click weapons submit the complete first/second target tuple as one action after both are legally previewed, never an independently committed first click.

**U:** The present native guard blocks the game's ordinary input before the loader UI. It cannot simply be left on while expecting independent native previews to work. A separate inspected input route/overlay or a verified native command adapter is needed to separate inspection from mutation. Preview calls may build effects or affect RNG/selection; prove that unequal hover histories do not change simulation. Do not loosen the guard based only on cursor coordinates.

## 4. Legality and original abilities

**C:** No fixed co-op rule of one move and one attack may override legitimate game abilities. Current per-process lab lockouts are engineering safeguards, not intended gameplay rules.

**R:** Treat legal native affordances, fresh target areas and authoritative actor state as validation inputs; then check observed consumption and complete outcomes. Neither a reachable tile list nor an engine function's successful return proves legal execution. Never repair allowance flags, revive an actor or retry an uncertain action to manufacture success.

Compatibility must eventually cover post-attack movement, movement through units, flying/teleporting, double actions, repair replacements, post-move effects, weapon charges, multi-stage effects, statuses and forced ally movement. Silica/Double Shot and the `Post_Move`/`Shifty` abilities are direct counterexamples to simplistic quotas; Temporal Reset modifies the team's normal reset allowance. Installed pilot/weapon definitions expose these cases, but their exact interaction with our adapters is not verified. See the [evidence ledger](design-review.md#evidence-ledger).

For the first two-PC mission, **R4:** offer only a clearly named supported configuration: pinned build/loader, Rift Walkers, standard weapons, base content, Normal, pilots without action-altering abilities, and a mission whose whole lifecycle and any allied units are supported. Reject unsupported configurations at setup rather than silently disabling their abilities mid-battle. This is a test scope, not the finished mod's balance. Repair, all three standard attacks, movement, deployment, enemy phase and mission conclusion still need engineering before that milestone.

## 5. Ready, Undo and Reset

**C:** Each player's ready status names the same encounter, phase and authoritative state revision. Every committed gameplay action, including Undo and Reset, clears both confirmations. Inspection, hover, pings and canceled drafts do not. A valid admitted mutation immediately clears readiness so a ready/end-turn race cannot overtake it. A rejected command changes no game state. Disconnect clears readiness and stops admission.

**R:** Ready is a reversible nonmodal button. End Turn itself occupies the serialized command slot: require both connected, both ready for the same revision, no pending action/decision/effect, and a verified player-phase completion boundary. Commit it once, reject late actions, run the entire enemy/environment sequence, compare, then reopen the next player phase. No timer and no implied readiness from a disconnected peer. Being unable to act or having a disabled mech does not remove a player's voice.

**C:** Preserve normal movement Undo wherever feasible; it must never silently reverse the other player's completed actions. **R5:** An owner can request native Undo for their own controlled actor at the current revision. Recheck the actual game's current undo eligibility and execute it as a new serialized command. An earlier revision becoming stale does not permanently prohibit Undo: refresh and query eligibility. If the original engine still permits it after another mech acts, preserve that option, provided native Undo's effects can be replicated correctly. If it no longer permits it, explain the reason and offer the separate shared Reset request if available. Never restore a stored whole-board snapshot to emulate per-mech Undo.

**U:** The live record proves a simple move/Undo pair, not Undo after another actor changes the vacated tile or after a weapon/mission effect. That interleaving must be tested against vanilla behavior; no blanket claim that every later action disables Undo is justified. If safe native Undo cannot be delivered initially, label the prototype limitation and obtain approval rather than making it a permanent co-op rule.

**C:** Either player can request Reset Turn; both must approve the same current revision. Consume only the normal shared allowance, with legitimate pilot modifiers. A desync never spends Reset. **R:** While a reset request is open, show a small pending strip; if another gameplay action commits, invalidate both reset approvals. On acceptance, clear queued intents, previews, readiness and tactical decisions, execute native Reset once on each instance, reconcile results and advance to a new session revision/generation. Do not rewind the deduplication journal or ownership rotation even though the board rewinds. Gameplay reset events and network recovery are different operations.

## 6. Shared campaign choices

**C:** One vote per player; matching votes select that option. Different votes choose between those two submitted options with 50/50 probability, even when many options are available. No host preference, no timer. Yes/no disagreements use the same rule for ordinary decisions. Result and random-tiebreak status are visible and persisted exactly once. The cosmetic reveal reads that result and does not draw again.

**R6:** Separate free local browsing/drafting from a consequential transaction. Put choices in a persistent compact panel, not a dialog for every click. Allow changes to a vote until the second valid vote atomically closes the decision; display locked votes afterward. Use immutable option identities and content versions, not translated labels or list indexes.

| Interaction | Proposed treatment | Reason / boundary |
|---|---|---|
| Hover, inspect stats, browse store, compare weapons, draft positions | Local UI, no vote | No shared state mutation |
| Next island, legal mission, ordinary reward choice | Confirmed ordinary vote | Use currently available choices only; fixed automatic rewards need no vote |
| Buy equipment/core/grid with shared reputation | Ordinary vote on one purchase or a small reviewed basket | Recheck budget and availability as one transaction; no private money |
| Core allocation, reversible upgrades/pilot swaps/loadout changes | Ordinary vote on a complete legal proposal, including keep-current | Draft locally; commit a compatible resulting loadout, not conflicting per-slot fragments |
| Deployment | Ordinary vote between complete legal layouts | Each can draft their units; merge nonconflicting drafts into a proposal. Commit once both choose; account for deployment abilities and phase restrictions |
| Donate/sell/discard equipment; lose an existing pilot permanently | Confirmed unanimity | Removing a pilot to retained storage is a reversible loadout change, not dismissal |
| Abandon campaign, Reset Turn | Confirmed unanimity | Reset remains the game's limited team resource |
| End Turn | Confirmed both-ready | Same-state confirmations; no coin flip |
| Leave island/store with unspent reputation or unresolved valuable rewards | Recommended unanimity | Game text warns that unspent reputation is lost on departure |
| Select timeline survivor / replace a stored time traveler; start new run over an existing save | Recommended unanimity | Final irreversible carryover/loss of progress, not an ordinary reward choice |
| Launch final island and thereby give up remaining campaign opportunities | Recommended unanimity | Agree to this commitment first; ordinary legal choices within the agreed path still use normal voting |

**R:** Conservatively require unanimity for every equipment/pilot disposal, avoiding a brittle definition of “valuable.” An ordinary purchase that entails permanent disposal is not allowed to hide that consequence: approve the destructive part unanimously first, then revalidate the ordinary proposal. A bundled proposal inherits its strictest requirement. Ordinary limited-use attacks and legal friendly fire remain tactical owner actions; do not turn every irreversible combat effect into a vote.

The game has different screens for mission rewards, perfect-island choice, end-island supplies, equipment/pilot arrangements, deployment and timeline selection. Some are partly native UI; scripts/text verify the categories, not a complete programmatic commit API. Each needs its own adapter before support. The early technical host may physically operate a menu only to apply an already resolved equal vote, never choose on the guest's behalf.

### Reliable vote transaction (proposed, not implemented)

Use the same single authoritative command journal as combat, with a separate decision state machine: `open → resolved → applying → applied`, plus `rejected`, `invalidated` or `uncertain`. Each decision has a durable ID derived from a persisted session/campaign decision sequence and a semantic subject (for example this island's reward or this store transaction), a snapshot revision, canonical legal options, two stable-player votes and the result. Keep one consequential campaign transaction open at a time initially.

On receiving the second vote, under the same authority lock: recheck both identities, options and revision; freeze the votes; resolve once; persist the result before showing or applying it. A split maps one unbiased random bit to the two frozen player choices. Use a dedicated, persisted session voting RNG/cryptographic facility, never the game's `math.random`, seed or combat stream. A deterministic derivation from a durably stored independent secret and decision ID is an option to survive a crash before result-write without a second draw; its actual runtime support remains unverified. Do not expose the seed to peers; this cooperative design does not claim protection against a malicious host editing files.

Apply only if the same decision's legal preconditions still hold. Persist the applied outcome plus checkpoint association. If an option became invalid, never silently substitute or reroll it: mark invalidated and explain; a new decision requires a genuinely changed state/options. Reopening the same unchanged subject, repeated button presses, rejected purchases, reconnects and save reloads reuse the existing decision/result. A status-quo result closes that subject for that revision; mutually reopening it cannot become an unbounded coin-flip retry. New materially different proposals can be considered normally.

Persist the decision ID, input revision, option hashes, votes, resolution method/result, ordering index and application outcome for debugging and synchronization. Log no RNG secrets. “Exactly once” is a requirement, not a property of TCP or a SaveGame hook. Game saves and a sidecar journal are not known to commit atomically; crash between engine application and durable recording must stop as uncertain unless a verified checkpoint reconciliation proves what happened. Never retry blindly or promise arbitrary crash-safe continuation.

If a peer leaves before voting finishes, suspend the decision and gameplay. Preserve the pending vote only while its revision/options remain valid; show it for confirmation on supported reconnect. Do not substitute the host's vote, a timeout coin flip or automatic approval. An explicit exit ends the network session rather than leaving one player able to modify the shared run.

## 7. Extra units, destruction and participation

**C:** Command rights must support more than three controllable entities without adding squad mechs. Ownership does not alter legal interactions between allies.

**R7:** A spawned/deployed controllable friendly inherits the controller of the creating actor at the committed creation event. Record provenance and a persistent session entity key; do not infer it from type or pawn-ID order. Mission allies without a creator go first to the player assigned only one squad mech for that battle; assign further such allies to the player with fewer commandable entities, with a persisted alternating tie-break. Freeze those assignments for the encounter instead of moving them automatically on deaths. The rule applies only to units the original game lets humans command; protectable NPCs and scripted units do not become commandable merely because they are friendly.

The current Artillery mission already has a player-team support unit outside the three squad IDs. General support is therefore relevant even before Advanced Edition. Identity matching after spawn, removal, revival and phase transition needs proof. Summoned units do not automatically follow later loans unless that extension is explicitly approved.

**R8:** Defer optional control loans until stable ownership and input routing exist, but design the ownership table to allow an encounter-scoped override. A future loan requires both parties, a safe command boundary, a new ownership revision, cancellation of stale intents/readiness, and no change to engine state or future rotation. Expire it at encounter end. If the one-mech player's unit is disabled now, preserve inspection, pings, suggestions, ready/reset/campaign votes; do not invent revival or automatically take a teammate's mech. Playtesting decides whether postponing loans creates unacceptable disengagement.

## 8. Saves, connection and progression

**R9:** The host machine owns the canonical co-op campaign/save; both humans have equal decision rights. Use a dedicated co-op profile on each machine and a separate session journal/checkpoint bundle. Player IDs are generated stable identifiers bound to authenticated session seats/reconnect credentials, not names, network addresses or host/guest role. No Steam identity or Steam networking API is assumed to be available. Do not include credentials in shareable logs.

Store campaign/session IDs, two primary entities, shared entity, first controller, encounter ledger, phase mapping, rotation ordinal, ownership overrides, latest revision/generation, action deduplication/results and vote records. Associate each supported save with exact build/content/configuration and checkpoint/journal identity. Reject mismatched pairs, stale connections and an older save with a newer journal; never silently generate a new campaign or reroll votes.

**R:** Initial two-PC mission testing is uninterrupted, with stop-on-disconnect and no host migration, mid-mission join or recovery claim. Campaign continuation comes later at verified save boundaries. Reconnect must prove the same authoritative checkpoint and state before admission; it must not restore allowances, rewards or reset usage. An ambiguous crash remains a stopped session, with evidence preserved. Restarting from an older checkpoint is a deliberate loss-of-progress policy needing separate approval, not transparent recovery.

Guests get no promised unlock/achievement merging. Do not patch personal profiles, copy the host's unlocks or award achievements twice. Local Steam achievement side effects also need testing/isolation: a disposable profile alone does not prove platform achievement isolation. Normal one-survivor timeline carryover belongs to the canonical campaign, not one pilot per human. Choose it unanimously as recommended above; linking a future run creates a new campaign ID and new ownership setup.

## 9. Minimum interface and balance

**R:** Use restrained game-style panels outside the board and objective/attack indicators. Distinguish players by both icon/label and color; show primary/shared role and current controller, a short battle-transition notice, two ready indicators, connection/state status, a compact vote panel and brief stale/rejected-action explanations. Keep pings rate-limited and suggestions advisory. No global cursor sharing, forced camera motion, individual scoreboards or cosmetic delays before play can continue. A coin-flip reveal is optional and skippable; the persisted result is authoritative.

**C/R:** Preserve base balance. Two brains do not add tactical resources, though discussion can improve solutions and coordination can add mistakes or waiting. Neither a difficulty increase nor equal enjoyment can be inferred without playtests. Science/support mechs may offer decisive positioning choices despite low damage; damage/kill counts would mismeasure contribution. Use Easy/Normal/Hard/Unfair as the game's own difficulty choices; start validation on Normal with base content. Advanced Edition remains a later compatibility expansion, including its optional content categories, not a co-op balance patch. Turning content off does not revert all Advanced Edition balance changes ([developer update](https://store.steampowered.com/oldnews/?appgroupname=into+the+breach&appids=590380&enddate=1659337200&feed=steam_community_announcements)).

Assess short missions, constrained deployment, moving objectives/environment hazards, summon-heavy squads and highly asymmetric pilots separately. Rotation does not change their legal solutions; input restrictions, stale previews and partner pressure can. Support private inspection and teammate proposals, but leave the final ordinary command with its controller. The [playtest plan](design-review.md#human-playtesting) measures agency and coordination rather than competitive output.
