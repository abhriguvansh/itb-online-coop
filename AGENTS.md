# Engineering instructions

## Current product milestone

Build the first playable two-human alpha: two people on separate Windows PCs independently complete one supported mission from deployment through victory and matching observed results, over a secure private connection. One operator using two VMs is engineering evidence only.

- Inspect current implementation and evidence before choosing one highest-impact blocker. Verify the existing full interactive gameplay path before investing in startup tooling. Fix missing gameplay first; otherwise simplify host/guest startup using existing infrastructure.
- Preserve working architecture. Prefer a complete, useful interaction over new frameworks, repeated equivalent replay proofs, unrelated refactoring, or additional test harness sophistication.
- Developer automation may test the game, but players must select their own actions and independently inspect, approve End Turn, and use supported Undo/Repair/Reset. Scripted tactical intent cannot establish alpha playability.
- Restrict the first alpha to the pinned Windows game/loader, stock Rift Walkers and a verified mission configuration. Explicitly reject unsupported encounters/interactions safely. Time pods and uncommon content may be deferred only when the supported scenario excludes them without rerolling randomness, skipping rewards, or changing vanilla rules.
- Keep AGENTS.md durable and concise. Store detailed results/failures in docs/command-session.md and current readiness in docs/status.md. Historical AGENTS entries remain in Git at 62fd304.

## Gameplay authority

The approved rules in docs/co-op-design.md and docs/co-op-acceptance.md remain authoritative; their historical engineering milestone does not override the current alpha priority.

- Each player chooses one persistent primary mech. The third alternates by entered encounter, with no extra rotation on reload, reconnect, Reset or linked final phases. Additional controllable allies follow the approved ownership rules. First-battle assignment is implemented; campaign rotation is not.
- Preserve legal interleaving, independent vanilla-visible inspection and renewed intent after stale rejection. Inspection grants no command rights and must not reveal hidden future information.
- Ordinary campaign disagreements have equal final votes and one persisted fair choice, without host privilege or duplicate rerolls. Reset/destructive exceptions require unanimity; End Turn requires both players' same-state readiness. Campaign machinery remains deferred.
- Never add health, actions, resources, rewards, enemy scaling or balance changes to make an experiment pass.

## Required safeguards

- Preserve ownership, legality, fresh two-runtime preparation, phase/result boundaries, input protection, bounded deadlines, duplicate/stale/conflict refusal and stop-on-uncertainty. Never retry an action that may have committed or rewrite outcomes to repair disagreement.
- Idle boards or unchanged snapshots do not prove enemy/environment/spawn/planning completion. Retain ordered engine events, restored allowances and later observations. Compare partial state only at equivalent boundaries; never claim full-state synchronization or general determinism from it.
- Use pinned upstream source and observed engine behavior, not plausible API names. Initial-choice and shared-XP hooks remain exact-build, bounded, restored native integrations; no seed, board, save-field or allowance normalization.
- Protect normal saves. Use ITB_Coop_Probe with a nonempty profile key; display names and folder keys differ. Back up and hash affected saves outside live directories before tests, preserve raw failure evidence, and restore only verified disposable checkpoints.
- Update only the owned mods/aman_itb_coop_probe payload while games are closed. Validate ownership manifests and file hashes; never overwrite unknown content or recursively delete a game, mods or save tree.
- No local native test executable may be built or run after the unresolved Norton alert. DLL compilation is allowed; native executable contracts run only in GitHub CI. Do not bypass security software or add exclusions.
- Never expose the unencrypted coordinator publicly. Remote alpha play requires a secure private network. Installation/account setup, firewall, security and Steam Cloud changes require explicit approval. No paid infrastructure. Six-digit rooms remain the eventual joining goal, with $0 additional recurring private-play costs.

## Environment and publication

- Keep synced sources/ read-only. This repository is the development checkout; game assets, binaries, saves, logs, tokens, credentials, VM files and .local/ remain private and untracked. No source license has been selected; do not vendor upstream code.
- Public source publication to abhriguvansh/itb-online-coop is approved. Use scoped commits and the existing no-reply Git identity; do not change global Git settings. Check CI for the exact pushed revision before claiming it passed.
- Existing ITB-Coop-A/B VMs and guest graphics installations are approved. Keep their recovery snapshots. Both displays must remain visibly rendering during paired tests; prior frame stalls are not proven cured. Preserve existing guest isolation, security and CPU/memory settings unless a specific change is authorized.
- Follow current Computer Use instructions for UI actions and observe before each action. Announce foreground testing. Obtain coordination when controls are not known idle; request manual help only for genuinely unavailable interaction or permission.

## Verification and reporting

Run focused checks appropriate to the change: npm test, tests/install.ps1, tests/bridge-mailbox.ps1, npm run check:tracked and git diff --check as applicable. Prefer actual game evidence; label source inspection, doubles, real sockets, real game instances and two-human play separately.

End runs with Current milestone, Completed, Actual evidence, Readiness, Next step, User involvement and Scope discipline. Recommend a model/reasoning setting only when supplying next-step instructions intended for another conversation, per the project-wide preference. Do not conduct another broad architecture or game-design review.
