# OpenBibleAI Roadmap

Status date: **2026-09-30**, committed implementation baseline `2623655`. Exact-reference search (parser/resolver, lookup-state, and UI/navigation wiring) is fully committed as of `1f60e8f`. Detailed evidence is in [MEMORY.md](MEMORY.md). Unchecked items below are planned capabilities.

## Completed

- [x] Validated book, reference, and verse values; repository contracts and test fixtures.
- [x] In-memory verse lookup, passage loading, caching, and JSON repositories.
- [x] Streamed study responses, cancellation and error handling (originally via local Ollama).
- [x] Installable Bible versions (2026-10-02, uncommitted): no bundled Bible; onboarding downloads pinned version packages (text + embedding index) from GitHub releases; switch versions, compare 2–4 in aligned columns, manage/delete; the chat answers from the reading version. UI localized in Spanish and Brazilian Portuguese (String Catalog). Public-domain KJV and RV1909 built and pinned, ready to publish; RVR1960 and modern Almeida await licenses; Almeida 1911 awaits a verified source.
- [x] Bible chat (2026-10-02, uncommitted): one ChatGPT-like panel replaces "Ask the Bible" and "This Verse": follow-ups use recent turns and the verses the previous answer cited, a selected verse attaches as a removable chip, chats are saved on device with a list (open/delete) and New Chat. AI Settings lists every downloaded model (Qwen3 1.7B/0.6B, search model) with Delete, whichever engine is active.
- [x] Ask the Bible (2026-10-01, uncommitted): free questions in any language answered from retrieved KJV passages (keywords + optional semantic search, bundled verse vectors), citations checked and linked to the reader.
- [x] On-device AI without external servers (2026-10-01, uncommitted): Apple's FoundationModels first, else a downloaded MLX Qwen3 model (1.7B; 0.6B on 4 GB devices), pinned revisions with SHA-256 verification; Ollama removed.
- [x] Canonically ordered books, chapter discovery, and ordered chapter verses.
- [x] Complete bundled KJV: 66 books, 31,102 verses, with separate book metadata.
- [x] Book → chapter → verse navigation with loading, empty, failure, and retry UI.
- [x] Full-chapter reading, selectable verses, and scrolling to sidebar selection.
- [x] Previous/Next within the selected book, including incomplete-dataset boundaries.
- [x] Navigation refresh (2026-10-01, uncommitted): drill-down sidebar (testament-grouped, filterable books → chapter grid), verse list removed from the sidebar, cross-book Previous/Next, ⌘[ / ⌘] and ⌥↑ / ⌥↓ shortcuts, "Book Chapter" breadcrumb.
- [x] Persist and restore book/chapter without overriding newer user navigation.

Completed means implemented with the dated test/manual evidence recorded in MEMORY; it does not mean release-certified on every declared platform.

## 1. Exact-reference search — complete

Goal: enter `John 3:16`, open the matching chapter, and select the requested verse for reading and AI study.

Slices:

- [x] Define and test the reference parser/resolver against a supplied catalog and existing `BibleReference` validation. `BibleReferenceParser.parse(_:books:)` returns a reference; it does not verify stored verse availability.
- [x] Add observable lookup state and resolve an actual stored verse, with cancellation/latest-request behavior appropriate to the interaction. `BibleReferenceSearchModel` uses separate catalog/verse repositories and publishes only matching stored verses.
- [x] Add the search entry and connect successful lookup to existing book/chapter/verse selection and reading-position persistence. Wired in `1f60e8f` via `BibleReaderNavigationModel` and the search UI, with `BibleReaderNavigationModelTests` and `ReferenceSearchUITests` covering it.

Acceptance criteria:

- Full English book names and explicit chapter/verse input work, including a numbered book such as `1 John 2:1`.
- Invalid input, unknown books, and unavailable chapter/verse references produce useful feedback without destroying the current reading position.
- Success loads the correct chapter, highlights/scrolls to the verse, enables its AI study panel, and saves the selected book/chapter.
- A superseded lookup or restoration cannot overwrite a newer user choice.
- Parser, repository failure, and navigation integration behavior are tested; the existing manual reading checklist still passes.

Initial supported syntax is a full catalog book name followed by `chapter:verse`, including `1 John 2:1` and `Song of Solomon 1:2`. Name matching ignores case and collapses whitespace, including tabs/newlines. Whitespace around the colon and leading zeros are accepted. Chapter/verse tokens use ASCII digits, must fit `Int`, and must be positive. Abbreviations (including publisher IDs), ranges, chapter-only queries, fuzzy matching, and multiple references are unsupported. Names must match uniquely; the parser reports unknown/ambiguous names separately from invalid syntax and domain position errors. Avoid building a full-text index for exact lookup.

## 2. Text search — implemented, uncommitted (2026-09-30)

Goal: find words or phrases in bundled KJV verses and open a result in the reader.

Rules as built: case/diacritic-insensitive whole-word matching; all words must appear in any order; a `"quoted phrase"` needs consecutive words; punctuation ignored; canonical Bible order, no relevance ranking; at least 2 letters; first 100 matches with total count and a truncation notice. Linear scan, no index (unmeasured; see item 3). No highlighting of matched words in excerpts.

Acceptance criteria:

- Define and document matching rules, ordering, and result limits before implementation.
- Results include a reference and scripture excerpt; empty queries, no matches, loading, and failure states are clear.
- Choosing a result uses the same navigation path as exact-reference lookup.
- Rapid query changes cannot display results for an older query; background work supports cancellation where applicable.
- Tests cover real query/result behavior without a live model dependency.

## 3. Measured search performance — implemented, uncommitted (2026-10-01)

