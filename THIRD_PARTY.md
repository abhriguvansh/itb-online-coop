# Dependency and source notes

No third-party game or mod source is vendored in this repository. API references and reviewed revisions are recorded in `dependencies.json` and `docs/feasibility.md`. `.local/` contains private research copies and must remain ignored.

| Component | Inspected version | License/source record | Repository use |
|---|---|---|---|
| Into the Breach | Windows Steam 1.2.93 / build 13725832 | Proprietary Subset Games product | User-installed runtime only; no redistribution |
| ITB-ModLoader | v2.9.6 | No root license found at inspected tag; distribution includes native/original binaries and separately licensed extensions | Obtained separately, checksum pinned; no bundling |
| ITB-ModUtils / modApiExt | 1.25 / `21bcb56` | Upstream LICENSE contains GPL v2 text | Existing loader extension API only; not copied |
| memedit | 1.2.2 / `24fb9af` | Upstream LICENSE contains GPL v3 text | Optional observer getters; enabled/calibrated for movement diagnostics; not copied |
| IntoTheBreachLua (kartoFlane fork) | `4ecc4a7`; inspected head `dcf22e7` | Upstream LICENSE contains GPL v2 text | Native boundary source audit only; no source/binary vendoring, compilation or installation |
| Fengari | 0.1.5 | MIT, upstream/package license | Development-only Lua 5.3 VM |
| luaparse | 0.3.1 | MIT, upstream/package license | Development-only Lua 5.1 syntax check |
| actions/checkout | [v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) | MIT; exact commit pinned in the workflow | GitHub-hosted CI only |
| actions/setup-node | [v7.1.0](https://github.com/actions/setup-node/releases/tag/v7.1.0) | MIT; exact commit pinned in the workflow | GitHub-hosted CI only |

The npm lockfile records exact resolved transitive packages and integrity values. Package license files stay with local installed dependencies. No code or art was reused from ITB-Hotseat. That project is a local mechs-versus-Vek PvP reference, not evidence of native online co-op.

Original project source has no distribution license selected yet. `UNLICENSED` in package.json records that status and `private: true` prevents accidental npm publication. Review licensing before adding vendored code or packaging upstream dependencies; this inventory is not a claim that the mixed upstream distribution can be relicensed under one license.
