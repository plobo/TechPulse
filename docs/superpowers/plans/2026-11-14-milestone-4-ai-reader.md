# Milestone 4 — On-device AI Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AI summaries (3 lengths), Ask-this-article, code explanation and validated architecture diagrams, all powered by Apple's on-device model, with a Debug-only Demo AI, on-device persistence via a V1→V2 SwiftData migration, and AI history in the AI Reader tab.

**Architecture:**
- Pure, framework-free units handle input building, prompts, diagram validation, Mermaid, layout and the request gate. They sit behind a reshaped provider-neutral `AIService` with three implementations: Foundation Models (iOS 26), Demo (Debug) and Unavailable.
- AI artifacts and conversations persist in `SwiftDataLibraryRepository` under `TechPulseSchemaV2`.
- `@MainActor @Observable` view models drive the SwiftUI screens, following the existing MVVM/DI patterns.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, FoundationModels (iOS 26, `#if canImport` + `@available`), CryptoKit, Swift Testing, XCTest UI tests, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-14-milestone-4-ai-reader-design.md`

## Global Constraints

- iOS deployment target stays **17.0**. Every FoundationModels use sits under `#if canImport(FoundationModels)` and `@available(iOS 26, *)`.
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: complete`; zero new warnings.
- Every AI output shows the existing `GeneratedContentBadge` ("AI-generated") and the model/provider name.
- When the input is not full text, show the label **"Based on the excerpt only"** (excerptOnly) or **"Based on title and summary only"** (metadataOnly).
- AI output about sample data also shows `SampleDataBadge`.
- Demo output always shows **"Demo AI — fake output"**. Demo exists only under `#if DEBUG`.
- The code-explanation caveat is copy verbatim: **"AI explanations can be wrong and are not a security review."**
- Model input for an article is built only from what `ArticleBodyPolicy` permits. Article text is delimited untrusted data. Notes, history and preferences never enter a prompt.
- Diagram limits: **≤ 12 components, ≤ 20 connections**, labels capped; never partially rendered; no web view.
- AI is off by default (`UserPreferences.aiFeaturesEnabled == false`). No test may depend on the real model.
- Test commands:
  - unit: `xcodegen generate -q && xcodebuild test -project TechPulseAI.xcodeproj -scheme TechPulseAI -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TechPulseAITests`
  - UI: same command with `-only-testing:TechPulseAIUITests`

## Review Focus

1. Article text containing the delimiter tokens or "ignore previous instructions" stays inert data inside the delimiters → pinned in Task 1 (`articleTextCannotCloseDelimiterBlock`).
2. Model diagram with cycles/self-loops: validation accepts cycles, rejects self-loops, and layout always terminates → pinned in Task 2 (`layoutTerminatesOnCycles`).
3. User leaves the article mid-generation: the task is cancelled, nothing partial is persisted, and the gate is released so the next request works → pinned in Task 6 (`cancelledSummaryPersistsNothingAndReleasesGate`).
4. Long chats exceed the context budget: older turns are trimmed, and the newest question is always kept → pinned in Task 1 (`questionPromptTrimsOldestHistoryToBudget`).
5. Demo toggled off after generating demo results: demo-cached output is never shown as real output → pinned in Task 5 (`cacheKeySeparatesDemoFromRealProvider`).

---

### Task 1: AI input building and prompts

**Files:**
- Modify: `TechPulseAI/Domain/Models/AI.swift` (replace contents)
- Create: `TechPulseAI/Domain/UseCases/AIPrompts.swift`
- Test: `Tests/TechPulseAITests/AIPromptTests.swift`

