# Conversation History

ChatSDK lets you fetch previous messages from a thread or channel. This is useful for building context-aware bots that need to read back conversation history.

## Fetching Messages

Use `thread.messages` to retrieve messages from a thread:

```ruby
bot.on_new_mention do |thread, message|
  messages, cursor = thread.messages(limit: 10)

  messages.each do |msg|
    puts "#{msg.author.name}: #{msg.text}"
  end
end
```

`thread.messages` returns a two-element array:

1. An `Array` of `ChatSDK::Message` objects
2. A cursor for pagination (or `nil` if no more pages)

## Pagination

Use the returned cursor to fetch the next page:

```ruby
all_messages = []
cursor = nil

loop do
  messages, cursor = thread.messages(cursor: cursor, limit: 50)
  all_messages.concat(messages)
  break if cursor.nil?
end
```

## Building Context for AI

A common pattern is collecting conversation history to pass to an AI model:

```ruby
bot.on_new_mention do |thread, message|
  history, _ = thread.messages(limit: 20)

  context = history.map do |msg|
    role = msg.author.bot? ? "assistant" : "user"
    { role: role, content: msg.text }
  end

  # Pass context to your AI
  response = ai_client.chat(messages: context)
  thread.post(response)
end
```

## Platform Support

| Platform | History Support | Notes |
|----------|----------------|-------|
| Slack | Yes | Uses `conversations.replies` for threads, `conversations.history` for channels |
| Teams | Declared but limited | Returns empty results (Bot Framework limitation) |
| Google Chat | Yes | Uses `list_messages` API |

All three adapters declare the `:message_history` capability. The Teams adapter currently returns empty results because the Bot Framework API does not provide a message history endpoint for bots.

## Channel-Level History

For channel-level history (not scoped to a thread), use the adapter's `fetch_messages` directly:

```ruby
slack_adapter = bot.adapter(:slack)
messages, cursor = slack_adapter.fetch_messages(channel_id: "C12345", limit: 50)
```