Result: baseline recorded; targets (p95 ≤ 100 ms, no main-actor stall > 16 ms) were missed (≈ 278 ms, ≈ 283 ms stall) and now pass (≈ 87 ms, ≈ 2 ms) with `@concurrent` and an ASCII tokenizer fast path. No index was needed. Details and commands: [DEVELOPMENT.md](DEVELOPMENT.md#search-performance-text-search).

Goal: keep search and navigation responsive with the complete dataset.

Acceptance criteria:

- Record a baseline on the full KJV, including device/toolchain, query cases, latency, and memory observations.
- Add indexing, caching, or background execution only for an observed bottleneck.
- If an index is added, define rebuilding/versioning and demonstrate result equivalence to the source dataset.
- Cancellation and interaction remain responsive; record measured before/after results rather than inferred improvements.

## 4. AI study improvements — implemented, uncommitted (2026-10-01)

As built: the selected verse's whole chapter, bounded to 6,000 characters of verse text (trimmed to a contiguous window around the selected verse when longer; the selected verse is always included), is sent as background context. Prompts use the full book name. The panel shows a verse card (full-name reference + text) and labels the response "Generated explanation — not Scripture". Answers are tied to the verse they were generated for and cleared on selection change. Mocked failure/timeout behavior is unchanged; a separate gated live smoke test exercises a real installed model. Not done: no automated check that generated claims or citations are accurate.

Goal: improve grounding and usability while preserving local model selection and streaming.

Acceptance criteria:

- Add chapter context through an explicit request-model change, with bounded context and tests for the constructed request.
- Display clear verse references and distinguish generated explanations from canonical text.
- Changing selection or stopping a request does not show stale generated content for another verse.
- Verify mocked failure/timeout behavior separately from a real installed-model smoke test.
- Do not represent generated citations or theological interpretations as verified scripture without checking them.

## 4a. App icon — selected and installed (2026-10-01)

Three 1024 px visual concepts, their hand-held variants, three Bible + AI treatments of the hand-held First Light concept, and twelve holographic Sculpted Book treatments are in `Design/AppIconConcepts/`, with small-size/mask comparison pages. Miguel selected `03-sculpted-book-original-pose-elegant-style.png`, which applies the elegant held-icon style to the original sculpted Bible and cupped-hand composition. That image now fills the iOS/iPadOS and macOS `AppIcon` slots. A matching two-layer `AppIconVision` image stack is selected for visionOS. The macOS app build and direct iOS/visionOS asset compilation passed; full iOS and visionOS app builds remain blocked by existing platform source errors documented in `MEMORY.md`. Editable vector artwork, appearance variants, and live platform review remain future polish.

## 4b. Bible versions — 29 versions, one release, signed catalog (2026-10-03, published)

Every openly licensed complete Bible on eBible.org in English (22, with the KJV), Spanish (5, with the RV1909) and Portuguese (2) is converted and indexed; drafts, Catholic-canon, incomplete and copyrighted texts are listed with reasons in DEVELOPMENT. Packages are published as assets of one `bibles` release (`<id>-<n>-<file>`, compressed where it helps; int8 verse index), about 8.8 MB per version instead of 22.5 MB. A signed remote catalog (Ed25519, key in the Keychain and the `release` GitHub environment, public key from `Local.xcconfig` through generated `BuildSettings`) lets new versions appear without an app update. Packages are no longer committed except the `kjv`/`rv1909` fixtures.

- [x] Signing key generated (Keychain), `BIBLE_CATALOG_PUBLIC_KEY` set locally, `CATALOG_SIGNING_KEY` secret in the `release` environment (Miguel as reviewer, `main` only). Miguel still needs to back the private key up.
- [x] `bibles` release with 116 verified assets and the signed catalog (sequence 1, Publish catalog run 37129793167); live install of KJV, BSB and Bíblia Livre; `bible-kjv-1` and `bible-rv1909-1` deleted.
- [ ] Live-check a remote catalog update in the app (publish sequence 2 with a new version).
- [ ] "Update available" for an installed version whose catalog entry moved to a new package revision.
- [ ] Deuterocanon support (Douay-Rheims, WEB Catholic); revisit draft texts (spablm, spabll, porbrbsl) when finalized.
- [ ] Request licenses: RVR1960 (American Bible Society for Sociedades Bíblicas Unidas) and a modern Almeida (Sociedade Bíblica do Brasil); add them through `add_version.sh` once granted.
- [ ] Live-check the chat in Spanish/Portuguese versions; recognize English book names in citations while reading another language.
- [ ] Keep the selected verse across version switches; check onboarding and comparison on iPhone/iPad.
- [ ] Later: Apple-Hosted Background Assets as the App Store host; catalog key rotation.

## 5. Release preparation

Goal: make the supported release configuration reproducible and usable.

Acceptance criteria:

- Restore a tracked, tested book-catalog generation path and preserve source/provenance documentation alongside reproducible resource checks.
- Expand CI to the appropriate package and app tests; verify the actual runner configuration.
- Validate keyboard navigation, VoiceOver, text readability, window sizes, and loading/error states.
- Select and test the intended release platforms; macOS results do not substitute for iOS/visionOS runs.
- Review translation distribution requirements (each Bible version's license and the KJV's UK letters-patent qualification) for release territories, signing, packaging, and installation behavior.
- Document remaining limitations and release/manual test evidence.

## Milestone discipline

Implement and explain one coherent slice at a time. Run relevant automated tests and meaningful manual checks, update the checkpoint, and identify the commit boundary. Do not combine data replacement, UI redesign, and search implementation into an unreviewable change. Commits and pushes remain user-directed.
