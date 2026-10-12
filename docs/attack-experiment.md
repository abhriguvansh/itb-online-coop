# Standard attack experiment — October 12, 2026

**Game-verified for one exact standard punch scenario; not a general attack executor.** Probe 0.4.1 submitted one native FireWeapon call, observed normal skill hooks, damage, push and action consumption. Pawn outcomes persisted after Save and Quit and relaunch.

## Scope and result

The pinned Windows Steam baseline was game 1.2.93, loader 2.9.6, modApiExt 1.25 and memedit 1.2.2. The disposable profile was ITB_Coop_Probe, Mission_Artillery, player turn 2. Combat Mech (local ID 0) at (3,3), HP 3, used the powered, unupgraded Prime_Punchmech in slot 1 against Hornet1 (ID 101) at (2,3), HP 3. The empty push destination was (1,3). Unsupported statuses, terrain hazards, skill variants and competing labs are rejected before submission.

The native call ran once. Normal skill-start and skill-end hooks were observed. The Hornet lost two HP and moved to (1,3); its queued target moved from (2,2) to (1,2). Combat Mech remained at (3,3), HP 3, became inactive and had no undo available. Grid power stayed 4. No gameplay flag setter or retry was used.

## Return value correction

Probe 0.4.0 incorrectly required a literal Boolean true from FireWeapon. It faulted even though the attack completed. Probe 0.4.1 records the call result and continues observing after any return or exception, with the one-call lockout set before entering the engine. The installed engine returned a number; the exact number was not logged. Return values are not completion evidence and never authorize a retry. Exceptions retain a fault even if effects subsequently appear.

Completion requires both execution hooks and three matching idle partial observations at least 100 ms apart. A five-second timeout faults the lab. These checks confirm this bounded outcome; they do not establish that all engine work has drained.

## Persistence and evidence

The corrected run contained 14 probe records and an empty game error file. After Save and Quit, Steam reported Cloud up to date. Relaunch produced five records and an empty error file. All captured pawn fields matched, including damage, pushed position, queued target and inactive attacker.

The entire partial state did **not** match: tile (2,3) health changed from 2 to 4 after reload. The cause is unresolved. This prevents claiming full-state persistence or replay equivalence. Four normal-profile files retained their baseline hashes.

Private evidence remains under .local/evidence/attack-0.4.0/ and .local/evidence/attack-0.4.1/, including before-reload, after-reload, persistence.json and reload-diff.json. Raw logs and saves are excluded from Git. Offline attack contracts exercise rejections, one-call lockout, return variants, hook requirements and timeout; they do not substitute for game evidence.

## Remaining work

Legal movement remains the primary execution blocker. General attack targeting, limited-use weapons, status interactions, collision variants, repair, serialized commands, complete input authorization and two-instance replay remain unproven. The next milestone combines a legal movement path with this bounded attack path before transport work begins.

## 0.4.2 overlap correction (offline-tested)

Review found that rearming during a pending call cleared the shared lab reservation, and the UI disable button could discard its observation. Rearming and manual disarming now reject while the attack is pending. Only measured completion, timeout or an explicit lifecycle reset releases it. Two regression contracts cover pending rejection through completion and ordinary pre-submission disarming. This version has not been installed or exercised in the real game; the runtime evidence above belongs to 0.4.1.
