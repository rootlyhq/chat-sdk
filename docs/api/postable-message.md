# API Reference: PostableMessage

`ChatSDK::PostableMessage` wraps content to be sent as a message. It can contain text, a card, or both.

## Constructor

```ruby
msg = ChatSDK::PostableMessage.new(
  text: "Hello",         # String (required if no card)
  card: nil,             # Cards::Node (required if no text)
  attachments: [],       # Array (default: [])
  metadata: {}           # Hash (default: {})
)
```

At least one of `text` or `card` must be provided. Passing neither raises `ArgumentError`.

## Class Method: from

`PostableMessage.from` converts various types into a `PostableMessage`:

```ruby
# String -> PostableMessage with text
PostableMessage.from("Hello")
# => PostableMessage(text: "Hello")

# Cards::Node -> PostableMessage with card and auto-generated fallback text
card = ChatSDK.card(title: "Info") { text "Details" }
PostableMessage.from(card)
# => PostableMessage(card: card, text: "Details")

# PostableMessage -> returns itself
PostableMessage.from(existing_msg)
# => existing_msg
```

This is used internally by `Thread#post` and `Channel#post`, so you rarely need to call it directly.

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `text` | `String` or `nil` | Plain text content |
| `card` | `Cards::Node` or `nil` | Card content |
| `attachments` | `Array` | File attachments |
| `metadata` | `Hash` | Arbitrary metadata |

## Methods

### card?

Returns `true` if the message contains a card.

```ruby
msg = PostableMessage.new(text: "Hello")
msg.card?  # => false

msg = PostableMessage.new(card: ChatSDK.card { text "Hi" })
msg.card?  # => true
```

## Usage

Most of the time you pass strings or cards directly to `thread.post` and the conversion happens automatically. Use `PostableMessage` explicitly when you need both text and a card:

```ruby
msg = ChatSDK::PostableMessage.new(
  text: "Notification fallback text",
  card: ChatSDK.card(title: "Alert") do
    text "Something happened"
    fields do
      field "Severity", "High"
    end
  end
)

thread.post(msg)
```

The `text` is used for push notifications and platforms that cannot render cards. The `card` is rendered as rich content on platforms that support it.
