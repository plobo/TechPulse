# TechPulse AI — iOS

A developer-focused app for discovering technology news, AI developments, coding articles, architecture, research and tutorials.

This repository holds the **content-browsing MVP** (Milestones 0–3 of
[`requirements/TECHPULSE_AI_IOS_IMPLEMENTATION_PLAN.md`](requirements/TECHPULSE_AI_IOS_IMPLEMENTATION_PLAN.md)).
It has five tabs, a personalized Discover feed with a daily briefing, Explore and search with filters, an article reader that follows publisher-content rules, and an offline Library of bookmarks, history and notes. Settings cover interests, appearance, notifications and privacy, plus data export and deletion.

> **Sample data:** no TechPulse backend exists yet, so the app ships with bundled **sample content** (`TechPulseAI/Resources/SampleContent.json`). The content is not real news, every link points to `example.com`, and the UI marks it with a "Sample data" banner and badges.

AI features (Milestone 4) are **not implemented**. Only the provider-neutral `AIService` protocol, an `UnavailableAIService`, and AI Reader empty states exist. Core reading works without AI.

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
| `TECHPULSE_API_BASE_URL` | Scheme environment variable (Edit Scheme → Run → Environment) | HTTPS base URL of the TechPulse API. If it is unset or not HTTPS, the app uses sample data. |
| `-ui-testing` | Launch argument | Sample data with an in-memory store |
| `-persistent-store` / `-reset-store` | Launch arguments (only with `-ui-testing`) | Use a real on-disk store, or wipe it, for relaunch tests |

**Release builds:** the Info.plist is generated (`GENERATE_INFOPLIST_FILE`), so scheme environment variables don't apply to archived/TestFlight builds, and those builds use sample data. Before shipping against a backend, add an `INFOPLIST_FILE` with a `TECHPULSE_API_BASE_URL` key to `project.yml`. `AppConfiguration` already reads that key.

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

## Roadmap

- **M4 AI Reader:** a backend `AIService`, three summary lengths, article Q&A grounded in permitted content, code explanation, and validated Mermaid diagrams, all with generated-content labels, caching and cost controls.
- **M5:** performance profiling, security review, App Store assets.
- **Later:** APNs digests, WidgetKit, App Intents, recommendation feedback.
