# API Reference: Thread

`ChatSDK::Thread` represents a conversation thread. It is the primary interface for sending messages, managing subscriptions, and interacting with a thread.

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `String` | Thread identifier |
| `channel_id` | `String` | Channel this thread belongs to |
| `adapter` | `Adapter::Base` | The platform adapter |
| `chat` | `Chat` | The parent Chat instance |

## Methods

### post(content)

Posts a message to the thread. Accepts a `String`, `Cards::Node`, or `PostableMessage`.

```ruby
thread.post("Hello!")
thread.post(ChatSDK.card(title: "Info") { text "Details" })
```

Returns a `ChatSDK::Message` with the posted message's ID.

### post_ephemeral(content, user_id:)

Posts a message visible only to the specified user.

```ruby
thread.post_ephemeral("Only you see this", user_id: "U123")
```

Raises `NotSupportedError` if the adapter does not support ephemeral messages.

### post_stream(placeholder: nil, &block)

Posts a streaming message that is updated incrementally.

```ruby
thread.post_stream(placeholder: "Loading...") do |stream|
  stream << "chunk1"
  stream << "chunk2"
end
```

### edit(message_id, content)

Edits an existing message.

```ruby
result = thread.post("Draft")
thread.edit(result.id, "Final version")
```

### delete(message_id)

Deletes a message.

```ruby
result = thread.post("Temporary")
thread.delete(result.id)
```

### react(message_id, emoji)

Adds an emoji reaction to a message.

```ruby
thread.react(message.id, "thumbsup")
```

### unreact(message_id, emoji)

Removes an emoji reaction from a message.

```ruby
thread.unreact(message.id, "thumbsup")
```

### upload(io:, filename:, comment: nil)

Uploads a file to the thread.

```ruby
File.open("report.pdf", "rb") do |f|
  thread.upload(io: f, filename: "report.pdf", comment: "Monthly report")
end
```

### messages(cursor: nil, limit: 50)

Fetches conversation history. Returns `[Array<Message>, cursor]`.

```ruby
messages, next_cursor = thread.messages(limit: 20)
```

### subscribe

Subscribes the bot to future messages in this thread.

```ruby
thread.subscribe
```

### unsubscribe

Unsubscribes from the thread.

```ruby
thread.unsubscribe
```

### subscribed?

Returns `true` if currently subscribed.

```ruby
thread.subscribed?  # => true/false
```

### state

Returns per-thread state data, or `nil` if none is stored.

```ruby
data = thread.state  # => {"count" => 3} or nil
```

### set_state(value)

Stores per-thread state data with a 30-day TTL.

```ruby
thread.set_state({"count" => 3})
```

### mention_user(user_id)

Returns a formatted user mention string for the current platform.

```ruby
thread.mention_user("U123")  # => "<@U123>" (Slack)
```

### open_modal(trigger_id:, modal:)

Opens a modal dialog. Requires a `trigger_id` from an action or slash command.

```ruby
modal = ChatSDK::Modals::Builder.new(title: "Form") do
  text_input id: "name", label: "Name"
end.build

thread.open_modal(trigger_id: event.trigger_id, modal: modal)
```

## Equality

Two threads are equal if they have the same `id` and `channel_id`.