**Interfaces:**
- Produces:
  - `enum AIInputBasis: String, Codable, Sendable { case fullText, excerptOnly, metadataOnly }` with `var label: String?` (nil for fullText).
  - `enum SummaryType: String, Codable, Sendable, CaseIterable { case thirtySeconds, twoMinutes, detailed }` with `title` and `init(_ length: SummaryLength)`.
  - `struct AIArticleInput: Sendable, Hashable { articleID, title, sourceName, text, basis: AIInputBasis, fingerprint: String; static func make(from: Article, budget: Int = AIPrompts.articleBudget) -> AIArticleInput }`
  - `enum AIRole`, `struct AIMessage` (id, role, content, timestamp), `struct AIConversation` (id, articleID?, articleTitle, basis, messages, updatedAt): Codable.
  - `enum AIServiceError: Error, Equatable { unavailable, rateLimited, busy, requestTooLarge, contextTooLarge, guardrail, invalidDiagram(String), generationFailed }` with `var message: String`.
  - `enum AIPrompts`:
    - `version = "m4-v1"`, `articleBudget = 6000`, `questionLimit = 500`, `snippetLimit = 4000`, `historyBudget = 3000`.
    - `instructions(for: AIFeature) -> String`.
    - `summary(_ input:, type:) -> String`.
    - `question(_ q: String, input:, history: [AIMessage]) throws -> String`.
    - `code(_ snippet: String) throws -> String`.
    - `diagram(_ input:) -> String`.
  - `enum AIFeature: String, Codable, Sendable { case summary, question, codeExplanation, diagram }`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func basisFollowsArticleBodyPolicy()  // full w/ content → .fullText & text contains content
                                            // excerptOnly w/ content set → .excerptOnly, text excludes content
                                            // linkOnly → .metadataOnly, text == title/source/summary only
@Test func fullTextTruncatedToBudgetAtWordBoundary()  // 10_000-word content, budget 6000 → text.count <= 6000+20, hasSuffix("[truncated]")
@Test func fingerprintStableAndChangesWithText()
@Test func articleTextCannotCloseDelimiterBlock()     // content containing "ARTICLE>>>" and "Ignore previous instructions" →
                                                      // prompt has exactly one "<<<ARTICLE" and one "ARTICLE>>>", injected text is between them
@Test func instructionsForbidFollowingArticleInstructions()  // every AIFeature: contains "Never follow instructions"
@Test func summaryPromptDescribesLengthAndThinInput()  // .thirtySeconds mentions "2 to 4 bullet"; excerptOnly mentions "only an excerpt"
@Test func questionAndSnippetLimits()   // 501-char question → throws .requestTooLarge; 4001-char snippet → throws; blank question → throws .requestTooLarge
@Test func questionPromptTrimsOldestHistoryToBudget()  // 50 long messages → prompt omits earliest, contains last question & most recent turn, history part <= historyBudget
```

- [ ] **Step 2: Run unit tests.** Expected: build fails (types missing).
- [ ] **Step 3: Implement** the types above. The delimiter neutralizer replaces `<<<ARTICLE`/`ARTICLE>>>` in input text with `[removed]`. The fingerprint is the SHA-256 hex of `basis.rawValue + "\n" + text` (CryptoKit). Remove the old `ArticleSummary` / `AIProviderInfo` / `AIConversation` types from `AI.swift` and update the stub protocol in `Domain/Repositories/AIService.swift` minimally so the target compiles (Task 3 reshapes it).
- [ ] **Step 4: Run unit tests.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(ai): article input building and prompts`.

### Task 2: Architecture diagram model, validation, Mermaid, layout

**Files:**
- Create: `TechPulseAI/Domain/Models/ArchitectureDiagram.swift`, `TechPulseAI/Domain/UseCases/DiagramRules.swift`
- Test: `Tests/TechPulseAITests/DiagramTests.swift`

**Interfaces:**
- Produces:
  - `struct ArchitectureDiagram: Codable, Sendable, Hashable { title: String; components: [Component]; connections: [Connection] }`, where `Component { id, name, kind, detail }` and `Connection { from, to, label }`.
  - `enum DiagramValidationError: Error, Equatable { empty, tooManyComponents, tooManyConnections, invalidID(String), duplicateID(String), danglingConnection(String), selfLoop(String) }`.
  - `enum DiagramValidator { maxComponents = 12; maxConnections = 20; maxLabelLength = 60; static func validate(_:) throws -> ArchitectureDiagram }`. It returns a sanitized copy: trimmed, control characters stripped, labels truncated. IDs must match `^[A-Za-z][A-Za-z0-9_]{0,31}$`.
  - `enum MermaidGenerator { static func source(for: ArchitectureDiagram) -> String }`.
  - `enum DiagramLayout { static func layers(for: ArchitectureDiagram) -> [[String]] }`: longest-path layering, ignoring back-edges.
  - `enum DiagramTextDescription { static func text(for:) -> String }`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func validDiagramPassesAndIsSanitized()   // name "  API\u{0007} " → "API"; 80-char label → 60 chars
