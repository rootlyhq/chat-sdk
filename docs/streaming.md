# Streaming

Streaming lets you post a placeholder message and update it incrementally as content arrives, similar to how ChatGPT shows tokens appearing. This is useful for AI-powered bots that generate responses token by token.

## Basic Usage

```ruby
bot.on_new_mention do |thread, message|
  thread.post_stream(placeholder: "Thinking...") do |stream|
    # Simulate token-by-token generation
    words = ["Hello", " ", "world", "!", " ", "How", " ", "are", " ", "you", "?"]
    words.each do |word|
      stream << word
      sleep(0.1)
    end
  end
end
```

## How It Works

1. `post_stream` posts the `placeholder` text as a new message.
2. The block receives a `Streaming::Stream` object.
3. Use `stream << chunk` to append text to an internal buffer.
4. The stream flushes (edits the message) at a throttled interval to avoid hitting API rate limits.
5. When the block returns, a final flush sends any remaining buffered content.

## Configuration

The throttle interval is controlled by `streaming_update_interval` (default: 0.5 seconds):

```ruby
bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: { slack: slack },
  state: state,
  streaming_update_interval: 1.0  # Flush at most once per second
)
```

## Without a Placeholder

If you omit the `placeholder:`, the first flush creates the initial message:

```ruby
thread.post_stream do |stream|
  stream << "Starting..."
  # The message is created on the first flush
  stream << " done!"
end
```

## Adapter Compatibility

Streaming works on any adapter that supports message editing (`edit_messages` capability). If the adapter does not support editing, the stream falls back to posting the final accumulated text as a single message.

| Adapter | Streaming Support |
|---------|------------------|
| Slack | Full (edit-based) |
| Teams | Full (edit-based) |
| Google Chat | Full (edit-based) |
| FakeAdapter | Full (for testing) |

## Integrating with AI APIs

Here is a realistic example using a streaming AI response:

```ruby
bot.on_new_mention do |thread, message|
  thread.post_stream(placeholder: "Generating response...") do |stream|
    client = OpenAI::Client.new
    client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: message.text }],
        stream: proc do |chunk|
          content = chunk.dig("choices", 0, "delta", "content")
          stream << content if content
        end
      }
    )
  end
end
```

## Testing Streams

Use `FakeAdapter` to verify streaming behavior:

```ruby
bot = ChatSDK::Testing.build_bot
adapter = bot.config.adapters[:test]

bot.on_new_mention do |thread, message|
  thread.post_stream(placeholder: "...") do |stream|
    stream << "hello "
    stream << "world"
  end
end

adapter.simulate_mention(bot, text: "test")

# The placeholder is posted, then edited with the final content
assert adapter.posted_messages.size >= 1
assert adapter.edited_messages.size >= 1
```
