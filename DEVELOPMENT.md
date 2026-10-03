# Development Guide

Commands below run from the repository root. See [MEMORY.md](MEMORY.md) for the dated results; the [Architecture](#architecture) section describes the design.

## Environment and project layout

Verified on 2026-09-30: Xcode 27.0, Apple Swift 6.4, native macOS 27.0 on Apple Silicon. The package manifests require Swift tools 6.4. Python 3 is used only for development-time Bible conversion; the app has no Python runtime dependency.

Check the selected command-line toolchain:

```bash
xcodebuild -version
swift --version
```

Open `OpenBibleAI.xcworkspace` for the app and all three local packages. The project also opens directly through `OpenBibleAI.xcodeproj`. Its definition is `OpenBibleAI.xcodeproj/project.xcproj`; do not assume the older `project.pbxproj` filename or rewrite its format.

The app target declares iOS 17, macOS 14 and visionOS 1 deployment targets (test targets 27.0), for iPhone, iPad, Mac and Vision (`TARGETED_DEVICE_FAMILY` 1,2,7). iOS code uses only iOS 17 APIs.

### Layout per platform

- **Mac (and visionOS):** a three-column `NavigationSplitView`: sidebar (reference/text search, books → chapter grid drill-down), reader, chat. Settings is the macOS Settings scene (a gear sheet on visionOS).
- **iPhone, and iPad in compact width (narrow Split View/Slide Over):** a `TabView` with Read, Chat, Search and Library (`AppShell/BibleReaderView+Phone.swift`). Read is a `NavigationStack` (books → chapters → reader) with the version and Compare menus in the bar and an icon-only chapter bar. Selecting a verse shows an "Ask about …" button that opens the Chat tab; citations, sources and search results open the reader in the Read tab. Search is one `.searchable` field: input with a colon is a reference, otherwise a text search. Library switches the reading version, toggles compared versions, and links to Manage Bibles and AI Settings.
- **iPad at regular width:** a two-column split (sidebar stack with search, books → chapters; the reader) with the chat in an `.inspector`, open by default and toggled from the toolbar, which also has Compare, the version menu and AI Settings (`AppShell/BibleReaderView+Pad.swift`).
- `AppNavigation` (`AppShell/AppNavigation.swift`) holds the tab, the Read stack (`readPath`; the iPad sidebar uses it without the reader) and the inspector; `ContentView` owns it so it survives version switches and size-class changes. Selection stays in `BibleReaderNavigationModel`. The shared pieces (`BookListView`, `ChapterGridView`, `ChapterReaderContent`, `ChapterNavigationBar`, `TextSearchResultRows`) are in `BibleReader/BibleReaderComponents.swift`.
- Compact width also changes Compare (versions stacked under each verse instead of columns), Manage Bibles (Delete by swipe or long press, without the confirmation the Mac shows) and onboarding (heading scrolls with the list, Start Reading pinned).

The selected app icon is in `OpenBibleAI/Assets.xcassets/AppIcon.appiconset/` for iPhone, iPad, and Mac. visionOS selects the two-layer `OpenBibleAI/Assets.xcassets/AppIconVision.solidimagestack/` through SDK-specific `ASSETCATALOG_COMPILER_APPICON_NAME` settings. The source concept and an installed-icon size preview are in `Design/AppIconConcepts/`. Asset catalog compilation can verify both icon configurations independently of full app builds; see the dated results in `MEMORY.md`.

List available schemes:

```bash
xcodebuild -list -workspace OpenBibleAI.xcworkspace
```

Verified scheme names include `OpenBibleAI`, `AllUnitTests`, `OpenBibleAITests`, and `OpenBibleAIUITests`. The shared `AllUnitTests.xctestplan` lists app unit tests plus BibleDomain, BibleData, and BibleAI tests.

## Architecture

Stable design and contracts. Dated status and evidence live in [MEMORY.md](MEMORY.md).

### Dependency map

```text
OpenBibleAIApp — composition root
  BibleLibraryModel.live() (pinned catalog, one LocalModelStore per version under Application Support/OpenBibleAI/Bibles/<id>)
    install / cancel / delete, active version (bible.activeVersion), bible(id) → LoadedBible (cached)
      BibleVersionPackage.load(from:) → version.json, books.json, JSONBibleRepository (language-aware BM25), embeddings.bin URL
  AppModel(library:) → .needsVersion (BibleOnboardingView) or .ready(Session) for the active version
    Session: BibleCatalogModel, BibleReferenceSearchModel, BibleTextSearchModel (that version's repositories)
             + one app-lifetime BibleChatModel (answers from the reading version)
    switchVersion(to:) → activate + new Session; the reader is rebuilt (.id(version)) and restores book/chapter
  BibleCompareModel(library:) → BibleCompareView columns (bible.compareVersions)
  ReadingPositionStore(any ReadingPositionStorage = UserDefaults.standard) → BibleReaderNavigationModel
  BibleReaderView → BibleReaderNavigationModel → search and selection; toolbar: BibleVersionMenu, BibleCompareMenu
  AIEngineModel.live() (Apple status, MLX tiers, LocalModelStore) → AISettingsView, BibleChatView
  SemanticSearchModel.live() (optional embedding model; useIndex(session.embeddingsURL)) → chat retrieval
  BibleChatModel.Engine (prompt streamer, budget, optional semantic search) + FileChatStore → BibleChatModel

SwiftUI app → BibleDomain, BibleData, BibleAI
BibleData → BibleDomain
BibleAI → BibleDomain
```

`AppModel.Repositories` groups `verses: any BibleRepository`, `catalog: any BibleCatalogRepository`, `text: any BibleTextSearchRepository` and `passages: any BiblePassageSearchRepository` for one installed version. Startup refreshes the library: with no installed version the state is `.needsVersion` (onboarding); otherwise the active version is loaded and `.ready(Session)` carries its models. Failures and cancellation have explicit startup states. The caching actor conforms only to the verse-lookup protocol; keep the contracts separate rather than passing one combined dependency. No Bible is bundled with the app.

### Source map

| Responsibility | Entry point |
|---|---|
| Dependency creation | [OpenBibleAIApp.swift](OpenBibleAI/OpenBibleAIApp.swift) |
| Startup state, version sessions | [AppModel.swift](OpenBibleAI/AppModel.swift) |
| Installable versions, onboarding, version menu, compare | [BibleLibraryModel.swift](OpenBibleAI/Features/BibleLibrary/BibleLibraryModel.swift), [BibleCatalogEntry+Published.swift](OpenBibleAI/Features/BibleLibrary/BibleCatalogEntry+Published.swift), [BibleOnboardingView.swift](OpenBibleAI/Features/BibleLibrary/BibleOnboardingView.swift), [BibleVersionMenu.swift](OpenBibleAI/Features/BibleLibrary/BibleVersionMenu.swift), [BibleCompareModel.swift](OpenBibleAI/Features/BibleLibrary/BibleCompareModel.swift), [BibleCompareView.swift](OpenBibleAI/Features/BibleLibrary/BibleCompareView.swift) |
| Version metadata, package loading, language rules | [BibleVersion.swift](Modules/BibleDomain/Sources/BibleDomain/BibleVersion.swift), [BibleVersionPackage.swift](Modules/BibleData/Sources/BibleData/BibleVersionPackage.swift), [TextAnalyzer.swift](Modules/BibleDomain/Sources/BibleDomain/TextAnalyzer.swift) |
| UI strings (en, es, pt-BR) | [Localizable.xcstrings](OpenBibleAI/Localizable.xcstrings) |
| Root view, settings sheet, background unload | [ContentView.swift](OpenBibleAI/ContentView.swift) |
| Book/chapter/verse-list state | [BibleCatalogModel.swift](OpenBibleAI/Features/BibleCatalog/BibleCatalogModel.swift) |
| Reader/search UI, chapter controls, verse → chat attachment | [BibleReaderView.swift](OpenBibleAI/Features/BibleReader/BibleReaderView.swift) |
| Selection, search task ownership, persistence, restoration | [BibleReaderNavigationModel.swift](OpenBibleAI/Features/BibleReader/BibleReaderNavigationModel.swift) |
| Chapter text, highlight, scrolling | [BibleChapterReadingView.swift](OpenBibleAI/Features/BibleReader/BibleChapterReadingView.swift) |
| Exact-reference parsing and lookup | [BibleReferenceParser.swift](Modules/BibleDomain/Sources/BibleDomain/BibleReferenceParser.swift), [BibleReferenceSearchModel.swift](OpenBibleAI/Features/BibleSearch/BibleReferenceSearchModel.swift) |
| Text search | [BibleTextSearchModel.swift](OpenBibleAI/Features/BibleSearch/BibleTextSearchModel.swift), [BibleTextQuery.swift](Modules/BibleDomain/Sources/BibleDomain/BibleTextQuery.swift) |
| Passage ranking, citations, verse vectors | [RankedVerseIndex.swift](Modules/BibleDomain/Sources/BibleDomain/RankedVerseIndex.swift), [CitationParser.swift](Modules/BibleDomain/Sources/BibleDomain/CitationParser.swift), [VerseVectorIndex.swift](Modules/BibleDomain/Sources/BibleDomain/VerseVectorIndex.swift) |
| Persisted reading position | [ReadingPosition.swift](OpenBibleAI/ReadingPosition.swift), [ReadingPositionStore.swift](OpenBibleAI/ReadingPositionStore.swift), [ReadingPositionStorage.swift](OpenBibleAI/ReadingPositionStorage.swift) |
| Bible chat (pipeline, history, summary, attached verse) | [BibleChatModel.swift](OpenBibleAI/Features/Chat/BibleChatModel.swift), [BibleChatView.swift](OpenBibleAI/Features/Chat/BibleChatView.swift), [BibleQuestionPrompt.swift](Modules/BibleAI/Sources/BibleAI/BibleQuestionPrompt.swift) |
| Saved chats | [ChatConversation.swift](OpenBibleAI/Features/Chat/ChatConversation.swift), [ChatStore.swift](OpenBibleAI/Features/Chat/ChatStore.swift) |
| Semantic search | [SemanticSearchModel.swift](OpenBibleAI/Features/Chat/SemanticSearchModel.swift), [SemanticVerseSearch.swift](Modules/BibleAI/Sources/BibleAI/SemanticVerseSearch.swift), [MLXTextEmbedder.swift](Modules/BibleAI/Sources/BibleAI/MLXTextEmbedder.swift) |
| Engine choice, downloads, deleting models | [AIEngineModel.swift](OpenBibleAI/Features/StudyAssistant/AIEngineModel.swift), [AISettingsView.swift](OpenBibleAI/Features/StudyAssistant/AISettingsView.swift), [AIEngineChoice.swift](Modules/BibleAI/Sources/BibleAI/AIEngineChoice.swift), [LocalModelStore.swift](Modules/BibleAI/Sources/BibleAI/LocalModelStore.swift), [ModelManifest.swift](Modules/BibleAI/Sources/BibleAI/ModelManifest.swift) |
| Engines | [AppleFoundationModelProvider.swift](Modules/BibleAI/Sources/BibleAI/AppleFoundationModelProvider.swift), [MLXModelProvider.swift](Modules/BibleAI/Sources/BibleAI/MLXModelProvider.swift), [AIPromptStreaming.swift](Modules/BibleAI/Sources/BibleAI/AIPromptStreaming.swift) |
| JSON decoding and file loading | [BibleData sources](Modules/BibleData/Sources/BibleData) |
| UI-test launch helper, local Bible server | [UITestLaunch.swift](OpenBibleAIUITests/UITestLaunch.swift), [UITestBibleServer.swift](OpenBibleAIUITests/UITestBibleServer.swift), [UITestBibles.swift](OpenBibleAI/Features/BibleLibrary/UITestBibles.swift) |

### Contracts and state ownership

- `BibleRepository.verse(at:)` supports exact lookup; missing stored verses throw a lookup error.
- `BibleCatalogRepository` exposes `books()`, `chapters(in:)` and `verses(in:chapter:)`: books in canonical order, unique ascending chapters, verses in reading order; absent collections are empty arrays.
- `InMemoryBibleRepository` stores verses by `BibleReference`; its initializer overwrites duplicates, while `JSONBibleRepository` rejects duplicates before constructing it. Do not generalize the JSON guarantee to arbitrary in-memory callers.
- `JSONBibleBookCatalog` maps snake-case DTO fields into validated `BibleBook` values and rejects duplicate book IDs. It does not enforce a complete 66-book dataset or unique canonical-order numbers.
- `CachingBibleRepository` caches successful verse results and shares in-flight lookups. A caller's cancellation is not evidence that a shared base request was cancelled.
- `BibleCatalogModel` has separate book, chapter-list and verse-list state, each carrying the requested identity. `BibleReaderView` retains one `BibleReaderNavigationModel` in SwiftUI State; it owns the selected book/chapter/reference, the search task and restoration. The catalog model owns only loading/browsing state.

### Navigation and persistence flow

1. The reader loads books, then attempts restoration.
2. Selecting a book clears chapter and verse selection; a task keyed by book ID loads chapters.
3. Selecting a chapter (chapter grid or Previous/Next) clears verse selection and saves book/chapter; a task keyed by book and chapter loads verses. Previous/Next cross books in canonical order through `BibleCatalogModel.chapterNumbers(in:)` and apply only if the navigation generation is unchanged. The sidebar is a drill-down (testament-grouped, filterable books → chapter grid); verses are selected in the reading pane, and `selectAdjacentVerse` backs ⌥↑ / ⌥↓.
4. `BibleChapterReadingView` shows the full chapter. Selection revisions request a scroll; manual scrolling does not change the selection.
5. `activeReference` is the selected verse only when it belongs to the loaded chapter. Every selection revision with an active reference attaches that verse to the chat (`BibleChatModel.attach`), except the revision produced by opening a verse from the chat.
6. Restoration checks the saved value, repository availability, cancellation, current selection and navigation generation after suspension. It does not select a verse or immediately resave.
7. Reference search resolves a stored verse first, then updates book/chapter/verse together and saves only book/chapter. New searches, query edits, ordinary selection, Cancel and reader disappearance cancel pending search; failures keep the current selection. Text-search results and chat links use `BibleReaderNavigationModel.open(_:)`, the same apply step.

The reading position is JSON `Data` under `bible.readingPosition` (`bookID`, `chapter`). `ReadingPositionStore` depends on the two-method `ReadingPositionStorage` protocol, which `UserDefaults` satisfies; tests inject an in-memory fake. `load()` returns nil for no data and throws for decoding/domain errors; errors are logged and never block reading, and invalid saved data is not deleted. Keep the generation and no-overwrite checks: a search attempt counts as user intent even if it fails, so a delayed restore must not navigate afterward.

### Concurrency and AI

- UI models are `@MainActor @Observable` classes; domain values are immutable and Sendable. Blocking work (JSON loading, text search, BM25) uses `@concurrent`; `async` alone does not leave the main actor.
- Chapter, verse-list, search and chat requests use generation counters so a late result never overwrites newer state; views also check result identity. Cancellation alone is not enough when a dependency doesn't stop immediately.
- Engines: `AppleFoundationModelProvider` (snapshot → delta via `StreamDeltaAccumulator`, errors mapped to `AIEngineError` for OS 26 and 27) and `MLXModelProvider` (shared lazily loaded `MLXModelEngine`, thinking off + `ThinkBlockFilter`). `AIEngineChoice.choose` is the pure selection rule; `AIEngineModel` holds status, downloads, the per-engine context budget, lists installed models of every tier and deletes them, and unloads MLX in the background. Keep pinned manifests and SHA-256 verification when changing models.
- `BibleChatModel` pipeline, per question on the reading version (`BibleChatModel.Bible`, with a `BibleQuestionPrompt.SearchProfile` for its name, language and citation style): keywords (any language → words of the version's language; sees the previous turn, earlier questions, summary and attached verse) → BM25 `rankedVerses`, fused by `RankFusion` with semantic search (when installed) and the previous answer's grounded citations → `passages(around:)` within the budget → `BibleQuestionPrompt.answer` (summary, recent turns, attached verse, passages) streamed via `AIPromptStreaming` → `CitationParser` + repository checks (grounded / outsideSources / notFound). The budget is shared: ≤ ⅓ history (summary included), ≤ ⅓ attached-verse chapter, the rest passages. Turns that drop out are summarized in the background after an answer.
- The chat owns its answer task: a new question or Stop invalidates the previous one; a stopped answer keeps its text. Conversations are `Codable` values saved by `FileChatStore` (one JSON file each, schema version 1, optional fields for additions); each answer records its `versionID` (missing = KJV), and citations are stored as text and re-checked against that version when a chat is opened (unlinked if it isn't installed).

Avoid adding a database, cloud AI or another translation without a decision with Miguel (and its license); preserve the exact-reference syntax, scripture text exactly as published, and saved-position compatibility.

## Signing and local configuration

Signing identities belong in an untracked local configuration. For your own device/signing setup:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set your own `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX` there. `Config/Shared.xcconfig` includes it optionally. Do not commit the local file or copy its values into documentation.

`BIBLE_CATALOG_PUBLIC_KEY` (and optionally `BIBLE_RELEASE_REPOSITORY`/`BIBLE_RELEASE_TAG`) also go there; see "Adding or updating a Bible version". The app reads them through `OpenBibleAI/Generated/BuildSettings.swift` (gitignored), which the app target's first build phase, *Generate build settings* (`Tools/generate_build_settings.sh`), rewrites from the build settings when they change (it records the xcconfig files in a dependency file so editing `Local.xcconfig` reruns it). Xcode lists the files to compile before that phase runs, so **on a fresh clone run `Tools/generate_build_settings.sh` once before the first build** (otherwise the first build fails with `cannot find 'BuildSettings'` and the next one succeeds). Scripts that build the app, such as `Tools/BibleImport/add_version.sh`, run it first.

The macOS unit-test baseline used ad-hoc signing overrides, shown below. Those overrides are for local testing, not device distribution or release signing.

## Automated validation

Run an affected package directly:

```bash
swift test --package-path Modules/BibleDomain
swift test --package-path Modules/BibleData
swift test --package-path Modules/BibleAI
```

The 2026-09-30 checkpoint refresh (against `2623655`) passed 33, 12, and 14 reported tests respectively. Isolated build locations can be selected with SwiftPM's `--scratch-path`; do not commit build products.

For app unit tests, the verified command was:

```bash
xcodebuild test \
  -workspace OpenBibleAI.xcworkspace \
  -scheme AllUnitTests \
  -destination 'platform=macOS' \
  -only-testing:OpenBibleAITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

The inspection also supplied a separate `-derivedDataPath` and `-quiet`; neither changes the intended test selection. In the 2026-09-30 refresh it reported 56 tests passed, zero failures, and zero skips. After the text-search milestone the same command reports 70 tests (BibleDomain 47, BibleData 13). Xcode emitted nonfatal destination/host-selection warnings. Removing `-only-testing:OpenBibleAITests` selects the complete test plan; in the recorded baseline the three package suites were run separately instead.

UI tests drive the real app and need a desktop where the app can open and capture a window: no other app in full-screen, and the window's saved display connected. They read and write the app's real `bible.readingPosition`, so back it up first if you care about your place. A verified command (add `BUNDLE_ID_PREFIX=dev.openbibleai.search-tests` to use a separate sandbox container and leave your real defaults alone):

```bash
xcodebuild test \
  -workspace OpenBibleAI.xcworkspace \
  -scheme OpenBibleAIUITests \
  -destination 'platform=macOS' \
  -only-testing:OpenBibleAIUITests/ReferenceSearchUITests \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

iPhone and iPad UI tests (`PhoneNavigationUITests`, `PadNavigationUITests`; each skips on the other idiom) run on simulators and attach screenshots to the result bundle (`xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`). Book and verse rows are lazy, so tests filter books and use verses near the top. If `xcodebuild` hangs after the tests finish, add `-collect-test-diagnostics never`:

```bash
xcodebuild test \
  -workspace OpenBibleAI.xcworkspace \
  -scheme OpenBibleAIUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -only-testing:OpenBibleAIUITests/PhoneNavigationUITests \
  -collect-test-diagnostics never
```

UI tests get their Bibles from `UITestBibleServer`: a 127.0.0.1 server in the (sandboxed, `ENABLE_INCOMING_NETWORK_CONNECTIONS`) test runner that serves `Bibles/kjv` plus `test-es`, test data made at run time from the KJV with Spanish book names. `launchForUITest(bibles:)` passes the server URL and pinned catalog in the launch environment; Debug builds then install through the real download path (`UITestBibles`, under `Application Support/OpenBibleAI/UITestBibles`). `.installed([...])` (default the KJV) pre-installs before the app starts, `.fresh` starts at onboarding. No internet is needed.

In Xcode, use `AllUnitTests` with My Mac for Command+U and `OpenBibleAI` for Command+R. UI tests are a separate target; do not count the app unit-test result as UI automation evidence.

Before delivery:

```bash
git diff --check
git status --short
```

Current CI in `.github/workflows/tests.yml` runs only BibleDomain on pushes to `main`, using a runner label `xcode-27`. Local results do not establish the remote runner's availability or a successful CI run. Expanding coverage is a roadmap item.

## On-device AI (Apple Intelligence and MLX)

The study assistant needs no server. `AIEngineModel` picks the engine on each refresh:

1. **Apple's on-device model** (`FoundationModels`, iOS/macOS/visionOS 26+) when `SystemLanguageModel.default.availability` is `.available`.
2. Otherwise a **downloaded MLX model** on Apple silicon (not the simulator), chosen by physical memory: ≥ ~5.5 GB → `mlx-community/Qwen3-1.7B-4bit` (≈985 MB), ≥ ~3.5 GB → `mlx-community/Qwen3-0.6B-4bit` (≈350 MB, smaller context/answer bounds). The user starts the download from the study panel or AI Settings.
3. Otherwise the panel explains why AI is unavailable (Apple Intelligence off, preparing, too little memory, unsupported device).

Models are pinned to a Hugging Face revision with per-file SHA-256 (`ModelManifest`), stored under the app container's `Application Support/OpenBibleAI/Models/<tier>/` (excluded from backup), and only used after every file verifies. Qwen3 runs with `enable_thinking: false`, and `ThinkBlockFilter` removes any leading `<think>` block. Dependencies: `mlx-swift-lm` pinned to 3.32.3 (`MLXLLM`, `MLXLMCommon`) and `swift-transformers` (`Tokenizers`); the tokenizer loader is hand-written (`TransformersTokenizerLoader`), so no Swift macro approval is needed.

`swift test` cannot build MLX's Metal shaders; MLX only runs from Xcode/`xcodebuild` builds. Package tests use fakes.

### Live checks (separate from mocked tests)

```sh
# Apple's model (needs Apple Intelligence on; runs in the BibleAI package)
OPENBIBLE_LIVE_APPLE=1 swift test --package-path Modules/BibleAI --filter LiveAppleModel

# MLX: downloads the pinned model into the app container, then answers John 3:16
TEST_RUNNER_OPENBIBLE_LIVE_MLX=standard xcodebuild test -workspace OpenBibleAI.xcworkspace -scheme AllUnitTests \
  -destination 'platform=macOS' -only-testing:OpenBibleAITests/LiveMLXModelTests \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
# use =compact for the 4 GB-device model
```

2026-10-01 on an M3 Max (macOS 27): Apple model 21 streamed deltas in 2.6 s for John 3:16; MLX 0.6B download+verify 19 s, load 1.0 s, answer 3.6 s; MLX 1.7B download+verify 65 s, load 1.0 s, answer 0.8 s; no `<think>` output. The 0.6B answer was noticeably less precise. Memory use was not measured. iPhone/iPad memory behaviour, visionOS hardware and Intel Macs are untested.

## Bible chat (retrieval and verse index)

The Bible chat (formerly "Ask the Bible") answers free questions from passages of the reading version: model-suggested keywords in the version's language (any question language; Apple's keyword step uses the content-transformation guardrails) → BM25 (`RankedVerseIndex`, `TextAnalyzer` for English, Spanish or Portuguese) fused by reciprocal rank with optional semantic search (`SemanticVerseSearch`: Qwen3-Embedding 0.6B 4-bit on device + the version's `embeddings.bin`, downloaded with it) → passages (±2 verses) within the engine budget → answer citing `[Book C:V]` → citations checked (`CitationParser`, also unbracketed "Luke 2:4") as grounded / outside sources / not found. Citations match the version's book names with or without accents and also accept every English, Spanish and Portuguese name (`BibleBookNames`, checked against `Tools/BibleImport/books/`), since models often cite "John 3:16" or "Mateus 2:1" while reading the RV1909.

Each package's index (≈31,100 × 256 Float16, ~16 MB) must match its `verses.json` (SHA-256 in its header; `BundledVerseIndexTests` checks `Bibles/kjv`) and the pinned embedding model. Rebuild after changing either; `TEST_RUNNER_OPENBIBLE_VERSION=<id>` selects `Bibles/<id>` (default `kjv`):

```sh
# 1. Embed all verses at 512 dims into the app container (~6 min on M3 Max; downloads the model once)
TEST_RUNNER_OPENBIBLE_BUILD_VERSE_INDEX=1 xcodebuild test -workspace OpenBibleAI.xcworkspace -scheme AllUnitTests \
  -destination 'platform=macOS' "-only-testing:OpenBibleAITests/VerseIndexBuilderTests/buildVerseIndex()" \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
# 2. Export the 256-dim index, then copy it into the package (container of the test host's bundle ID)
TEST_RUNNER_OPENBIBLE_EXPORT_VERSE_INDEX=1 xcodebuild test … "-only-testing:OpenBibleAITests/VerseIndexBuilderTests/exportBundledIndex()" …
cp ~/Library/Containers/<prefix>.OpenBibleAI/Data/Library/Application\ Support/OpenBibleAI/<id>-embeddings.bin Bibles/<id>/embeddings.bin
# 3. Evaluate retrieval and runtime/bundle consistency
TEST_RUNNER_OPENBIBLE_EVAL_RETRIEVAL=1 xcodebuild test … -only-testing:OpenBibleAITests/VerseIndexBuilderTests …
# Live answers: TEST_RUNNER_OPENBIBLE_LIVE_ASK=apple|standard|compact [TEST_RUNNER_OPENBIBLE_LIVE_ASK_SEMANTIC=1] … -only-testing:OpenBibleAITests/LiveAskBibleTests
#   (answersCiteVerifiedVerses: one question per chat; conversationsKeepContextAcrossTurns: English follow-ups and Spanish about attached John 3:16)
# Live chat UI (two turns, open a source, relaunch, reopen the saved chat):
TEST_RUNNER_OPENBIBLE_LIVE_ASK=1 xcodebuild test -workspace OpenBibleAI.xcworkspace -scheme OpenBibleAIUITests -destination 'platform=macOS' \
  -only-testing:OpenBibleAIUITests/BibleChatUITests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= BUNDLE_ID_PREFIX=dev.openbibleai.search-tests
```

Saved chats are JSON files in the app container under `Application Support/OpenBibleAI/Chats/` (one per chat, `schemaVersion` 1). If an Xcode debug session of the app is running, XCUITest cannot terminate it; the shared launch helper (`OpenBibleAIUITests/UITestLaunch.swift`) detects a debugger-attached copy and fails immediately with instructions. Use `BUNDLE_ID_PREFIX=dev.openbibleai.search-tests` or stop the session.

2026-10-01 (M3 Max): embedding 31,102 verses 376 s; runtime vs bundle worst cosine 0.9997; golden questions (question words only, no model keywords) keyword 5/12 (all Spanish missed) vs semantic/hybrid 11/12 at both 256 and 512 dims → 256 shipped. BM25 index build 200 ms once, query+passages 0.1 ms (Release).

## Search performance (text search)

Measured 2026-10-01 on Apple M3 Max (14 cores), macOS 27.0 (26A428), Xcode 27 / Swift 6.4, full bundled KJV (31,102 verses). Single machine, macOS only; no iOS/visionOS. Medians of 20 runs after 3 warm-ups; p95 in parentheses. Latency was the same for every query case (common, rare, no-match, multi-word, phrase, two-letter, diacritic) because cost is dominated by per-verse tokenization, not matching.

| Metric (Release) | Baseline | After |
|---|---|---|
| Search latency, all 8 query cases | 270–284 ms (p95 ≤ 291) | 85–88 ms (p95 ≤ 89) |
| Main-actor stall during a search | ≈ 283 ms (equals search time) | ≈ 2.1 ms |
| Repository load (decode + init) | 85 ms (init/sort alone 41 ms) | unchanged |
| Footprint: before load / after load | 7 / 31 MB | 7 / 30 MB |
| Footprint after searches | 32.6 MB | 38.4 MB, identical after a second full round (plateau, no growth) |

Debug baseline: ≈ 440–460 ms per search, main-actor gap ≈ 450–470 ms, init 98 ms. Debug was not re-measured after the changes.

Targets used: p95 ≤ 100 ms (Release) and no main-actor stall over one 16 ms frame. Both failed at baseline and both pass now.

Changes made, each because of a measurement: (1) `InMemoryBibleRepository.search` is `@concurrent` so the scan leaves the main actor (red test: `searchDoesNotBlockTheCallersMainActor`); (2) `BibleTextQuery.words(in:)` has an ASCII fast path that avoids Foundation folding. No index or per-verse cache was added; the targets are met without one. `SearchEquivalenceTests` checks the optimized results equal a reference matcher using the original rules on all 31,102 verses (13 queries, including diacritics and punctuation).

Remaining lever, not taken: 4,585 verses (14.7%) contain non-ASCII characters (`¶ Æ æ — ’`) and still use the slow folding path, plausibly about half of the remaining ~86 ms. Extending the fast path is the next step if latency needs to drop further. The footprint increase after searches is the allocator high-water mark from worker threads, not a leak (second round unchanged).

Commands (both skipped unless `OPENBIBLE_BENCH=1`, so normal runs stay fast):

```sh
# Latency, load time, memory (use without -c release for Debug)
OPENBIBLE_BENCH=1 swift test -c release --package-path Modules/BibleData --filter SearchPerformance

# Main-actor stall with the real BibleTextSearchModel (Release needs the extra settings)
TEST_RUNNER_OPENBIBLE_BENCH=1 xcodebuild test -workspace OpenBibleAI.xcworkspace -scheme AllUnitTests \
  -configuration Release -destination 'platform=macOS' -only-testing:OpenBibleAITests/SearchMainActorStallTests \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO
```

Without `ENABLE_HARDENED_RUNTIME=NO` the Release test bundle fails to load (Team ID mismatch). The benchmarks print tables and assert nothing about timing. `SearchEquivalenceTests` runs by default and takes a few seconds in Debug.

## Bible versions and provenance

No Bible ships inside the app. On first launch the user downloads a version (onboarding suggests one in their language); more can be added, switched, compared and deleted from the reader's version menu. Each version is a **package** whose files are assets of the single GitHub release **`bibles`** of this repository, named `<id>-<n>-<file>` (`<id>-<n>` is the package revision, e.g. `kjv-1`). Files that shrink by ≥ 5% are published compressed as `<file>.zlib` (raw DEFLATE) and decompressed on install. `LocalModelStore` downloads them (resumable, completion marker), checking the SHA-256 of the archive and of the installed file.

**Catalog.** The versions on offer are listed in `Tools/BibleImport/catalog.json` (`schema`, `sequence`, entries of version metadata plus pinned files). The app has it built in ([BibleCatalogEntry+Published.swift](OpenBibleAI/Features/BibleLibrary/BibleCatalogEntry+Published.swift), generated from it) and, when built with a catalog public key, also fetches the published `catalog.json` + `catalog.json.sig` from the `bibles` release at launch (`BibleLibraryModel.updateCatalog`). A remote catalog is accepted only if its **Ed25519 signature** verifies with `BIBLE_CATALOG_PUBLIC_KEY`, its schema is known, every entry downloads from this repository's `bibles` release, and its `sequence` is at least the built-in/last accepted one; it is cached and re-verified on launch, so offline launches keep it. New versions therefore appear **without an app update**. Each installed version is pinned to the entry it was installed from (`<Bibles>/<id>/entry.json`), so a later catalog never makes it disappear. When the catalog moves an installed version to a newer revision, Manage Bibles offers **Update** (`BibleLibraryModel.availableUpdate`/`update`): the new revision downloads into `<Bibles>/.staging/<id>` while the installed one stays readable, then replaces it in one `replaceItemAt`, is pinned, and is reopened if it is being read; a failed or cancelled update keeps the installed revision.

**Never delete or replace a published `<id>-<n>-*` asset.** Every build pins asset names and hashes; a deleted or changed asset breaks installs from that build forever. Fixes ship as a new package revision (`<id>-<n+1>`). Only `catalog.json` and `catalog.json.sig` are replaced. Downloading Bible text and indexes is data, which App Store guideline 2.5.2 allows (it forbids downloading code).

| Package file | Content |
|---|---|
| `version.json` | `id`, `name`, `abbreviation`, `language` (BCP-47), `copyright` |
| `books.json` | `book_id`, `name` (in the version's language), `canonical_order` |
| `verses.json` | `book_id`, `chapter`, `verse`, `text` |
| `embeddings.bin` | `VerseVectorIndex` (256-dim, format 2: int8 values plus a scale per verse, ~8 MB) built from that `verses.json` |

Book IDs follow the publisher's VPL export for every version (e.g. `JOH`, `SOL`), so a `BibleReference` names the same verse in each and comparison aligns by book, chapter and verse. A book's testament comes from its ID (the 27 New Testament IDs), so Catholic editions list their deuterocanonical books inside the Old Testament in the order of their book table (`books/en-catholic.json`: Tobit and Judith after Nehemiah, Wisdom and Sirach after Song of Solomon, Baruch after Lamentations, 1–2 Maccabees after Malachi; modern English names, e.g. 1 Samuel rather than Douay's 1 Kings). Preserve verse text exactly, including supplied-word brackets and the source's capitalization; conversion is not an editorial rewrite.

### Versions and licensing

| ID | Version | Language | Status |
|---|---|---|---|
| `kjv` | King James Version (eng-kjv2006) | en | Public domain (UK letters-patent qualification below). Package versioned in `Bibles/kjv/` (test fixture). |
| `rv1909` | Reina-Valera 1909 ([eBible spaRV1909](https://ebible.org/find/details.php?id=spaRV1909)) | es | Public domain. Package versioned in `Bibles/rv1909/` (test fixture); 31,084 verses (18 empty slots of eBible's KJV-numbered file skipped, listed by the converter). |
| `bsb` `msb` | Berean Standard Bible (engbsb), Majority Standard Bible (engmsb) | en | Public domain. |
| `web` `webbe` `webc` `webu` | World English Bible: US (engwebp), British (engwebpb), Classic (eng-web), Updated (engwebu) | en | Public domain. Classic and Updated: deuterocanon left out (`canon_only`). |
| `dra` | Douay-Rheims 1899 American Edition (engDRA) | en | Public domain (license checked 2026-10-03). 73 books with the deuterocanon, 35,811 verses as published: Vulgate Psalm numbering (titles as verses), Greek additions in Esther 10–16 and Daniel 3, 13–14, so Compare against Protestant versions misaligns there. |
| `webbe-dc` | World English Bible British Edition with Deuterocanon (eng-webbe) | en | Public domain (checked 2026-10-03). The Catholic 73 books (`books/en-catholic-greek.json` + `canon_only`): Greek Esther and Daniel (`ESG`, `DNG`, shown as Esther and Daniel) replace the shorter Hebrew ones; 1 Esdras, Prayer of Manasseh, Psalm 151, 3–4 Maccabees and 2 Esdras are left out. 35,379 verses (29 empty slots skipped, mostly Sirach). Because of the `ESG`/`DNG` IDs, Compare shows "—" for Esther and Daniel against other versions. |
| `wmb` `wmbbe` | World Messianic Bible: US (engwmb), British (engwmbb) | en | Public domain. |
| `asv` `asvbt` `rv1895` | American Standard Version 1901 (eng-asv), ASV Byzantine Text (engasvbt), Revised Version 1895 (eng-rv) | en | Public domain. ASVBT and RV: deuterocanon/Apocrypha left out (`canon_only`). |
| `ylt` `darby` `webster` `bbe` `gnv` | Young's Literal (engylt), Darby (engDBY), Webster 1833 (engwebster), Bible in Basic English (engBBE), Geneva 1599 (enggnv) | en | Public domain. |
| `lsv` | Literal Standard Version (englsv) | en | CC BY-SA 4.0, © 2020 Covenant Press. |
| `fbv` | Free Bible Version (engfbv) | en | CC BY-SA 4.0, © 2018 Dr. Jonathan Gallagher. |
| `ulb` | Unlocked Literal Bible (engULB) | en | CC BY-SA 4.0, © 2017 Door43 World Missions Community. |
| `t4t` | Translation for Translators (eng-t4t) | en | CC BY-SA 4.0, © 2008-2017 Ellis W. Deibler, Jr. Joins some verses (30,640). |
| `ojb` | The Orthodox Jewish Bible (engojb) | en | CC BY 4.0, © Artists for Israel International. Hebrew versification (Psalm titles as verse 1, Joel 3, …), so Compare misaligns there. |
| `bes` | La Biblia en Español Sencillo (spabes) | es | CC BY 4.0, © 2018, 2019 AudioBiblia.org / Irma Flores. |
| `pdpt` | Palabra de Dios para ti (spapddpt) | es | CC BY 4.0, © 2020 Asociación Bíblica Latinoamericana. |
| `vbl` | Versión Biblia Libre (spavbl) | es | CC BY-SA 4.0, © 2018-2020 Jonathan Gallagher y Shelly Barrios de Avila. |
| `nbv` | Biblica® Open Nueva Biblia Viva (spaonbv) | es | CC BY-SA 4.0, © 2006, 2008 Biblica, Inc.; must be shared unchanged; "Biblica" is a trademark used with permission. A paraphrase that joins verses (29,102). |
| `blivre` | Bíblia Livre (porbr2018), Almeida 1819 Textus Receptus updated | pt-BR | CC BY 4.0, © 2018 Diego Santos, Mario Sérgio e Marco Teles. Suggested first for Portuguese. |
| `nbv-pt` | Biblica® Open Nova Bíblia Viva (poronbv) | pt-BR | CC BY-SA 4.0, © 2007, 2010 Biblica, Inc.; same Biblica terms as `nbv`. |
| — | Almeida Revista e Corrigida 1911 | pt | Public domain edition, but no source of verified provenance found (2026-10-02): the known digital text comes from a withdrawn CrossWire module, redistributed by the Aionian Bible with edits. Not built. |
| — | Reina-Valera 1960 | es | © Sociedades Bíblicas Unidas, administered by the American Bible Society (licensing@americanbible.org). Requires a license before it is built or published. |
| — | Almeida (modern ARC/ACF) | pt | © SBB / SBTB. Requires a license. |
| — | Drafts: Santa Biblia libre para el mundo (spablm), Santa Biblia libre Latinoamericano (spabll), Bíblia Portuguesa Mundial (porbrbsl) | es, pt | Public domain, but their publishers call them drafts under review. Not built. |
| — | WEB Catholic (eng-web-c) | en | Public domain, but eBible's VPL export (txt, xml and sql, checked 2026-10-03) has no Genesis; only the USFM archive has it. Not built until the VPL is fixed or a USFM converter exists; Genesis is not patched in from another edition. `webbe-dc` is the WEB with the Catholic canon meanwhile. |
| — | NET, NASB, AMP, ERV, GOD'S WORD; LBLA, NBLH, Reina-Valera Gómez, Valera 1602 Purificada; ARA, NAA, NVI, NTLH | en, es, pt | Copyrighted without an open license. Wycliffe Modern Spelling is CC BY-NC-ND. Incomplete texts (NT or OT only: Open English Bible, Tyndale, EMTV, JPS 1917, Brenton, porblt, portft, …) are left out. |

Rights were checked on 2026-10-02 against eBible.org's [copyright list](https://ebible.org/Scriptures/copyright.php), each version's details page and the `*_about.htm` notice inside its archive (recorded as `license_checked` in the recipe). The `copyright` line in `version.json` carries the license, and onboarding and Manage Bibles show it. CC BY-SA packages are redistributed under the same license. Versification differences against the KJV are as published; mostly verses modern critical texts omit (Matthew 17:21, Acts 8:37, …; 16 in BSB/ASV/VBL), shown as "—" in Compare.

Only public-domain, openly licensed (CC BY / CC BY-SA) or licensed texts may be published. Keep licensed sources in the ignored `Tools/BibleImport/Source/` and never commit their generated JSON.

**KJV attribution and notice:** source ID **`eng-kjv2006`**, standardized 1769 text, protocanon only, courtesy of the CrossWire Bible Society and eBible.org ([details and terms](https://ebible.org/details.php?id=eng-kjv2006), [VPL archive](https://ebible.org/Scriptures/eng-kjv2006_vpl.zip)). The notice dated 2026-09-26 labels the work Public Domain while identifying special letters-patent restrictions on printing/importing printed copies in the United Kingdom; preserve that qualification and review territory/format requirements before release. The archive is Bible text only (no notes, headings or introductions); the app must not imply otherwise.

### Adding or updating a Bible version

Packages are **not** stored in git (except the `kjv` and `rv1909` test fixtures): each is rebuilt from its recipe, built into the ignored `Bibles/<id>/`, and published as release assets. Recipes live in `Tools/BibleImport/versions/<id>.json`: version metadata (the `copyright` line names the license), `source`/`source_url`, `license_checked`, book-name table (`Tools/BibleImport/books/<lang>.json`, or `en-catholic` for a Catholic canon), expected counts, `skip_empty_verses`, `canon_only` (leave out an edition's deuterocanon) and `package` (revision number, default 1).

1. **License.** Public domain, CC BY 4.0, CC BY-SA 4.0, or written permission; a complete 66-book text (or one whose extra books `canon_only` removes). Check the publisher's terms and the archive's `*_about.htm`; record the date in `license_checked`.
2. **Recipe.** Add `versions/<id>.json` (set `expected_verses` from the converter's count and explain any gap against the KJV).
3. **Build:** `Tools/BibleImport/add_version.sh <id>` downloads the source, converts it (validation plus versification report), embeds every verse (~6 min on Apple silicon), exports the int8 index to `Bibles/<id>/embeddings.bin` and checks the runtime embedder reproduces it (worst cosine ≥ 0.99).
4. **Review** the report: counts, versification gaps, copyright line, sizes.
5. **Stage and pin:** `python3 Tools/BibleImport/make_release.py <id>` adds the entry to `catalog.json` (`sequence + 1`), regenerates the Swift catalog, stages the assets in `Tools/BibleImport/Release/` and prints the `gh release upload bibles …` command. It refuses to re-pin a published revision with different bytes (bump `package`).
6. **Upload** the assets with the printed command, then **commit and push** the recipe, `catalog.json` and the Swift catalog.
7. **Approve** the *Publish catalog* workflow run (`.github/workflows/publish-catalog.yml`, environment `release`): it checks every pinned asset is published with its size and hash and the sequence is newer, signs `catalog.json` with the `CATALOG_SIGNING_KEY` secret and uploads `catalog.json` + `.sig` to the release. Existing installs see the new version on next launch.

To fix a published text, bump `package` in the recipe and repeat; the old assets stay for builds that pin them. Privately licensed texts follow the same flow, but their sources stay in the ignored `Source/`.

**Signing key.** Ed25519, created once with `Tools/BibleImport/catalog_key.sh generate`: the private key goes to the login Keychain ("OpenBibleAI catalog signing"), and the printed public key (hex) goes in `BIBLE_CATALOG_PUBLIC_KEY` in `Config/Local.xcconfig` (compiled into the app by the *Generate build settings* phase, `Tools/generate_build_settings.sh`, as the gitignored `OpenBibleAI/Generated/BuildSettings.swift`; builds without it use only the built-in catalog). Store the private key as the GitHub secret with `catalog_key.sh export-private | gh secret set CATALOG_SIGNING_KEY --env release` and keep a backup in a password manager; it must never be committed or put in an xcconfig (those values are compiled into the app). If it is lost, remote catalogs stop until an app update ships a new public key; if it leaks, a forged catalog can still only point at this repository's `bibles` release. Without the workflow: `catalog_key.sh verify-assets` then `sign`, and upload with `--clobber`.

`PublishedBibleCatalogTests` checks the built-in catalog equals `catalog.json` and every entry against its package when present locally; `TEST_RUNNER_OPENBIBLE_VERIFY_RELEASES=1` downloads every pinned asset and checks it after publishing. For the KJV, `convert_vpl.py` reproduces `Bibles/kjv/books.json` and `verses.json` byte for byte. To convert older Float16 indexes, `TEST_RUNNER_OPENBIBLE_REQUANTIZE_INDEX=1` re-encodes every `Bibles/*/embeddings.bin` as int8 (into the test host's container) and checks search agreement.

### Recorded SHA-256 values

These identify the files measured on 2026-09-30, not a promise that the publisher's mutable URL will always return identical bytes.

| File | SHA-256 |
|---|---|
| `eng-kjv2006_vpl.zip` | `1cb3e91ecba56b2f266b7b6fe2c5bf88289fa487f980fba13fca9fa942dd21af` |
| `eng-kjv2006_vpl.txt` | `68c5f764bf1c204868c3eb72592035c0947f057b608c2149dbff765d8ddd86f6` |
| `eng-kjv2006_about.htm` | `c8866ab3be88ef08e6457a5eb4dac546038c4202411cb7fbfc9cd44ad453cf48` |
| `Bibles/kjv/books.json` | `8ee8b3d8827b880522ad35c2e235ff0d009cb990ab861233910e1925f959c3dd` |
| `Bibles/kjv/verses.json` | `53f72606c548907934bc3109d7dba2185eede224e445c70e30bd0d99cc516d69` |

### Read-only dataset verification

```bash
python3 - <<'PY'
import json
from pathlib import Path

books = json.loads(Path('Bibles/kjv/books.json').read_text())
verses = json.loads(Path('Bibles/kjv/verses.json').read_text())
book_ids = {b['book_id'] for b in books}
references = {(v['book_id'], v['chapter'], v['verse']) for v in verses}

assert len(books) == len(book_ids) == 66
assert sorted(b['canonical_order'] for b in books) == list(range(1, 67))
assert all(b['book_id'].strip() and b['name'].strip() for b in books)
assert len(verses) == len(references) == 31102
assert {v['book_id'] for v in verses} == book_ids
assert all(v['chapter'] > 0 and v['verse'] > 0 and v['text'].strip() for v in verses)
print('Verified 66 books and 31102 unique, nonempty verse records')
PY
```

## Localization

The UI is localized with a String Catalog, [OpenBibleAI/Localizable.xcstrings](OpenBibleAI/Localizable.xcstrings): English source, Spanish (`es`) and Brazilian Portuguese (`pt-BR`), following the system language. Scripture is never translated; it comes from the chosen version. Use `LocalizedStringKey` literals in views and `String(localized:)` for strings built in models (status and error messages). Counts use plural variations.

After adding or changing UI strings, build for macOS and iOS (some strings are platform-only), sync the catalog, translate the new keys and remove stale ones:

```bash
xcrun xcstringstool sync OpenBibleAI/Localizable.xcstrings --stringsdata \
  <DerivedData>/Build/Intermediates.noindex/OpenBibleAI.build/Debug/OpenBibleAI.build/Objects-normal/arm64/*.stringsdata \
  <DerivedData>/Build/Intermediates.noindex/OpenBibleAI.build/Debug-iphonesimulator/OpenBibleAI.build/Objects-normal/<arch>/*.stringsdata
```

`LocalizationCatalogTests` fails when a key lacks an `es` or `pt-BR` translation or changes its placeholders; `LocalizationUITests` launches the app in each language.

## Manual regression checklist

Record these independently of automated test results:

1. Browse Genesis through Revelation. Genesis has 50 chapters; Psalms has 150.
2. Open John 3 and select verse 16 from the chapter text; verify highlighting and the AI panel. Select another verse from the sidebar and verify scrolling.
3. Scroll Psalm 119 through its 176 verses; check that chapter navigation stays available.
4. Verify Previous disabled at Genesis 1 and Next disabled at Genesis 50. Changing book/chapter clears verse selection and the previous AI interaction.
5. Rapidly switch chapters/books and confirm the final chapter and text match the selected identity.
6. Quit normally and relaunch after both sidebar chapter-grid selection and Previous/Next navigation (including a cross-book step such as Malachi 4 → Matthew 1). Restore book/chapter without automatically selecting a verse.
7. Search `John 3:16`, `1 John 2:1`, and `Song of Solomon 1:2`; each opens the chapter, highlights the verse, and enables the AI panel. Invalid input, an unknown book, and `John 999:999` show feedback without changing the current chapter. Relaunch restores the searched book/chapter.
8. First launch with nothing installed (or a fresh container): onboarding lists the published versions, suggests one for the system language, downloads with progress and Cancel, then Start Reading opens the reader. Switch versions from the toolbar menu (book and chapter stay), compare two or more versions in aligned columns, delete a version from Manage Bibles (not the one in use), and check the UI in Spanish and Portuguese.
9. On iPhone (portrait and landscape) and iPad (landscape, portrait, Split View ⅓): every tab and screen fits without sideways scrolling; books → chapter → verse → Ask about → Chat; a citation returns to Read; switching size class keeps the chapter and chat; large Dynamic Type and Dark Mode stay readable.
10. With an engine available (Apple Intelligence, or the downloaded model), ask a question, observe streaming, and test Stop/selection changes. On a device without Apple Intelligence, check the download, progress, cancel and delete flow. Keep this result separate from mocked provider tests.

## Troubleshooting and delivery

- A version fails to load: check its package folder under `Application Support/OpenBibleAI/Bibles/<id>` (all four files, `.complete` marker matching the pinned tag) before changing decoding code. Deleting it from Manage Bibles and downloading again re-verifies every file.
- Invalid JSON/data: preserve the error and source snapshot; check conversion and domain validation instead of inserting placeholders into scripture.
- Graph does not show a recent symbol: inspect coverage/freshness and current files. The handoff used source fallback for stale graph metadata.
- First launch has no reading position: normal behavior. Invalid/unavailable saved positions leave the reader at selection; storage and navigation tests inject an in-memory `ReadingPositionStorage` fake, not UserDefaults.
- A planned test is not in a result: verify scheme/test-plan selection. `OpenBibleAIUITests` and live model checks are not included in the 115-test baseline.
- Review only intended files for a milestone commit. Include changed Xcode project configuration when needed, but exclude local signing settings, source downloads, and build caches.
