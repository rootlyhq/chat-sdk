# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-20

### Added

- **Slack multi-workspace OAuth** with per-team token resolution — a single bot instance can serve multiple Slack workspaces

### Fixed

- Clear stale `Thread.current` client references and cache per-team Slack clients correctly

## [0.9.0] - 2026-07-20

### Added

- **X OAuth2 token refresh** with automatic rotation and state persistence

### Changed

- Removed redundant `ensure_valid_token` call in WhatsApp `upload_media`

## [0.8.1] - 2026-07-20

### Changed

- Extracted shared format converter helpers into `ChatSDK::Format::Converter::Base` base class

## [0.8.0] - 2026-07-20

### Added

- **Format converters** for bidirectional markup conversion across all 11 platform adapters (e.g. Slack mrkdwn to/from Teams Adaptive Card markdown)

## [0.7.0] - 2026-07-20

### Added

- **Infrastructure tier** — persistent connection modes for 4 platforms:
  - Slack Socket Mode (WebSocket-based event delivery)
  - Discord Gateway (WebSocket bot gateway)
  - Teams Graph API client (`ChatSDK::Teams::GraphClient`)
  - Google Chat Pub/Sub subscription support

## [0.6.0] - 2026-07-20

### Added

- **Slack Assistants API** methods and home tab support (`update_home_tab`)
- **Slack scheduled messages** (`schedule_message`, `list_scheduled_messages`, `delete_scheduled_message`)
- **Telegram MarkdownV2** formatting support
- **Telegram long-polling** mode as an alternative to webhooks
- **WhatsApp template builder** for structured template messages
- `get_user(user_id)` method on all adapters that support user lookup

### Changed

- Tier 1 capability parity — added templates, media upload, and history support across adapters that were missing them
- Extracted `MediaTypes` module; cleaned up dead code in Teams, X, and Twilio adapters

## [0.5.0] - 2026-07-19

### Added

- Closed capability gaps across 8 adapters — added missing edit, delete, reactions, file uploads, history, and streaming where each platform's API supports it
- Linear adapter now supports edit, delete, reactions, history, and streaming

### Changed

- Updated capability matrices in all documentation to reflect new adapter support levels

## [0.4.0] - 2026-07-19

### Added

- **X (Twitter) adapter** (`chat_sdk-x`) — X API v2 with CRC challenge validation, HMAC-SHA256 webhook verification, tweets, DMs, and likes
- **Linear adapter** (`chat_sdk-linear`) — Linear GraphQL API with HMAC-SHA256 webhook verification and issue comment threading

### Fixed

- Linear adapter: added missing `:threads` capability declaration
- Linear adapter: removed falsely declared `:reactions` capability (added back correctly in v0.5.0)

## [0.3.0] - 2026-07-19

### Added

- **Instrumentation** — zero-dependency pub/sub system (`ChatSDK::Instrumentation`) with 6 events: `dispatch`, `dedupe`, `lock`, `handler`, `api_request`, `rate_limited`
- **Shared API client base** (`ChatSDK::ApiClient::Base`) with automatic 429 retry, exponential backoff, and instrumentation hooks — adopted by Mattermost, Discord, Telegram, Messenger, WhatsApp
- **Building State Adapters** guide for creating custom state backends
- Docs build CI job to catch broken MDX/imports
- RubyDoc.info badge and docs site nav link

### Changed

- Extracted `ChatSDK::Adapter::MetaVerification` shared concern (Messenger + WhatsApp)
- Extracted `ChatSDK::Cards::TextHelpers` shared mixin (collect_text_parts, truncate)
- Extracted `Adapter::Base#read_json_body` helper used by 7 adapters
- Updated all docs: platform tables expanded to 9 adapters, state backends to 4
- Fixed AI agent-tools docs: removed nonexistent `chat:` param, corrected `ToolExecutor` usage

### Fixed

- Twilio: removed false `:file_uploads` capability declaration (upload_file always raised)
- Telegram: restored missing instrumentation events after API client migration

## [0.2.1] - 2025-07-18

Initial public release of ChatSDK Ruby.

### Added

- Core SDK (`chat_sdk`) with unified Chat, Thread, Message, Channel, and Author abstractions
- **Platform adapters** (9 platforms):
  - `chat_sdk-slack` — Slack (Block Kit cards, modals, ephemeral messages)
  - `chat_sdk-teams` — Microsoft Teams (Adaptive Cards, Bot Framework)
  - `chat_sdk-gchat` — Google Chat (Google Cards v2)
  - `chat_sdk-discord` — Discord (Ed25519 signature verification, embeds)
  - `chat_sdk-mattermost` — Mattermost (webhook-based)
  - `chat_sdk-telegram` — Telegram (inline keyboards, webhook verification)
  - `chat_sdk-twilio` — Twilio SMS/MMS (HMAC-SHA1 signature verification)
  - `chat_sdk-messenger` — Facebook Messenger (HMAC-SHA256 verification, templates)
  - `chat_sdk-whatsapp` — WhatsApp (Cloud API, interactive messages)
- **State backends** (4 backends):
  - In-memory state (built into core, no dependencies)
  - `chat_sdk-state-redis` — Redis state adapter with TTL support
  - `chat_sdk-state-pg` — PostgreSQL state adapter with auto-migration and JSONB storage
  - `chat_sdk-state-mysql` — MySQL state adapter with auto-migration and JSON storage
- **Cards DSL** for building rich, cross-platform card messages
- **Modals** support for platforms that support them (Slack, Teams)
- **AI integration**:
  - `ToolBuilder` for defining AI-callable tools from chat handlers
  - `ToolExecutor` for executing tool calls
  - `StreamHandler` for streaming AI responses to chat
  - `to_ai_messages` converter for transforming chat history into LLM-ready format
- **Streaming** support for real-time message updates
- **Event system** with typed event dispatching and handler registration
- **Webhook verification** with per-platform signature validation
- **Rails integration** via Rack middleware
- **Testing helpers** (`ChatSDK::Testing`) for unit testing bots without live APIs
- **Examples**: Rails chat demo (ActionCable + Turbo + Stimulus) and Rack bot
- **Documentation site** at [chat-sdk.ai](https://chat-sdk.ai) built with Fumadocs/Next.js
- CI pipeline with RuboCop linting and multi-Ruby (3.3, 3.4, 4.0) test matrix
- OIDC-based gem publishing workflow for all adapters
