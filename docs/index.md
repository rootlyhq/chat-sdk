# ChatSDK Ruby

ChatSDK Ruby is a unified SDK for building chat bots that work across Slack, Microsoft Teams, Google Chat, Mattermost, Discord, Telegram, Twilio, Messenger, WhatsApp, X, Linear, and any other platform you write an adapter for. It is a Ruby port of the [chat-sdk.dev](https://chat-sdk.dev) TypeScript library, redesigned with idiomatic Ruby patterns.

## Key Features

- **Normalized events** -- Write your handler once. `on_new_mention`, `on_reaction`, `on_action`, and other callbacks receive the same data structures regardless of which platform the event came from.

- **Cards DSL** -- Build rich messages with a block-based Ruby DSL. Cards automatically render as Block Kit (Slack), Adaptive Cards (Teams), or Card v2 (Google Chat).

- **Streaming** -- Post a placeholder message and stream token-by-token updates with built-in throttling. Works on any adapter that supports message editing.

- **Pluggable adapters** -- Swap platforms (Slack, Teams, Google Chat, Mattermost, Discord, Telegram, Twilio, Messenger, WhatsApp, X, Linear) and state backends (Memory, Redis, PostgreSQL, MySQL) without changing your bot logic. Eleven official adapters ship out of the box, or build your own by subclassing `ChatSDK::Adapter::Base`.

- **Thread subscriptions** -- Subscribe to a thread so future messages are routed to your `on_subscribed_message` handler, letting you build multi-turn conversations.

- **Concurrency safe** -- Built-in per-thread locking and event deduplication prevent race conditions when running across multiple processes.

- **Testable** -- `ChatSDK::Testing::FakeAdapter` records every outbound call in-memory. Simulate mentions, actions, reactions, and slash commands without hitting any external API.

## Quick Links

- [Getting Started](getting-started.md) -- Install, configure, and run your first bot in five minutes.
- [Handling Events](handling-events.md) -- All event handlers with examples.
- [Cards](cards.md) -- Full cards DSL reference.
- [Platform Adapters](platform-adapters.md) -- Capability matrix and escape hatches.
- [Testing](testing.md) -- How to test your bot with FakeAdapter.
