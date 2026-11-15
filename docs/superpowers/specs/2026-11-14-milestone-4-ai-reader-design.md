# Milestone 4 — AI Reader (on-device) — Design

**Date:** 2026-11-14
**Status:** Approved by owner 2026-11-14 (builder-check answers folded in as designer calls, §10)
**Builds on:** `requirements/TECHPULSE_AI_IOS_IMPLEMENTATION_PLAN.md` §3.3, §3.6, §9, §14 (Milestone 4), and the shipped MVP on `main`.

## 1. Intent

TechPulse helps developers move from **Discover → Understand → Visualize → Implement → Learn**. The MVP covers Discover. Milestone 4 adds **Understand** and **Visualize** through AI-assisted reading: summaries, questions about an article, code explanations and architecture diagrams.

The owner chose **Apple's on-device model** (the Foundation Models framework) as the only AI provider for this milestone. The reasons:

- No backend exists.
- Provider credentials must never ship in the app (plan §1).
- Article text and user questions never leave the phone.

## 2. Goals

1. **Summaries are the priority feature** and get the most polish. There are three lengths:
   - **30-second:** 2–4 concise bullets.
   - **2-minute:** context, key points and implications.
   - **Detailed:** concepts, terminology and technical trade-offs.
2. **Ask this article:** a multi-turn Q&A grounded only in the permitted article text. It says plainly when the article does not support an answer.
3. **Code explanation:** explains a code snippet, identifies the language/framework, and appends a fixed caveat that it is not a security review or a guarantee of correctness.
4. **Architecture diagrams:** proposes components and data flow based on the article. It is drawn natively and comes with a text equivalent and copy/share of the Mermaid source.
5. **Saved on the phone:** generated summaries and Q&A conversations persist across launches. The AI Reader tab lists recent ones.
6. **A stand-in model** (a fake, clearly marked provider) lets every AI screen be exercised in the simulator and in tests.

## 3. Non-goals

- Backend or cloud AI providers. The existing provider-neutral `AIService` protocol stays, so one can be added later, but none is built now.
- Audio summaries, quizzes, widgets, Siri/App Intents, comparisons (later phases per plan §2).
- Extracting code from article bodies. Most content is excerpt-only, so code explanation works on code the user pastes or selects.
- Rendering Mermaid via a web view or JavaScript library.
- Sending notes, reading history or preferences to the model.

## 4. Anti-goals (failure even if it "works")

- Unlabelled generated text, or generated text that could be mistaken for publisher content.
- The model processing more article text than the publisher permits. For example, it must never be fed `content` when availability isn't `full`.
- Following instructions embedded in article text (prompt injection).
- Fabricated citations or sources.
- Stand-in output that could ever appear as real output: in a release build, or without a visible "Demo AI — fake output" marker.
- Any regression of the non-AI experience on devices that can't run the model.
- Claiming the real model's output quality has been verified when it has not (see §8).

## 5. Constraints

- **Toolchain:** Xcode 26.x, Swift 6 strict concurrency, iOS deployment target stays **17.0**. All Foundation Models code is behind `@available(iOS 26, *)` and `#if canImport(FoundationModels)`.
- **Device support:** the real model requires iOS 26 on an Apple Intelligence device with Apple Intelligence enabled. The app must check the model's availability and distinguish these states in its messaging:
  - device not eligible;
  - Apple Intelligence not enabled;
  - model not ready yet / downloading;
  - available.

  On iOS < 26, the service is unavailable.
- **Development machine:** Intel Mac. The simulator **cannot** run Apple's model, so all automated tests use the stand-in or test doubles. No test may depend on the real model.
- **Context window:** the on-device model's context is small, a few thousand tokens. Article input must be budgeted and truncated deterministically. For multi-turn Q&A, the conversation must stay within budget: trim or restart the session with a fresh transcript when needed.
- **Content permission (publisher rules):** the model input for an article is built only from what `ArticleBodyPolicy` permits:
  - `full`: full text (truncated to budget), plus title/source/summary.
  - `excerptOnly`: excerpt, plus title/source/summary.
  - `linkOnly`: title/source/summary only.

  Outputs record the **input basis** (`fullText` / `excerptOnly` / `metadataOnly`).
