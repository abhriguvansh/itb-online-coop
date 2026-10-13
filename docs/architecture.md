# Architecture decisions

**October 12 design review:** feature expansion is paused pending user approval of [the review](design-review.md). [The gameplay specification](co-op-design.md) is authoritative for confirmed requirements; recommendations and acceptance scenarios remain unimplemented. The observer ADRs below describe the original research sequence, not the full current 0.8.0 capability. In particular, an original native input bridge is now installed and tested within [these limits](window-guard.md).

## Selected now

**ADR 001: ship an observer before an action executor or transport.** Source inspection found permissive Move and FireWeapon APIs; calling them directly would not preserve normal rules. Observation is the smallest experiment that can reveal execution order and accessible state without introducing gameplay mutations.

`mod/scripts/init.lua` supplies loader metadata and lifecycle. `probe.lua` subscribes once, distinguishes effect-building counts from execution events, resets observation epochs across contexts, and restricts tactical capture to the named test profile. `snapshot.lua` copies only scalar data immediately; no Board/Pawn userdata is retained for a later callback. `json.lua` and `settle.lua` are pure helpers. `tools/probe-report.cjs` parses local diagnostic JSON, summarizes boundaries, and compares explicitly selected observations.

The mod calls the existing loader extension API; it does not copy or vendor it. memedit is optional for observation and required for the manually armed movement diagnostic. The development Node dependencies are never installed in the game.

**ADR 002: stability is a measurement, not a lock.** Three unchanged idle observations are labeled `settled_candidate`, with `proofOfQuiescence=false`. The first real-game test produced candidates between portions of enemy activity, before later effects. They do not authorize actions or assert full synchronization. Input remains normal single-player input outside the explicitly armed temporary gate. A future executor needs a stronger boundary that accounts for phase and pending work.

**ADR 003: separate local evidence from publishable source.** `.local/` stores downloaded upstream sources/binaries, backups, inert test fixtures, and logs. Git contains this project's source, tests, dependency pins and documentation. Publication must use reviewed tracked files only. `package.json` is private; source licensing is undecided.

**ADR 004: measure an engine action before accepting it as legal execution.** `movement.lua` validates a bounded request immediately before one native call, retains scalar data, and checks destination, allowance, activity and health afterwards. `movement_ui.lua` supplies a local opt-in trigger on the disposable profile. Neither is a multiplayer input gate. The experiment is restricted to three exact Rift Walker pawn identities in `Mission_Artillery`, one adjacent plain-ground destination, and a clear road/forest origin. Unsupported statuses, tiles, abilities, missing reads, stale requests and concurrent lab actions fail closed.

The real 0.2.0 test returned true and changed position but left movement unused. The lab timed out into a fault that survives context resets until process restart. No allowance setter, forced position, automatic retry or rollback was used to manufacture a successful result. [Evidence and next investigation](movement-experiment.md) record the difference from normal UI movement. This diagnostic remains a known failing path, not an executor to connect to transport.

**ADR 005: trace bookkeeping without changing it.** `move_trace.lua` copies state at build/start/end, deduplicates unchanged preview states, and briefly watches for later changes. It does not edit effects, call actions, or use setters. Native userdata never survives a callback. The 0.2.1 normal-move trace found undo available by effect start and movement consumed by effect end. The start hook therefore cannot be treated as a pre-mutation rejection boundary. [Evidence and limits](move-trace.md).

## Proposed after the probe

**ADR 006: investigate existing input interception before replacing native libraries (historical investigation).** The [native boundary audit](native-boundary.md) finds event suppression in the installed loader's source lineage, but no exposed complete command-submission operation. Probe 0.3.0 tested that path with a timed diagnostic gate: the selected mouse move was blocked, then succeeded after timeout. [Evidence](input-gate.md). Hook ordering, exception fall-through, release handling, and polled-state bypasses must be measured before treating it as authorization. Later work selected an original local Windows input bridge; 0.8.0 adds local protected sessions. Neither provides complete multiplayer input authorization. DLL exports and movement flag setters do not establish a legal command API.

The 0.2.2 direct skill-effect experiment also failed allowance/undo equivalence, although its position persisted across a controlled reload. The historical `effect` and `native` paths remain regression cases; the current selected movement path is the bounded UI bridge. Do not connect the failed primitives to transport. [Evidence](effect-experiment.md).

Proposed: one authoritative host orders both players' validated requests through the same path. Two actual game instances render locally. Keep game integration, command validation/session rules, transport, state comparison, and UI/diagnostics separate. Both humans can freely interleave legal actions; serialize individual commands, not entire human turns. A temporary engine experiment must not be represented as satisfying the full co-op interaction requirement.

Confirmed: each human chooses one persistent primary mech; the third alternates controller each battle. Classes are not hardcoded. Reconnecting, reloading, Reset and linked final phases must preserve assignments. The initial shared controller and precise encounter-entry transaction are recommendations awaiting approval in the specification. Persist stable entity/encounter identity rather than counting hooks or relying on mission-type strings. Rift Walkers remain a proposed initial compatibility scope, not a permanent squad restriction.

Confirmed: ordinary campaign choices use equal votes and a single persisted 50/50 selection between different votes. Technical host menu operation does not grant superior decision rights. Destructive choices and Reset require unanimity; End Turn requires both ready on the same state, invalidated by gameplay actions. Preserve native movement Undo wherever feasible. Unsupported Undo/Reset must be blocked in a restricted prototype, with that limitation explicit; they are not intended permanent exclusions. The Vek remain AI-controlled.

The review proposes one serialized session journal for combat and campaign decisions, separate from engine RNG. The identity/deduplication/checkpoint schema must precede adapters even though campaign UI is later. Atomic engine-save/journal commitment is unproven; stop uncertain recovery rather than retrying mutations or rerolling votes. No implementation of these session systems exists.

No transport has been selected. First establish a supported communication path from the embedded Lua runtime; do not assume LuaSocket, unrestricted DLL loading, or an ABI. A small local helper and reliable ordered LAN transport are candidates. Messages must be bounded structured data with version/session/action identifiers, sequence numbers and revisions. Never execute received code. A receipt acknowledgement is not proof of in-game execution.

## Open synchronization decision

Ordered command replay needs demonstrated equivalence of RNG, AI planning, spawn order, previews and mission effects. Host outcome replication needs safe restoration of sufficient hidden engine state. Neither has been established; a hybrid is only justified by evidence. Compare only equivalent settled boundaries. On divergence, preserve both logs and stop mutations; automatic repair is deferred.

Streaming, local PvP, a recreated browser game, and a mock second client do not satisfy the native co-op objective. No infrastructure for matchmaking, public servers, accounts, web dashboards, databases or campaign persistence is being built in this increment.
