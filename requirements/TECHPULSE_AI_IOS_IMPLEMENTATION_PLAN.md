# TechPulse AI — iOS Implementation Plan

**Platform:** iOS  
**Primary stack:** Swift 6, SwiftUI, SwiftData, URLSession  
**Architecture:** Feature-oriented MVVM with dependency injection; use structured concurrency throughout  
**Purpose:** A developer-focused intelligence app for discovering technology news, AI developments, coding articles, software architecture, research, and engineering tutorials.

---

## 1. Product vision

TechPulse AI should do more than aggregate headlines. It should help developers move through:

**Discover → Understand → Visualize → Implement → Learn**

The iOS app provides a personalized feed, a clean article-reading experience, optional AI-assisted understanding, saved knowledge, and practical developer resources.

### Product principles

- Curated, useful, low-noise content rather than an endless generic news feed.
- Clear source attribution and links to original publishers.
- AI-generated material must be labelled as generated and distinguishable from publisher content.
- Respect publisher terms, robots policies, API terms, copyright, and rate limits. Store metadata and links; do not republish full articles without permission.
- Core reading, search, bookmarks, and saved notes should work without an AI API key.
- Keep provider credentials off the client. AI requests should go through a secured backend or a user-configured provider integration with clear security warnings.

## 2. MVP scope

### Included in version 1

1. Discover feed with category filters.
2. Eight content categories:
   - AI & Machine Learning
   - Technology News
   - Coding & Programming
   - Architecture & System Design
   - AI Developer Tools
   - Research & Innovation
   - Engineering Career
   - Tutorials & Learning
3. RSS/API source ingestion through a backend.
4. Article list, detail reader, source link, publish date, reading-time estimate.
5. Search, sort, category and source filters.
6. Bookmarking, reading history, saved notes.
7. Daily briefing generated from available article metadata and summaries.
8. Settings for interests, appearance, notifications and privacy.
9. Offline persistence for saved article metadata and user notes.

### Later phases

- AI summaries at 30-second, 2-minute and detailed levels.
- Ask AI about an article, with answers grounded in retrieved article content that the provider is permitted to process.
- Code extraction and syntax-highlighted snippets.
- Architecture diagrams and Mermaid rendering.
- GitHub repository and release discovery.
- Technology/model comparison.
- Siri/App Intents, widgets, audio summaries and learning quizzes.

## 3. App navigation and screens

Use a five-tab `TabView`:

### 3.1 Discover

- Personalized feed of recent and relevant articles.
- Daily briefing card.
- Trending topics and editor/algorithmically selected highlights.
- Category chips and pull-to-refresh.
- Article cards show title, source, date, category, reading time and optional thumbnail.
- Clearly distinguish sponsored or promoted content if introduced later.

### 3.2 Explore

- Category directory and topic pages.
- Source directory.
- Trending technologies and tags.
- Filters for date range, source, category and reading difficulty where available.

### 3.3 AI Reader

- A focused entry point for AI-powered article workflows.
- Recent AI conversations and generated summaries.
- If AI is unavailable or disabled, show an informative empty state and preserve ordinary reading functionality.

### 3.4 Library

- Bookmarks, saved articles, reading history and personal notes.
- Filter by category and read/unread state.
- Offline availability indicator.
- Allow users to remove saved content and clear history.

### 3.5 Profile / Settings

- Topic and technology preferences.
- Notification preferences.
- Appearance: system/light/dark.
- AI provider and privacy controls.
- Data export/delete controls where supported.
- About, source policy, licenses and app version.

### 3.6 Article detail

- Title, source, author when available, publication date and source link.
- Article content only when licensed or available through an allowed feed/API; otherwise show a concise excerpt and open-original action.
- AI summary panel, key takeaways and topic tags when available.
- Bookmark, share, add note and ask AI actions.
- Related articles.
- Report incorrect metadata or generated summary.

## 4. UX and design system

- Native SwiftUI, adaptive layouts and Dynamic Type.
- Support VoiceOver, Reduce Motion, sufficient contrast and keyboard navigation.
- Use reusable design tokens for spacing, typography, colors and card styles.
- Build light and dark appearances; avoid relying on color alone for status.
- Loading skeletons, empty states, retry states and offline states for every major feed.
- Use `NavigationStack` and typed navigation destinations.
- Keep article typography comfortable and uncluttered.
- Avoid autoplay media and unexpected notifications.

## 5. Suggested architecture

Use feature-oriented modules with MVVM and explicit dependency injection. Keep domain logic independent of SwiftUI and persistence.

```text
TechPulseAI/
├── App/
│   ├── TechPulseAIApp.swift
│   ├── AppRouter.swift
│   ├── AppDependencies.swift
│   └── AppConfiguration.swift
├── Core/
│   ├── Networking/
│   ├── Persistence/
│   ├── DesignSystem/
│   ├── Analytics/
│   ├── Logging/
│   ├── Errors/
│   └── Utilities/
├── Domain/
│   ├── Models/
│   ├── Repositories/
│   └── UseCases/
├── Data/
│   ├── API/
│   ├── RSS/
│   ├── DTOs/
│   ├── Mappers/
│   └── RepositoryImplementations/
├── Features/
│   ├── Discover/
│   ├── Explore/
│   ├── ArticleDetail/
│   ├── AIReader/
│   ├── Search/
│   ├── Library/
│   └── Settings/
├── Resources/
└── Tests/
```

