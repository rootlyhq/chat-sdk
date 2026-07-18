# API Reference: Chat

`ChatSDK::Chat` is the central object that holds adapters, state, event handlers, and webhook endpoints.

## Constructor

```ruby
ChatSDK::Chat.new(
  user_name:,
  adapters:,
  state:,
  **options
)
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `user_name` | `String` | Yes | -- | Bot display name |
| `adapters` | `Hash{Symbol => Adapter::Base}` | Yes | -- | Platform adapters keyed by name |
| `state` | `State::Base` | Yes | -- | State backend |
| `dedupe_ttl` | `Integer` | No | `600` | Deduplication TTL in seconds |
| `streaming_update_interval` | `Float` | No | `0.5` | Min seconds between stream edits |
| `on_lock_conflict` | `Symbol` or `Proc` | No | `:drop` | Lock conflict policy |
| `log_level` | `Symbol` | No | `:info` | Log level |

## Instance Methods

### Event Registration

```ruby
chat.on_new_mention { |thread, message| ... }
```

Register a handler for @-mentions.

```ruby
chat.on_new_message(pattern) { |thread, message| ... }
```

Register a handler for @-mentions matching a `Regexp` pattern.

```ruby
chat.on_subscribed_message { |thread, message| ... }
```

Register a handler for messages in subscribed threads.

```ruby
chat.on_direct_message { |thread, message| ... }
```

Register a handler for direct messages.

```ruby
chat.on_reaction(emojis = nil) { |event| ... }
```

Register a handler for reactions. Pass an `Array` of emoji names to filter.

```ruby
chat.on_action(action_id) { |event| ... }
```

Register a handler for card actions (buttons, selects) matching `action_id`.

```ruby
chat.on_slash_command(command) { |event| ... }
```

Register a handler for slash commands matching `command`.

### Adapter Access

```ruby
chat.adapter(name) # => Adapter::Base
```

Returns the adapter registered under `name`. Raises `ConfigurationError` if not found.

### Channel / DM Access

```ruby
chat.channel(id, adapter_name: nil) # => Channel
```

Returns a `Channel` for the given ID. If `adapter_name` is omitted, uses the first registered adapter.

```ruby
chat.open_dm(user_id, adapter_name: nil) # => Channel
```

Opens a DM conversation with the user and returns a `Channel`.

### Webhooks

```ruby
chat.webhooks[:slack]     # => Webhook::Endpoint (Rack app)
chat.webhooks.router      # => Webhook::Router (Rack app)
```

### Dispatch

```ruby
chat.dispatch(event, adapter_name:)
```

Dispatches an event through the handler pipeline. Called internally by webhook endpoints.

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `config` | `Config` | Configuration object |
| `state` | `State::Base` | State backend |
