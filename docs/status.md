# Status — October 12, 2026

**Latest working increment: Milestone 0 preparation and an offline-tested observation probe. No in-game milestone is complete.**

## Implemented

- Local Git repository and publishable source layout.
- Probe 0.1.0 with version logs, execution/build distinction, mission-phase observations, partial state capture, unavailable-field reporting and candidate stability observations.
- Bounded JSON log reader, deterministic observed-state digests and explicit-boundary field differences.
- Verified backup/staging tool and scoped probe install/uninstall with ownership and hash checks.
- Pinned dependency/source records, feasibility table, test plan and a GitHub Actions workflow.

## Actually checked

- Steam build 13725832 and executable version string 1.2.93. An existing old log said 1.2.88; it was not used as the installed-version authority.
- No visible existing loader or mod directory in the inspected installation; game was not running during backup.
- Loader v2.9.6 ZIP hash matches GitHub release metadata. Its bundled original Lua/SDL DLLs match the installed originals.
- Ten save files and four affected game files backed up and hash-verified outside the live save directory. Private manifest: `.local/backups/baseline-20261012-151451/manifest.json` on the originating machine.
- Five mod files pass Lua 5.1 syntax parsing. Eighteen Lua contract tests and eleven log-analysis assertions pass. Contract execution uses Fengari/Lua 5.3 and engine doubles.
- Installer tested in an inert temporary directory: plan writes nothing, payload stays scoped, duplicate install/edited/unowned files are rejected, uninstall preserves other mods and the loader.
- Actual-game installer was run in **Plan** mode only. Live installation and saves remain unchanged.

## Blocked or unverified

The staged loader has not been installed or launched. Its native libraries require the installation decision requested by the handoff. Native game UI control is unavailable in this session. A human must select the disposable profile and perform the first tactical test; no screenshot or runtime log exists for this project yet.

Legal programmatic actions, complete input gating, exact settled boundaries, AI/RNG reproduction, full-state restoration, transport and two-instance synchronization are unproven. Steam Cloud state and a second PC/tester have not been established; neither is needed for the first single-instance observer test.

GitHub publication is pending an approved destination/visibility and authenticated write access. No remote was created or pushed. Source licensing is undecided; upstream/game code is not included. The workflow is configured, not GitHub-tested.

## Single next action

Approve the prepared loader-and-probe installation, then perform the first single-instance smoke test in `docs/test-plan.md` using `ITB_Coop_Probe`. The concrete change is replacement of three existing loader-entry files plus loader additions and this probe; the resource archive is backed up because the loader rewrites it at startup. This decision was intentionally deferred until the file plan, backups, code and offline tests were ready.
