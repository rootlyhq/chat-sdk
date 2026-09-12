# Conversation History

ChatSDK exposes history through `bot.history`, with user-, thread-, and channel-scoped APIs. This is useful for building context-aware bots that need to read back conversation history across platforms.

## Unified History API

```ruby
thread_page = bot.history.thread.list(thread, limit: 20)
channel_page = bot.history.channel.list_messages(channel, limit: 50)
threads_page = bot.history.channel.list_threads(channel, limit: 50)
```

Each page is a hash containing the result (`:messages` or `:threads`) and `:next_cursor`.

`bot.transcripts` remains available as a deprecated alias for `bot.history.user`.

## User History

User history can combine a person's conversations across platforms. By default, the normalized author email is the identity key; configure a resolver when your adapters use another identity:

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: {slack: slack},
  state: state,
  history: {
    user: {
      identity: ->(_thread, message) { message.author.email },
      retention: 30 * 24 * 60 * 60,
      max_per_user: 200
    }
  }
)

bot.history.user.append(thread, message)
entries = bot.history.user.list(user_key: "person@example.com", limit: 20)
prompt = bot.history.user.to_prompt_entries(entries)
bot.history.user.delete(user_key: "person@example.com")
```

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