@Test func rejectsStructuralProblems()          // empty, 13 components, 21 connections, "1bad" id, duplicate id, dangling "x", self-loop a→a — each the matching error
@Test func mermaidEscapesLabelsAndIsWellFormed() // first line "flowchart TD"; name with quotes → contains "#quot;"; edge "a -->|\"reads\"| b"; no raw "<script"
@Test func layoutTerminatesOnCycles()            // a→b→c→a plus c→d → returns within test, every id appears exactly once
@Test func layoutOrdersSourcesFirst()            // a→b, b→c → [["a"],["b"],["c"]]
@Test func textDescriptionListsComponentsAndConnections() // contains "API (service)" and "API → DB: reads"
```

- [ ] **Step 2: Run.** Expected: build fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `feat(ai): diagram validation, Mermaid and layout`.

### Task 3: AIService protocol, availability, request gate, Demo and service selection

**Files:**
- Modify: `TechPulseAI/Domain/Repositories/AIService.swift` (replace)
- Create: `TechPulseAI/Data/AI/DemoAIService.swift`, `TechPulseAI/Domain/UseCases/AIRequestGate.swift`
- Modify: `TechPulseAI/App/AppDependencies.swift`, `TechPulseAI/App/AppConfiguration.swift`, `TechPulseAI/Domain/Models/Library.swift` (prefs)
- Test: `Tests/TechPulseAITests/AIServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 and Task 2 types.
- Produces:
  - `enum AIAvailability: Equatable, Sendable { case available, deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady, unsupportedOS }` with `var message: String`.
  - `struct AIProviderInfo: Codable, Sendable, Hashable { provider; model; isDemo: Bool }`.
  - `struct CodeExplanation: Codable, Sendable, Hashable { language; explanation; risks: [String]; static let caveat = "AI explanations can be wrong and are not a security review." }`.
  - The protocol:
    ```swift
    protocol AIService: Sendable {
      var providerInfo: AIProviderInfo { get }
      func availability() async -> AIAvailability
      func summarize(_ input: AIArticleInput, type: SummaryType) async throws -> String
      func answer(_ question: String, input: AIArticleInput, history: [AIMessage]) async throws -> String
      func explainCode(_ snippet: String) async throws -> CodeExplanation
      func diagram(for input: AIArticleInput) async throws -> ArchitectureDiagram   // raw; callers validate
    }
    ```
  - `UnavailableAIService(reason: AIAvailability = .unsupportedOS)`.
  - `#if DEBUG struct DemoAIService`: provider "Demo AI", model "demo", isDemo true. Every text starts with `"[Demo AI — fake output] "`. `diagram` returns a valid 4-component sample. Optional `delay: Duration`.
  - `actor AIRequestGate { init(maxPerMinute: Int = 10, dateProvider: any DateProvider); func begin(_ key: String) throws; func end(_ key: String) }`. It throws `.busy` when the key is in flight and `.rateLimited` after maxPerMinute begins within 60 s.
  - `struct AIServices: Sendable { real: any AIService; demo: (any AIService)?; func active(demoEnabled: Bool) -> any AIService }`. `AppDependencies.ai` becomes `AIServices`; `AppDependencies` also gains `aiGate: AIRequestGate`.
  - `UserPreferences` gains `demoAIEnabled = false` and `aiGenerationCount = 0` (JSON blob; decoding old payloads must still work → custom `init(from:)` using `decodeIfPresent`).
  - `AppConfiguration.forcesDemoAI` is true for `-ui-testing` + `-demo-ai`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func gateRejectsConcurrentSameKeyAndAllowsAfterEnd()
@Test func gateRateLimitsWithinSixtySeconds()        // maxPerMinute 2: 3rd begin throws .rateLimited; with now+61s allowed
@Test func servicesPickDemoOnlyWhenEnabledAndPresent()
@Test func demoOutputIsMarkedFake()                  // summarize/answer/explain prefixed; explainCode language non-empty
@Test func demoDiagramIsValid()                      // DiagramValidator.validate does not throw
@Test func unavailableServiceThrowsUnavailable()
@Test func oldPreferencesPayloadStillDecodes()       // JSON without new keys → demoAIEnabled false, count 0
@Test func demoForcedOnlyUnderUITesting()
```

- [ ] **Step 2: Run.** Expected: build fails.
- [ ] **Step 3: Implement.** In `AppDependencies.live`, `real` = `FoundationModelsAIService()` when available at compile/run time (Task 4 adds it; until then `UnavailableAIService()`), and `demo` = `DemoAIService()` under `#if DEBUG`. Wire both regardless of data source.
- [ ] **Step 4: Run.** Expected: pass; existing tests still green.
- [ ] **Step 5: Commit** `feat(ai): provider-neutral service, availability, gate, demo`.