- **Untrusted input:** article text is passed as clearly delimited data. The system instructions tell the model never to follow instructions found inside it. User questions are also capped in length.
- **Limits (cost controls for an on-device model):**
  - one generation at a time per article;
  - cancellable;
  - a per-request input character cap;
  - a simple rate limit (e.g. no more than N requests per minute). The exact numbers are the builder's call.

  The plan's "make cost and provider usage visible" maps to showing which model produced each output and a running count of local generations in Settings.
- **Privacy:** only article-derived text and the user's own question or snippet are ever in a prompt.

## 6. Decided behaviour

### 6.1 Turning AI on

- AI stays **off by default**. The existing Profile → "AI features" toggle turns it on.
- The toggle is enabled only when the active AI service is available. Otherwise its footer explains *why*, in the availability states from §5.
- The "Preferred summary length" setting becomes live and selects the default summary length.

### 6.2 Summaries (priority)

- The article page's AI panel shows a **30-second / 2-minute / Detailed** segmented control, defaulting to the preferred length.
- **All three lengths are always offered**, including for excerpt-only and link-only articles. When the input was not full text, the result shows a visible **"Based on the excerpt only"** label, or "Based on title and summary only" for link-only articles.
- Every result shows the **"AI-generated"** badge and the model/provider name.
- Results stream in, or show progress if streaming isn't practical. They can be cancelled and regenerated.
- Results are **cached on the device**, keyed by article ID + summary length + input-basis fingerprint + prompt version + model ID. Reopening the article shows the cached result instantly. "Regenerate" replaces it.
- The summary must not invent facts beyond the input. Where the input is thin, it says so rather than padding.

### 6.3 Ask this article

- An "Ask AI" action on the article page opens a chat sheet scoped to that article.
- Answers are grounded only in the permitted article input. When the input does not support an answer, the model says so (e.g. "The article doesn't cover this").
- Each answer shows the AI-generated badge and the input-basis label when not full text.
- Conversations are saved on the device and can be resumed from the article page or the AI Reader tab.

### 6.4 Code explanation

- Entry points:
  - "Explain code" from the article page, where the user pastes a snippet; the explanation is linked to that article;
  - the AI Reader tab, as a standalone tool with no article attached.

  Sending selected article text directly is **deferred**: it would mean replacing the SwiftUI reader body with a UIKit text view, which risks regressing the non-AI reading path. Users can copy text and paste it. Pasted code is user-supplied input, so it carries no input-basis label.
- Output:
  - the detected language/framework;
  - a plain-language explanation;
  - notable risks or gotchas;
  - a fixed caveat: "AI explanations can be wrong and are not a security review."

### 6.5 Architecture diagrams

- An "Architecture diagram" action on the article page.
- The model returns a **structured diagram**, not free-form markup:
  - a title;
  - components (id, name, kind, short description);
  - connections (from, to, label).
- The app **validates** it before drawing anything:
  - unique IDs;
  - edges reference existing nodes;
  - bounded counts (e.g. ≤ 12 components, ≤ 20 connections);
  - label lengths capped;
  - only safe characters.

  Invalid output is rejected with a retry option and is never partially rendered.
- The app **draws it natively in SwiftUI** (boxes and arrows, simple layered layout). No web view, no JavaScript.
- An **accessible text version** lists components and connections and is exposed to VoiceOver.
- The app **generates Mermaid source** from the validated structure and offers copy and share. Labels are escaped so the source is always syntactically valid.
- Labelled AI-generated, plus the input-basis label.

### 6.6 AI Reader tab

- When AI is available and enabled, the tab shows **recent AI activity**, newest first, covering all four kinds: summaries, conversations, code explanations and diagrams. Each is linked to its article where it has one. The tab also has an entry to the standalone code explainer.
- When AI is unavailable or disabled, the current empty state stays, updated to say *why* (availability state) and how to enable it.
- Rows can be deleted. A "Clear AI history" control removes all of it.

### 6.7 Persistence

- All four kinds are stored locally in SwiftData in V2: summaries, conversations/messages, code explanations and diagrams. Diagrams are cached per article like summaries: reopening shows the last diagram, and "Regenerate" replaces it.
- This is the **first real schema migration**: add a `TechPulseSchemaV2` with the new models and a migration stage from V1. V1 data (bookmarks, notes, history, preferences, cached articles) must survive the migration, and a test must prove it.
- AI data is included in **Export My Data** and removed by **Delete All Data**.
- Clearing the article cache does **not** delete AI history.