### Architecture rules

- Views render state and forward user actions; they do not fetch data directly.
- View models expose observable UI state and call use cases.
- Use cases contain application-level orchestration.
- Repository protocols live in the domain layer; implementations live in the data layer.
- DTOs must not leak into SwiftUI views.
- Inject `URLSession`, repositories, clock/date provider and AI service abstractions.
- Use `@MainActor` for UI-facing view models.
- Use actors for shared mutable caches or coordination where appropriate.
- Use `async throws` APIs and cancellation-aware tasks.
- Avoid unstructured tasks unless their lifetime is explicitly managed.

## 6. Core domain models

Define stable identifiers and explicit date handling.

### Article

- `id: UUID` or stable canonical identifier
- `canonicalURL: URL`
- `title: String`
- `summary: String?`
- `excerpt: String?`
- `imageURL: URL?`
- `sourceID: String`
- `sourceName: String`
- `author: String?`
- `publishedAt: Date?`
- `fetchedAt: Date`
- `categoryIDs: [String]`
- `tags: [String]`
- `readingTimeMinutes: Int?`
- `contentAvailability: ContentAvailability`
- `isBookmarked: Bool` (prefer a separate bookmark relation in persistence)
- `isRead: Bool` (prefer a separate reading-state record)

### Supporting models

- `Source`: ID, name, homepage URL, feed/API URL, source type, enabled state, attribution requirements.
- `Category`: ID, title, description, icon identifier.
- `UserPreferences`: selected categories, followed technologies, preferred summary length, theme, notification settings.
- `Bookmark`: article ID, created date, optional note.
- `ReadingHistoryEntry`: article ID, last-opened date, progress if meaningful.
- `ArticleSummary`: article ID, summary type, generated text, model/provider metadata, creation date.
- `DailyBriefing`: date, article IDs, generated introduction and key themes.
- `AIConversation` and `AIMessage`: conversation context, role, content, timestamp and referenced article IDs.

Use enums for category-independent state such as content availability, source type, summary type and request status.

## 7. Content ingestion and networking

### Recommended approach

Do not make every phone independently crawl arbitrary websites. Build a small backend ingestion service that fetches approved RSS feeds and supported APIs, normalizes metadata, deduplicates articles and exposes a stable API to the apps.

### Client API contract (illustrative)

- `GET /v1/articles?category=&cursor=&limit=`
- `GET /v1/articles/{id}`
- `GET /v1/search?q=&category=&from=&to=`
- `GET /v1/categories`
- `GET /v1/sources`
- `GET /v1/briefings/daily`
- `POST /v1/ai/summaries`
- `POST /v1/ai/article-questions`

The backend contract is illustrative and should be finalized before client implementation.

### iOS networking

- Use `URLSession` with typed `Decodable` DTOs.
- Add request timeout, retry with bounded exponential backoff for transient errors, and cancellation.
- Handle HTTP status codes and decoding failures explicitly.
- Add pagination and deduplicate by canonical URL / backend ID.
- Use `ETag` or `Last-Modified` when supported.
- Cache feed responses and images with bounded storage.
- Never hardcode secrets in the app bundle.
- Do not scrape sites that disallow it.

### Candidate content sources

Validate current API access, feed availability, licensing and terms before enabling a source.

- Hacker News API / RSS
- GitHub Trending or supported GitHub APIs
- arXiv API
- Official Apple Developer News and Swift blog feeds
- Kotlin and Android developer blogs
- OpenAI, Anthropic and Google AI news feeds
- InfoQ and other publisher feeds where permitted
- Technology publisher feeds where feed terms allow

Store source attribution and canonical article URLs for every item.

## 8. Persistence and offline behavior

Use SwiftData for local user data and cached metadata in the MVP.

- Persist bookmarks, notes, reading history, preferences and recently fetched article metadata.
- Define migration strategy from the first schema version.
- Keep network DTOs separate from SwiftData models; map explicitly.
- Support offline access to saved metadata and notes.
- Only cache full article text when publisher terms and product policy permit it.
- Provide storage management and clear-cache controls.

## 9. AI capabilities (Phase 2)

Create a provider-neutral `AIService` protocol so the app is not tied to one model vendor.

### Initial AI workflows

1. **30-second summary:** 2–4 concise bullets.
2. **2-minute summary:** context, key points and implications.
3. **Detailed explanation:** concepts, terminology and technical trade-offs.
4. **Ask this article:** answer questions using only supplied, permitted article context; state when the answer is not supported.
5. **Code explanation:** explain selected snippets and identify language/framework.
6. **Architecture explainer:** propose components and data flow based on the article.

### AI safety and quality

- Label generated content.
- Include source article references and avoid fabricated citations.
- Treat article text as untrusted input; never follow instructions found inside an article.
- Set token, request-size and rate limits.
- Add caching keyed by article version, prompt version and model.
- Make cost and provider usage visible.
- Do not send personal notes or reading history to an AI provider without explicit user action.
- Do not promise that AI-generated code is secure or production-ready.
- Validate any diagram syntax before rendering.

