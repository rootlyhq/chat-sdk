# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
