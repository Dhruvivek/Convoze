# Flutter client core architecture

**Status:** accepted — amended by [ADR 0009](0009-local-first-client-data-layer.md) (`lib/core/db/` + `lib/core/sync/` hold the Local replica and sync engine)

## Context

The Flutter client needs a foundational architecture before any feature work (realtime transport, offline caching, chat UI) can start (#3, part of the build-ready spec map in #1). No strong preference was settled going in, and the app has real-time requirements (Socket.IO-driven messages/presence/typing, per `docs/features.md`), phone+OTP-gated screens, and media uploads.

## Decisions

- **State management: Riverpod**, with code generation (`riverpod_generator` + `@riverpod`, `build_runner`). `StreamProvider`/`AsyncNotifier` map directly onto socket event streams, autodispose keeps chat-screen providers from leaking state, and codegen is Riverpod's current documented default. Rejected Bloc (more event/state ceremony than a solo build needs) and Provider (superseded by Riverpod).
- **Navigation: GoRouter**, with a single top-level `redirect` callback wired to a Riverpod auth-state provider via `refreshListenable` — one source of truth for gating screens behind the phone+OTP auth flow, instead of per-route guards or hand-rolled `Navigator 2.0` (`RouterDelegate`/`RouteInformationParser`).
- **Project structure: feature-first** (`lib/features/{auth,conversations,chat,presence,profile}/...`). Layer-first (`lib/data`, `lib/domain`, `lib/presentation`) was rejected because it collapses group chat, media, reactions, and search into one `presentation/` folder as the app grows.
  - Within each feature, a **`data` + `presentation` split only** — no separate use-case/domain layer. The repository pattern still lives in `data` (so REST vs. socket source is swappable/testable), but an explicit use-case-class layer is ceremony without payoff at this scale; the Riverpod notifier holds orchestration logic directly.
  - **`lib/core/`** holds cross-feature concerns: the shared Dio client provider, GoRouter config, app theme, common widgets, and DTOs used by more than one feature (e.g. `User`). This is also where the socket-connection entry point will plug in once the realtime-transport ticket lands.
- **HTTP client: Dio.** Chosen over the bare `http` package for interceptors (auth token attach/refresh), native multipart support (media uploads, feature #9), and cancellation tokens (search-as-you-type, feature #13).
- **Environment/base-URL config: `--dart-define` + `String.fromEnvironment`**, wrapped in a thin `AppConfig`. Rejected `flutter_dotenv` (extra dependency not needed) and build flavors (overkill unless distinct app icons/bundle IDs per environment are needed later).

## Consequences

- Adding a feature means adding a `lib/features/<name>/{data,presentation}` folder, not touching a shared layer folder.
- Any code needing dependency injection goes through Riverpod providers — no `get_it` or other DI container introduced alongside it.
- Auth-gating for new screens is automatic as long as they're registered under the `GoRouter` config that the top-level `redirect` covers; no per-screen auth checks needed.
