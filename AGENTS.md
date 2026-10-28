# AGENTS.md

## AGENTS.md Loading Budget

- Keep this root file limited to repository-wide invariants and precise routing gates; place detailed workflows in versioned documentation or skills.
- Codex applies a combined instruction budget (32 KiB by default) across global, root, and nested guidance. Keep mandatory gates first and preserve headroom for narrower scopes.
- Do not raise `project_doc_max_bytes` as the first response to oversized guidance; remove duplication and route conditional detail first.

## Working on an issue (Mandatory)

Several people (and their Claude sessions) work on this repository. To never
do the same work twice:

1. **Claim before starting.** Look at the issue first: if someone else is
   assigned, do not start; ask them. Otherwise assign yourself
   (`gh issue edit N --add-assignee @me`); the "in progress" label follows
   automatically.
2. **One branch per issue**, from `web-client-792`: `issue-N-short-name`.
   Push it and open a **draft pull request** early, with "Closes #N" in the
   description, so work in progress is visible.
3. **Merge through the pull request** into `web-client-792`; no direct
   pushes. The "Issue claim" check fails when the pull request names no
   issue or the issue is not assigned to its author.
4. **Done:** merge, then the issue closes with a short summary. Giving up:
   unassign yourself and say what is left in a comment.
5. Small fixes without an issue: open one first.

## Client Assets Gate (Mandatory)

Any change touching client-assets auto-installation must preserve the runtime contract below:

1. **Final install paths must remain OTC-standard**
   - `data/things/<version>/`
   - `data/sounds/<version>/`
   - runtime extras in expected runtime locations (for example `bin/*` when distributed upstream)

2. **No alternate permanent source of truth**
   - Do not move runtime loading to `client-assets/` (or any new root) as the primary runtime path.
   - Temporary/cache directories are allowed only as transient staging, never as final runtime source.

3. **Security defaults stay strict unless explicitly justified**
   - `strictManifestSha256 = true`
   - `allowRawFallbackHashMismatch = false`

4. **Cross-platform build safety**
   - Android must not require unsupported `libarchive` linkage.
   - Desktop archive extraction behavior must remain functional.

5. **Verification required in PR description**
   - Explicitly state tested install paths and expected runtime load behavior.

Reference: `docs/client-assets-auto-install.md`

## UI Design Gate

New or changed windows and touch screens use the ot-ui styles
(`data/styles/50-ot-ui.otui`): build from `Ot*` styles and `&ot-` tokens, no
one-off colours, fonts or images. Reference: `docs/design-language.md`
