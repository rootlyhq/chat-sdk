# Usage Overview

This page covers the core concepts of ChatSDK Ruby. Each section links to a detailed page.

## The Chat Instance

`ChatSDK::Chat` is the central object. It holds your adapters, state backend, and event handlers.

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack_adapter },
  state: ChatSDK::State::Memory.new
)
```

Required arguments:

| Argument | Type | Description |
|----------|------|-------------|
| `user_name` | `String` | Display name for the bot (used in logging) |
| `adapters` | `Hash{Symbol => Adapter}` | One or more platform adapters keyed by name |
| `state` | `State::Base` | A state backend (Memory or Redis) |

Optional keyword arguments are documented in [Getting Started](getting-started.md).

## Adapters

An adapter translates between ChatSDK's normalized API and a specific platform. Each adapter is a subclass of `ChatSDK::Adapter::Base` that implements methods like `post_message`, `edit_message`, and `parse_events`.

ChatSDK ships three official adapters:

- `ChatSDK::Slack::Adapter` -- [Slack](adapters/slack.md)
- `ChatSDK::Teams::Adapter` -- [Microsoft Teams](adapters/teams.md)
- `ChatSDK::GChat::Adapter` -- [Google Chat](adapters/gchat.md)

See [Platform Adapters](platform-adapters.md) for the full capability matrix.

## State

The state backend stores thread subscriptions, event deduplication records, per-thread locks, and arbitrary key-value data. Two implementations ship out of the box:

- `ChatSDK::State::Memory` -- In-process, no dependencies. Good for development and single-process deployments.
- `ChatSDK::State::Redis` -- Uses Redis. Required when running multiple processes or dynos.

See [State Adapters](state-adapters.md) for details.

## Event Handlers

Register blocks that run when events arrive:

```ruby
bot.on_new_mention { |thread, message| ... }
bot.on_subscribed_message { |thread, message| ... }
bot.on_direct_message { |thread, message| ... }
bot.on_new_message(/deploy/) { |thread, message| ... }
bot.on_reaction { |event| ... }
bot.on_action("approve_btn") { |event| ... }
bot.on_slash_command("/deploy") { |event| ... }
```

Handlers for mentions, subscribed messages, and direct messages receive `(thread, message)`. Handlers for reactions, actions, and slash commands receive a single `event` object that includes a `thread` method.

See [Handling Events](handling-events.md) for details on each handler.

## Threads and Channels

A `Thread` represents a conversation thread. It is your primary interface for sending messages:

```ruby
bot.on_new_mention do |thread, message|
  thread.post("Hello!")
  thread.post(ChatSDK.card(title: "Status") { text "All systems go" })
  thread.subscribe  # receive future messages in this thread
end
```

A `Channel` represents a chat channel. Use it for posting messages outside of event handlers:

```ruby
channel = bot.channel("C12345", adapter_name: :slack)
channel.post("Scheduled announcement")
```

See [Threads, Messages & Channels](threads-messages-channels.md) for the full API.

## Webhooks

ChatSDK exposes Rack-compatible webhook endpoints. Mount them in your web framework to receive events from each platform:

```ruby
# Single adapter
run bot.webhooks[:slack]

# Multi-adapter router (dispatches by path)
run bot.webhooks.router
```

See [Getting Started](getting-started.md) and [Rails Integration](rails.md).