### 6.8 Stand-in model ("Demo AI")

- A fake `AIService` that returns deterministic, obviously-fake canned output for every feature. It includes a valid sample diagram.
- It is **available only in Debug builds**. It is switched on by a Debug-only toggle in Profile ("Demo AI — fake output") or by a launch argument for UI tests.
- Everything it produces carries a prominent **"Demo AI — fake output"** marker in addition to the AI-generated badge.
- When it is on, it replaces the real service. When it is off, the real service is used if available.

### 6.9 Sample-data mode

- The real on-device service is wired **regardless of data source**. Sample mode is the mode that ships today, so wiring the model only for the remote data source would make it unreachable.
- AI output about a sample article shows both labels: **"Sample data"** and **"AI-generated"**.

### 6.10 Reporting a problem with AI output

- Plan §3.6 asks for a way to report a wrong generated summary. Each AI result (summary, answer, code explanation, diagram) gets a "Report a problem" action.
- It reuses the existing share-sheet report. The payload carries the article ID, output kind, output text, model, prompt version and input basis. It never includes notes or history.

## 7. Architecture notes (decided)

- Keep the existing provider-neutral `AIService` protocol, extending or reshaping it as needed for the four features, streaming, availability states and diagram output. Implementations:
  1. `FoundationModelsAIService`: real, iOS 26+.
  2. `DemoAIService`: stand-in, Debug only.
  3. `UnavailableAIService`: existing.
- Prompt construction and diagram validation/Mermaid generation are pure, testable units with no framework dependency. The input-basis logic, truncation, delimiting, prompt version and per-feature instructions are unit-tested.
- Use Foundation Models' guided generation (structured output types) for diagrams and, where helpful, for summaries.
- View models follow the existing pattern: `@MainActor @Observable`, explicit dependency injection via `AppDependencies`, and `.task`-scoped work with cancellation.

## 8. Verification

- **Unit tests (Swift Testing)** cover:
  - prompt building per feature and basis, truncation, injection delimiting;
  - caching keys and invalidation;
  - availability mapping;
  - diagram validation (valid, duplicate IDs, dangling edges, over-limit, unsafe text);
  - Mermaid generation and escaping;
  - V1 → V2 migration preserving data;
  - export/delete including AI data;
  - rate limiting and cancellation;
  - view-model states using the stand-in and failure doubles.
- **UI tests** run with the Demo AI launch argument:
  - summary length switching with labels visible;
  - Ask flow;
  - diagram renders with its text alternative;
  - AI Reader lists saved items after relaunch.
- **Not verifiable here:** the real model's output quality and behaviour. That needs a physical iOS 26 Apple Intelligence iPhone. The README and the final report must say so explicitly. The real-service code must compile and be wired, but its output is untested.

## 9. Left to the builder

- Exact prompts and wording, token/character budgets, rate-limit numbers.
- The diagram layout algorithm and visual styling (within the design tokens).
- Whether summaries use streaming or one-shot generation with progress.
- Exact SwiftData model shapes for V2, and how conversations are trimmed to fit context.
- UI placement details within the article page, sheets vs. pushes.
- Wording of availability messages.

## 10. Calls made by the designer (not explicitly decided by the owner)

- Code explanation works on pasted or selected code, not code automatically extracted from articles.
- Diagrams: structured output → native drawing + text version + Mermaid copy/share. No web view.
- AI history is included in export, removed by Delete All, and has its own "Clear AI history".
- Demo AI is Debug-only, toggled in Profile or by launch argument.
- "Cost visibility" for an on-device model = show the model name per output + a local generation count in Settings.
- (Builder check) All four AI output kinds are persisted, listed, exported and cleared. Diagrams are cached per article.
- (Builder check) Selecting text in the reader to send to the explainer is deferred; paste only, to avoid regressing the reader.
- (Builder check) The real model is wired in sample-data mode too, with "Sample data" and "AI-generated" labels combined.
- (Builder check) "Report a problem" is added to every AI output via the existing share-sheet report.
