# TechPulse AI — iOS

A developer-focused app for discovering technology news, AI developments, coding articles, architecture, research and tutorials.

This repository holds the **content-browsing MVP** (Milestones 0–3 of
[`requirements/TECHPULSE_AI_IOS_IMPLEMENTATION_PLAN.md`](requirements/TECHPULSE_AI_IOS_IMPLEMENTATION_PLAN.md)).
It has five tabs, a personalized Discover feed with a daily briefing, Explore and search with filters, an article reader that follows publisher-content rules, and an offline Library of bookmarks, history and notes. Settings cover interests, appearance, notifications and privacy, plus data export and deletion.

> **Sample data:** no TechPulse backend exists yet, so the app ships with bundled **sample content** (`TechPulseAI/Resources/SampleContent.json`). The content is not real news, every link points to `example.com`, and the UI marks it with a "Sample data" banner and badges.

**Milestone 4 (AI Reader)** adds on-device AI using Apple's Foundation Models framework: summaries at three lengths, Ask-this-article, code explanation and architecture diagrams. See [AI Reader](#ai-reader-milestone-4) below. Core reading works without AI.

## Requirements

| Tool | Version used |
|---|---|
| Xcode | 26.1 (Swift 6.2, Swift 6 language mode, strict concurrency) |
| iOS deployment target | 17.0 (SwiftData + Observation) |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen` |

## Setup

```bash
xcodegen generate          # creates TechPulseAI.xcodeproj from project.yml (not committed)
open TechPulseAI.xcodeproj # run the TechPulseAI scheme on an iOS 17+ simulator
```

### Configuration

| Setting | Where | Effect |
|---|---|---|
| `TECHPULSE_API_BASE_URL` | Scheme environment variable (Edit Scheme → Run → Environment), or the `TECHPULSE_API_BASE_URL` build setting (written into Info.plist) for archived/TestFlight builds | HTTPS base URL of the TechPulse API. **Debug builds also accept `http://localhost` / `http://127.0.0.1`** for a local [TechPulse Server](../TechPulse-Server). If it is unset or invalid, the app uses sample data. |
| `-ui-testing` | Launch argument | Sample data with an in-memory store |
| `-persistent-store` / `-reset-store` | Launch arguments (only with `-ui-testing`) | Use a real on-disk store, or wipe it, for relaunch tests |

**Local server (default for Run):** the `TechPulseAI` scheme's Run action sets `TECHPULSE_API_BASE_URL=http://localhost:8080` (in `project.yml`). Start [TechPulse Server](../TechPulse-Server) first (`docker compose up -d` or `npm run dev`); if it isn't running, Discover shows "Service unavailable". Remove that variable from `project.yml` (or the scheme) to go back to sample data. Tests use their own environment, so they never depend on the local server. ATS allows plain HTTP only to local addresses (`NSAllowsLocalNetworking`).

**No secrets live in the app.** AI provider credentials belong on the backend (see `.env.example`).

## Architecture

The app uses feature-oriented MVVM with explicit dependency injection and structured concurrency.

```
TechPulseAI/
├── App/            entry point, RootView (5-tab TabView + typed NavigationStacks), AppDependencies, AppConfiguration, AppRouter
├── Core/
│   ├── Networking/ APIClient (timeouts, bounded exponential backoff, ETag/304, cancellation, offline mapping)
│   ├── Persistence/ SwiftData VersionedSchema V1 + migration plan, SwiftDataLibraryRepository (actor)
│   ├── DesignSystem/ tokens (spacing, radius, palette, typography), cards, chips, skeletons, state views, badges
│   ├── Errors/     UserFacingError + LoadState
│   └── Utilities/  formatting + accessibility labels
├── Domain/
│   ├── Models/     Article, Category, Source, DailyBriefing, Library models, UserPreferences, AI models
│   ├── Repositories/ ArticleRepository, CatalogRepository, BriefingRepository, LibraryRepository, AIService
│   └── UseCases/   dedupe/canonical URLs, sorting/search matching, reading time, DailyBriefingBuilder
├── Data/
│   ├── DTOs/       backend wire formats (snake_case JSON, ISO-8601)
│   ├── Mappers/    DTO → domain (drops malformed items, http(s)-only URLs)
│   └── RepositoryImplementations/ RemoteContentRepository, SampleContentRepository
├── Features/       Discover, Explore, Search, ArticleDetail, Library, Settings, AIReader
└── Resources/      SampleContent.json
```

Rules followed:
- Views render state and forward actions. They never fetch data directly.
- `@MainActor @Observable` view models call repositories. DTOs never reach views.
- `LibraryStore` is one main-actor facade that keeps bookmark and read state consistent across tabs.
- SwiftData runs on its own actor, and only `Sendable` domain values cross that boundary.
- Loading runs in `.task`/`.task(id:)`, which SwiftUI cancels automatically. Search debounces through task cancellation.

### Publisher content policy

`ArticleBodyPolicy` shows full text only when `content_availability == "full"`. Otherwise it shows the excerpt, or a link-only notice. Every article shows its source name and a **Read at {source}** button that opens the canonical URL in the browser. Full text is cached offline only when it is licensed.

## Backend contract (illustrative, unverified)

