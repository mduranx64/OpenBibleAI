# OpenBibleAI — Agent Instructions

## Start here

This repository contains a SwiftUI Bible reader with an on-device AI study assistant (Apple Intelligence where available, otherwise a downloaded MLX model; no external server). Work in this repository, not the separate ChatGPT Study-project mirror.

At the start of a new session, read in order:

1. [MEMORY.md](MEMORY.md) — dated checkpoint, evidence, limitations, and next task.
2. [ROADMAP.md](ROADMAP.md) — completed milestones and ordered upcoming work.
3. [Development guide](DEVELOPMENT.md) — architecture, build/test commands, data provenance, and operational checks.

Then inspect `git status --short --branch` and recent commits. Reconcile documentation with current source before editing. The checkpoint is historical evidence, not a promise that the checkout is unchanged.

## Working with Miguel

- Default to **implement and explain**: edit and test small, coherent feature slices, then explain what changed, why, and how it was verified.
- This remains a learning project. Explain consequential Swift, concurrency, and design choices without requiring Miguel to copy each edit or answer “red/green” after every test.
- Use meaningful red/green tests for new behavior. Avoid tests that merely repeat implementation details or unrelated refactors.
- Report at meaningful milestones, identifying a sensible commit point. Ask about consequential product ambiguities; resolve routine implementation details from the code and agreed scope.
- Distinguish source inspection, automated tests, user-reported manual checks, and fresh live checks. Never describe mocked engine tests as real inference.

## Architecture and behavior to preserve

- Keep domain values and repository contracts in `BibleDomain`, JSON conversion/loading in `BibleData`, and AI transport/provider behavior in `BibleAI`.
- Keep `BibleRepository` and `BibleCatalogRepository` separate. Cached verse lookup and catalog browsing are intentionally separate injected dependencies.
- Use the existing validated value types. Preserve stable publisher book IDs and canonical ordering; do not sort books alphabetically.
- UI-facing models use `@MainActor` and `@Observable`. Preserve cancellation checks, request-generation guards, and result/selection identity checks.
- Do not assume `async` alone moves blocking work off the main actor. The existing disk loaders explicitly use `@concurrent`.
- Preserve full-chapter reading, verse selection in the reading pane (a chosen verse attaches to the next Bible-chat question as a removable chip; verses opened from the chat do not attach), cross-book Previous/Next in canonical order (stopping only at the first chapter of the first book and the last chapter of the last book; books with no chapters are skipped), and reading-position restoration without overwriting a newer user selection.
- Persist book and chapter using the existing store; verse selection and scroll offset are not currently persisted. Do not change the saved representation without compatibility handling.
- No Bible is bundled: versions are installable packages, assets of the single `bibles` GitHub release pinned by SHA-256 in the catalog (`Tools/BibleImport/catalog.json`, built in and published signed). Packages are rebuilt from recipes in `Tools/BibleImport/versions/`; only `Bibles/kjv` and `Bibles/rv1909` (test fixtures) are versioned. Preserve scripture text exactly as published; never generate, edit or silently substitute it. Publish only public-domain, CC BY / CC BY-SA or licensed versions (RVR1960 and modern Almeida need a license first).
- Never delete or replace a published `<id>-<n>-*` release asset (builds pin them); ship fixes as a new package revision. Never commit or print the catalog signing key outside `catalog_key.sh export-private`; only its public key belongs in `Config/Local.xcconfig`.
- The UI is localized with `OpenBibleAI/Localizable.xcstrings` (en, es, pt-BR). New UI strings need Spanish and Portuguese translations; `LocalizationCatalogTests` enforces this.

## Code discovery

Prefer codebase-memory MCP when available: confirm project/freshness, use `search_graph`, relevant `trace_path`, and `get_code_snippet`, then `check_index_coverage` for evidence paths. Paginate relevant results. Use Tier 2 verification by default.

**Start-of-session graph check (do this before any code exploration, including before delegating to an Explore agent):**

1. `list_projects` → confirm `Users-miguel-Projects-OpenBibleAI` exists.
2. `index_status` → confirm `ready`, and note the generation timestamp and `parse_partial` files. Watched projects auto-refresh; run `index_repository` only if the project is missing or after a large external change (branch switch, bulk generated files).
3. `check_index_coverage` on every file you will cite or edit.
4. Known gap: tree-sitter cannot parse typed-throws signatures (`throws(SomeError)`), so lines containing them are always `parse_partial`. Read those lines directly. Re-indexing does not fix this.
5. Record in `MEMORY.md` only what was actually checked; do not copy "stale index" claims forward without re-checking.

An earlier inspection found an index older than recent features. Missing graph symbols are not proof of missing code. For stale, partial, skipped, or unknown coverage, read the current source and reported missed ranges. Use direct file/config/literal inspection when appropriate; if MCP is unavailable, use targeted `rg` and source reads and disclose that fallback.

## Validation and Git

- Follow the commands and regression checklist in [DEVELOPMENT.md](DEVELOPMENT.md). Run the affected package/app tests, then broaden only when the change warrants it.
- Use mocked providers for repeatable tests. Perform live model checks (Apple model, MLX) and manual UI checks separately and state any untested paths.
- Run `git diff --check` and inspect the changed/staged file list before declaring a milestone ready.
- Preserve unrelated user edits and the chosen checkout/branch. Do not commit, push, rewrite history, or create another chat unless requested.
- Do not commit local signing identities, Xcode user state, build artifacts, or downloaded source archives. `Tools/BibleImport/Source/` is ignored; import scripts and generated Bible JSON are versioned.

## Maintaining context

At completed milestones, update this repository's `MEMORY.md` and the relevant roadmap status with dated evidence and limitations. Keep stable architecture and operational commands in the development guide rather than copying them everywhere.

`MEMORY.md` here is ordinary project documentation. It is separate from global Codex memory; this file does not authorize changing global memory or unrelated project instructions.