### Task 4: Foundation Models service (compile-verified only)

**Files:**
- Create: `TechPulseAI/Data/AI/FoundationModelsAIService.swift`
- Modify: `TechPulseAI/App/AppDependencies.swift`
- Test: `Tests/TechPulseAITests/AIServiceTests.swift` (availability mapping)

**Interfaces:**
- Produces:
  - `@available(iOS 26, *) struct FoundationModelsAIService: AIService` with provider "Apple Foundation Models" and model "SystemLanguageModel.default".
  - `enum AIAvailabilityMapper { static func map(isAvailable: Bool, reason: String?) -> AIAvailability }`, a pure mapping keyed on the reason names `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`.
  - `static func makeRealService() -> any AIService` in `AppDependencies` returns the FM service on iOS 26 and `UnavailableAIService(.unsupportedOS)` otherwise.

- [ ] **Step 1: Write failing test** `availabilityMapperCoversAllReasons()`: each reason string maps to the matching case, `isAvailable` → `.available`, unknown → `.deviceNotEligible`.
- [ ] **Step 2: Run.** Expected: fail.
- [ ] **Step 3: Implement.**
  - Each call creates a fresh `LanguageModelSession(instructions: AIPrompts.instructions(for:))`; sessions are not shared across concurrency domains.
  - Use `respond(to:)` for text. Use `respond(to:generating:)` with private `@Generable` types `GenDiagram` / `GenCodeExplanation` mapped to domain types.
  - Map errors: `exceededContextWindowSize` → `.contextTooLarge`, `guardrailViolation` → `.guardrail`, `rateLimited` / `concurrentRequests` → `.rateLimited`, else `.generationFailed`.
  - Map availability via `SystemLanguageModel.default.availability`.
- [ ] **Step 4: Run unit tests.** Expected: pass; the app target builds with FoundationModels linked weakly. Real output is unverified (ledger note).
- [ ] **Step 5: Commit** `feat(ai): Foundation Models service`.

### Task 5: Persistence V2 — AI artifacts and conversations

**Files:**
- Modify: `TechPulseAI/Core/Persistence/Schema.swift` (add `TechPulseSchemaV2`, stage), `TechPulseAI/Core/Persistence/SwiftDataLibraryRepository.swift`, `TechPulseAI/Domain/Repositories/Repositories.swift`, `TechPulseAI/Domain/Models/Library.swift` (`LibraryExport.ai`)
- Create: `TechPulseAI/Domain/Models/AIActivity.swift`
- Test: `Tests/TechPulseAITests/AIPersistenceTests.swift`

**Interfaces:**
- Produces:
  - `enum AIArtifactKind: String, Codable, Sendable { case summary, codeExplanation, diagram }`.
  - `struct AIArtifact: Identifiable, Codable, Sendable, Hashable`, with fields:
    - `id: UUID`, `kind`, `cacheKey: String`;
    - `articleID: ArticleID?`, `articleTitle: String?`, `summaryType: SummaryType?`, `basis: AIInputBasis?`;
    - `provider: AIProviderInfo`, `promptVersion`;
    - `text: String?`, `code: CodeExplanation?`, `diagram: ArchitectureDiagram?`;
    - `createdAt`.
  - `enum AICacheKey { static func summary(_ input: AIArticleInput, type: SummaryType, provider: AIProviderInfo) -> String; static func diagram(_ input:, provider:) -> String }`, built from articleID|feature|type|fingerprint|AIPrompts.version|provider.model|isDemo.
  - `enum AIActivityItem: Identifiable, Codable, Sendable, Hashable { case artifact(AIArtifact), conversation(AIConversation) }` with `date`.
  - `protocol AILibraryRepository: Sendable` (adopted by `SwiftDataLibraryRepository`):
    - `artifact(cacheKey:) async throws -> AIArtifact?`
    - `saveArtifact(_:) async throws` (upsert by cacheKey)
    - `conversation(articleID:) async throws -> AIConversation?`
    - `saveConversation(_:) async throws`
    - `recentAIActivity(limit: Int) async throws -> [AIActivityItem]`
    - `deleteAIItem(id: UUID) async throws`
    - `clearAIHistory() async throws`
  - `AppDependencies.aiLibrary: any AILibraryRepository` (same actor instance as `library`).
  - `TechPulseSchemaV2` adds the `AIArtifactRecord` and `AIConversationRecord` `@Model`s (payload JSON `Data` + indexed `cacheKey` / `articleID` / `updatedAt`). `TechPulseMigrationPlan.stages = [.lightweight(fromVersion: V1, toVersion: V2)]`. `PersistenceController` opens V2.
  - `exportData()` includes `ai: [AIActivityItem]` (decoding older exports without it must work), `deleteAllData()` clears AI records, and `clearCache()` leaves them.

