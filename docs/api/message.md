# API Reference: Message

`ChatSDK::Message` is a normalized representation of a chat message, whether incoming or outgoing.

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `String` | Platform-specific message ID |
| `text` | `String` | Message text content |
| `author` | `Author` | Who sent the message |
| `thread_id` | `String` | Thread identifier |
| `channel_id` | `String` | Channel identifier |
| `platform` | `Symbol` | Platform name (`:slack`, `:teams`, `:gchat`, `:test`) |
| `attachments` | `Array` | File attachments (default: `[]`) |
| `raw` | `Object` | Raw platform payload (default: `nil`) |
| `timestamp` | `String` | Platform-specific timestamp (default: `nil`) |

## Constructor

```ruby
message = ChatSDK::Message.new(
  id: "msg_123",
  text: "Hello",
  author: author,
  thread_id: "T123",
  channel_id: "C123",
  platform: :slack,
  attachments: [],
  raw: nil,
  timestamp: nil
)
```

## Equality

Two messages are equal if they have the same `id` and `platform`.

```ruby
msg1 == msg2  # true if same id and platform
```

## Author

`ChatSDK::Author` represents the sender of a message.

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `String` | User ID |
| `name` | `String` | Display name |
| `platform` | `Symbol` | Platform name |
| `bot?` | `Boolean` | Whether the author is a bot |
| `raw` | `Object` | Raw platform data (default: `nil`) |

```ruby
author = ChatSDK::Author.new(
  id: "U12345",
  name: "Jane",
  platform: :slack,
  bot: false
)

author.bot?  # => false
```

Two authors are equal if they have the same `id` and `platform`.

## Accessing Message Data in Handlers

```ruby
bot.on_new_mention do |thread, message|
  puts message.id          # "1234567890.123456"
  puts message.text        # "hello bot"
  puts message.author.name # "jane"
  puts message.author.id   # "U12345"
  puts message.author.bot? # false
  puts message.channel_id  # "C12345"
  puts message.thread_id   # "1234567890.123456"
  puts message.platform    # :slack
  puts message.raw         # {"type"=>"message", ...}
end
```