The client implements the endpoints below with `APIClient` + `RemoteContentRepository`. They have **not been tested against a live server**; the contract needs to be finalized with the backend.

| Endpoint | Response DTO |
|---|---|
| `GET /v1/articles?category=&cursor=&limit=` | `{ items: [Article], next_cursor }` |
| `GET /v1/articles/{id}` | `Article` |
| `GET /v1/search?q=&category=&source=&from=&to=&difficulty=&sort=` | `{ items, next_cursor }` |
| `GET /v1/categories` | `[{ id, title, description, icon }]` |
| `GET /v1/sources` | `[{ id, name, homepage_url, feed_url, type, enabled, attribution }]` |
| `GET /v1/briefings/daily` | `{ date, article_ids, introduction, key_themes, is_ai_generated }` |

The `Article` fields are `id, canonical_url, title, summary, excerpt, content, image_url, source_id, source_name, author, published_at, category_ids, tags, reading_time_minutes, content_availability (full|excerpt_only|link_only), difficulty`.
`SampleContent.json` uses the same format, so it doubles as a fixture for the contract.

These are not yet defined: a related-articles endpoint (the client falls back to the category feed), a metadata-report endpoint (reports go through the share sheet for now), and the AI endpoints `POST /v1/ai/summaries` and `POST /v1/ai/article-questions`.

## Tests

```bash
xcodegen generate
# Unit tests (Swift Testing): DTOs/mapping, API client retry/ETag/errors, dedupe/sort/search,
# sample repository, briefing, SwiftData persistence + relaunch, view models
xcodebuild test -project TechPulseAI.xcodeproj -scheme TechPulseAI \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TechPulseAITests
# UI tests (XCTest): five-tab navigation, feed → detail, category filter, search,
# AI Reader empty state, bookmark persistence after relaunch, largest Dynamic Type
xcodebuild test -project TechPulseAI.xcodeproj -scheme TechPulseAI \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TechPulseAIUITests
```

No test depends on live third-party feeds. CI (`.github/workflows/ios.yml`) runs the unit tests.

## Accessibility & privacy

- Dynamic Type, including accessibility sizes: cards drop thumbnails and summaries and stack their metadata. VoiceOver gets one combined label per card plus a Bookmark action. Selected chips expose the selected trait and a checkmark, so state never relies on colour alone. Touch targets are at least 44 pt, and nothing animates.
- All user data stays on the device. Profile → Data & Storage exports it as JSON, clears the cache or history, or deletes everything.
- The app collects no analytics. Notification permission is requested only when a notification toggle is switched on.

## AI Reader (Milestone 4)

Design: [`docs/superpowers/specs/2026-11-14-milestone-4-ai-reader-design.md`](docs/superpowers/specs/2026-11-14-milestone-4-ai-reader-design.md)

Plan: [`docs/superpowers/plans/2026-11-14-milestone-4-ai-reader.md`](docs/superpowers/plans/2026-11-14-milestone-4-ai-reader.md)

- **Provider:** Apple's on-device model (`FoundationModelsAIService`). It needs **iOS 26 on an Apple Intelligence device with Apple Intelligence turned on**. There's no server and no API keys, and article text never leaves the phone. On other devices or iOS versions the app explains why AI isn't available, and everything else still works. FoundationModels is weak-linked, so the app still runs on iOS 17–18.
- **Features:**
  - Summaries: 30-second, 2-minute or detailed.
  - Ask this article: multi-turn Q&A that says when the article doesn't cover a question.
  - Code explanation: works on pasted code and ends with a fixed caveat.
  - Architecture diagrams: structured model output, validated, drawn natively in SwiftUI, with a VoiceOver text version and copy/share of the Mermaid source. There's no web view.
- **Safety and labels:**
  - Every output carries **AI-generated**, the model name and, when relevant, **Based on the excerpt only** / **Based on title and summary only** and **Sample data**.
  - The model only sees what `ArticleBodyPolicy` allows.
  - Article text is fenced as untrusted data.
  - Notes and history are never included.
  - Requests are throttled: one at a time per article, plus a per-minute limit.
- **Storage:** summaries, diagrams, code explanations and conversations are saved on the device (SwiftData schema V2, migrated from V1). They're listed in the AI Reader tab, included in Export My Data, and removed by Delete All Data or Clear AI History.
- **Demo AI (Debug builds only):** a stand-in that returns obviously fake canned output marked **Demo AI — fake output**. Turn it on in Profile → AI & Privacy, or with the launch arguments `-ui-testing -demo-ai`, which UI tests use. It isn't compiled into Release builds.

> ⚠️ **Verification status:** the real on-device model's output has **not** been run or checked. This project was built on an Intel Mac, whose simulator can't run Apple's model. All automated tests use Demo AI or test doubles; the real service is compile-verified only. Run it on an iOS 26 Apple Intelligence iPhone before relying on its output.

## Roadmap

- **M4 follow-ups:** verify and tune prompts on a real Apple Intelligence device, stream responses, send selected reader text to the code explainer, and optionally add a backend `AIService`.
- **M5:** performance profiling, security review, App Store assets.
- **Later:** APNs digests, WidgetKit, App Intents, recommendation feedback.