- [ ] **Step 1: Write failing tests**

```swift
@Test func v1StoreMigratesToV2KeepingUserData()   // container with Schema(versionedSchema: V1) at temp URL: insert bookmark+note → reopen via PersistenceController → bookmark & note present, AI empty
@Test func artifactUpsertAndLookupByCacheKey()
@Test func conversationSaveAndResumeByArticle()
@Test func recentActivityNewestFirstAcrossKinds()
@Test func deleteAndClearAIHistory()
@Test func exportIncludesAIAndDeleteAllRemovesIt()
@Test func clearCacheKeepsAIHistory()
@Test func cacheKeySeparatesDemoFromRealProvider()
```

- [ ] **Step 2: Run.** Expected: build fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all unit tests.** Expected: pass (including all pre-existing persistence tests).
- [ ] **Step 5: Commit** `feat(ai): schema V2 with AI history and migration`.

### Task 6: AI view models

**Files:**
- Create: `TechPulseAI/Features/AIReader/ArticleAIViewModel.swift`, `AskArticleViewModel.swift`, `CodeExplainerViewModel.swift`, `DiagramViewModel.swift`, `AIReaderViewModel.swift`, `AIReport.swift`
- Modify: `TechPulseAI/Features/Settings/SettingsViewModel.swift`, `TechPulseAI/Features/Library/LibraryStore.swift` (generation count increment)
- Test: `Tests/TechPulseAITests/AIViewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces (all `@MainActor @Observable`):
  - `ArticleAIViewModel(article: Article, dependencies:, library:)`:
    - state: `selectedType: SummaryType` (default from prefs), `summaries: [SummaryType: LoadState<AIArtifact>]`, `availability: AIAvailability?`, `isEnabled: Bool` (prefs on && available), `isSampleData`, `provider`;
    - actions: `load()` (availability + cached), `generate(_ type:, force: Bool = false) async`, `cancel()`.
  - `AskArticleViewModel(article:, dependencies:, library:)`: `conversation: AIConversation`, `draft`, `isAnswering`, `error: String?`, `send() async` (persists after each answer).
  - `CodeExplainerViewModel(article: Article?, dependencies:, library:)`: `snippet`, `result: LoadState<AIArtifact>`, `explain() async`.
  - `DiagramViewModel(article:, dependencies:, library:)`: `state: LoadState<AIArtifact>`, `load() async` (cache first), `generate(force:) async`. Validation failure → `.failed(.unexpected)` with `errorMessage` set from `AIServiceError.invalidDiagram`.
  - `AIReaderViewModel(dependencies:, library:)`: `items: [AIActivityItem]`, `availability`, `load()`, `delete(_:)`, `clearAll()`.
  - `enum AIReport { static func text(articleID:, kind:, output:, provider:, promptVersion:, basis:) -> String }`.
  - `SettingsViewModel` gains `setDemoAI(_:)` (DEBUG), `aiAvailability`, `loadAIAvailability() async`, `clearAIHistory() async`.
  - Every successful generation calls `library.updatePreferences { $0.aiGenerationCount += 1 }` and holds the gate key `"\(articleID)|\(feature)"` for the call.

- [ ] **Step 1: Write failing tests** (use `DemoAIService(delay:)`, a `ThrowingAIService` test double, and the in-memory store):

```swift
@Test func summaryUsesCacheOnSecondLoad()            // generate → new VM load() shows same artifact without calling service (counting double)
@Test func summaryLabelsBasisForExcerptArticle()     // artifact.basis == .excerptOnly
@Test func regenerateReplacesCachedSummary()
@Test func cancelledSummaryPersistsNothingAndReleasesGate()  // delay 1s, cancel → no artifact saved, next generate succeeds
@Test func disabledOrUnavailableBlocksGeneration()   // prefs off → isEnabled false, generate no-op
@Test func askPersistsConversationAndResumes()
@Test func askRejectsOverlongQuestionWithMessage()
@Test func codeExplanationSavedWithCaveatAvailable()
@Test func invalidDiagramIsRejectedNotSaved()        // double returns self-loop → state failed, no artifact
@Test func aiReaderListsAndClearsActivity()
@Test func generationCountIncrements()
@Test func reportTextIncludesProvenanceButNoNotes()
```

- [ ] **Step 2: Run.** Expected: build fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all unit tests.** Expected: pass.
- [ ] **Step 5: Commit** `feat(ai): AI view models`.

### Task 7: AI UI, settings, AI Reader tab, UI tests, docs

**Files:**
- Create: `TechPulseAI/Features/AIReader/AIPanels.swift` (summary panel, labels row), `AskArticleSheet.swift`, `CodeExplainerSheet.swift`, `DiagramSheet.swift` (native drawing + text alternative + Mermaid copy/share)
- Modify:
  - `TechPulseAI/Features/AIReader/AIReaderView.swift` (activity list + explainer entry + availability empty state);
  - `TechPulseAI/Features/ArticleDetail/ArticleDetailView.swift` (replace `AISummaryPanel`; add Ask / Explain code / Diagram actions);
  - `TechPulseAI/Features/Settings/SettingsView.swift` (availability footer, Demo toggle under `#if DEBUG`, generation count, Clear AI history);
  - `TechPulseAI/Core/DesignSystem/Components.swift` (`DemoAIBadge`, `InputBasisLabel`);
  - `README.md`;
  - `Tests/TechPulseAIUITests/TechPulseAIUITests.swift`.