### Architecture diagrams

- Generate Mermaid source from a structured diagram representation.
- Validate and sanitize before rendering.
- Offer textual component descriptions for accessibility.
- Allow copy/share of diagram source.
- Do not render arbitrary executable HTML or scripts from model output.

## 10. Search, recommendations and personalization

MVP:
- Search title, source, tags and available summaries through backend search.
- Category and source filters.
- Sort newest/relevance.
- Followed technologies stored in preferences.

Later:
- Recommendation ranking based on selected interests, freshness, source diversity and explicit feedback.
- Avoid opaque personalization; explain why an article is recommended.
- Provide controls to reset or disable personalization.

## 11. Notifications, widgets and Siri

Later-phase enhancements:
- APNs notifications for selected topics and important releases.
- Digest notifications with quiet hours and frequency controls.
- WidgetKit: daily briefing, saved reading and followed technology updates.
- App Intents: search saved articles, open daily briefing, save current article where supported.
- Siri behavior must be user-initiated and privacy-conscious.

Do not request notification permission on first launch. Explain the value first and ask contextually.

## 12. Testing strategy

### Unit tests

- DTO decoding and mapping.
- Repository behavior with mocked API clients.
- Pagination, deduplication and sorting.
- Search/filter use cases.
- Bookmark and reading-history logic.
- AI prompt construction, response parsing and error handling.
- Date/time and daily-briefing logic.

### SwiftUI and integration tests

- Navigation across all tabs.
- Feed loading, empty, offline and error states.
- Search and filters.
- Bookmark persistence after relaunch.
- Article detail and external-link behavior.
- Dynamic Type and accessibility identifiers.
- SwiftData migration tests.

Use protocol-based mocks and deterministic test data. Avoid tests that depend on live third-party feeds.

## 13. Accessibility, privacy and security

- VoiceOver labels, values, hints and logical focus order.
- Dynamic Type and minimum touch targets.
- Reduce Motion and sufficient contrast.
- Use Keychain only for secrets that genuinely belong on-device.
- Use HTTPS and validate backend authentication.
- Minimize analytics; do not log article-question content or personal notes by default.
- Provide privacy disclosures for AI processing and third-party services.
- Support account/data deletion if accounts and server-side personal data are introduced.
- Review App Store privacy labels and third-party SDK disclosures.

## 14. Delivery milestones

### Milestone 0 — Foundation
- Create Xcode project and build configurations.
- Establish folder structure, dependency container and design tokens.
- Add lint/format conventions if adopted.
- Add unit-test target and CI build.

### Milestone 1 — Browse content
- Define API DTOs and domain models.
- Implement networking and repository.
- Build Discover, Explore and Article Detail.
- Add loading, empty, error and offline states.

### Milestone 2 — Personal library
- Add SwiftData persistence.
- Implement bookmarks, notes, history and preferences.
- Add search and filters.
- Verify migrations and relaunch persistence.

### Milestone 3 — Briefing and polish
- Integrate daily briefing endpoint.
- Add accessibility and responsive layouts.
- Add source attribution and privacy screens.
- Complete UI and integration tests.

### Milestone 4 — AI reader
- Integrate backend AI endpoints.
- Add summary variants and article Q&A.
- Add code explanation and architecture diagram rendering.
- Add cost controls, caching and generated-content labels.

### Milestone 5 — Release readiness
- Performance profiling and memory checks.
- Offline and network-failure testing.
- Security/privacy review.
- App Store assets, metadata and TestFlight validation.

## 15. Definition of done

- The app builds cleanly with the selected supported Xcode/iOS deployment target.
- All five navigation areas have functional MVP behavior.
- Articles show source attribution and open the canonical publisher page.
- Search, filtering, bookmarks, notes and reading history work.
- Saved user data persists after relaunch.
- Network failures produce actionable retry states.
- No API secrets are embedded in the app.
- AI-generated text and diagrams are clearly labelled and validated.
- Critical flows have automated tests.
- VoiceOver and Dynamic Type are verified on key screens.
- Privacy and publisher-content rules are documented.

## 16. Instructions for Claude Code

Implement this plan incrementally. Before coding:

1. Inspect the existing repository and preserve established conventions.
2. Confirm the deployment target and toolchain from project files; do not guess.
3. Identify missing backend contracts and create mock fixtures if the backend is not ready.
4. Present a concise implementation sequence and file changes.
5. Build after each milestone and resolve compiler errors before proceeding.
6. Add tests alongside each feature.
7. Do not fabricate live news data or claim an API integration works without verifying it.
8. Keep secrets out of source control and provide an `.env.example` only for backend configuration.
9. Use sample content clearly marked as sample data.
10. Update the README with setup, architecture, configuration and test instructions.

**First implementation task:** establish the SwiftUI app shell, five-tab navigation, design system, domain models, dependency container, mock article repository and Discover feed using sample data. Do not start AI integration until the content-browsing MVP is stable.