**Interfaces:**
- Consumes: Task 6 view models.
- Produces: accessibility identifiers `ai.summary.panel`, `ai.summary.type`, `ai.summary.text`, `ai.label.basis`, `ai.label.demo`, `ai.ask`, `ai.ask.field`, `ai.ask.send`, `ai.diagram`, `ai.diagram.text`, `ai.diagram.copy`, `ai.code`, `aiReader.list`.

- [ ] **Step 1: Write failing UI tests** (launch `-ui-testing -demo-ai`; demo forces AI enabled):

```swift
func testSummaryLengthSwitchShowsLabels()      // open first card, ai.summary.panel exists, tap "Detailed", ai.summary.text contains "Demo AI", ai.label.demo exists, ai.label.basis exists (sample articles are excerpt-only for first card)
func testAskArticleFlow()                       // ai.ask → type question → send → a static text containing "Demo AI" appears
func testDiagramRendersWithTextAlternative()    // ai.diagram → ai.diagram.text exists, ai.diagram.copy exists
func testAIReaderListsSavedItemsAfterRelaunch() // -persistent-store -reset-store: generate summary, terminate, relaunch with -demo-ai -persistent-store, AI Reader tab → aiReader.list has ≥1 cell
func testAIReaderUnavailableWithoutDemo()       // existing test: plain -ui-testing still shows unavailable state
```

- [ ] **Step 2: Run UI tests.** Expected: the new tests fail (elements missing).
- [ ] **Step 3: Implement the views.**
  - Article panel: segmented `SummaryType`; labels row of `GeneratedContentBadge`, `InputBasisLabel`, `DemoAIBadge`, `SampleDataBadge` when applicable, provider name; Regenerate / Cancel; a Report menu item using `AIReport` via `ShareLink`.
  - The diagram uses `DiagramLayout.layers` drawn in a `Canvas` or stacked views with arrows, exposes `DiagramTextDescription` as the VoiceOver label and a visible "Text version" disclosure, and offers Mermaid via `UIPasteboard` copy + `ShareLink`.
  - README: an M4 section covering on-device model requirements, Demo AI, and the explicit "real model output unverified on this machine" statement.
- [ ] **Step 4: Run UI tests and unit tests.** Expected: all pass.
- [ ] **Step 5: Commit** `feat(ai): AI reader UI, settings and UI tests`.
