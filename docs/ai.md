# AI Layer

The AI module provides provider-agnostic utilities for integrating LLMs with ChatSDK. It has no dependency on any specific AI/LLM gem -- you bring your own provider.

## Message Conversion

Convert ChatSDK messages into the `{role, content}` format expected by most LLMs:

```ruby
# Fetch messages from a thread
messages, _ = adapter.fetch_messages(channel_id: "C123", thread_id: "T456")

# Convert to AI format
ai_messages = ChatSDK::AI.to_ai_messages(messages)
# => [{ role: "user", content: "Hello" }, { role: "assistant", content: "Hi there!" }]

# Include user names for multi-user conversations
ai_messages = ChatSDK::AI.to_ai_messages(messages, include_names: true)
# => [{ role: "user", content: "[Alice]: Hello" }, ...]

# Custom transform (e.g., add system context, filter)
ai_messages = ChatSDK::AI.to_ai_messages(messages) do |msg, original|
  msg[:metadata] = { message_id: original.id }
  msg
end
```

See [Message Conversion](ai/to-ai-messages.md) for full details.

## Agent Tools

Generate tool definitions for AI agents with preset permission levels:

```ruby
# Create tool definitions for an agent
tools = ChatSDK::AI.create_tools(chat: chat, preset: :messenger)

# Three presets available:
# :reader    - fetch_messages, fetch_thread (read-only)
# :messenger - reader + post_message, send_direct_message, add_reaction, start_typing
# :moderator - messenger + edit_message, delete_message, remove_reaction

# Execute a tool call from an LLM response
builder = ChatSDK::AI::ToolBuilder.new(chat: chat, preset: :messenger)
result = builder.execute(:post_message, {
  adapter_name: "slack",
  channel_id: "C123",
  text: "Hello from the AI agent!"
})
```

See [Agent Tools](ai/agent-tools.md) for full details.

## Streaming LLM Responses

Bridge any `Enumerable` or `Enumerator` of string chunks to a ChatSDK streaming message:

```ruby
# With any LLM client that returns an enumerable of chunks
thread.post_ai_stream(llm_chunks, placeholder: "Thinking...")

# Or use the class directly
ChatSDK::AI::StreamHandler.stream_to_thread(thread, llm_chunks)
```

## Provider-Agnostic Example

```ruby
chat.on_new_mention do |event, thread|
  # 1. Fetch conversation history
  messages, _ = thread.messages

  # 2. Convert to AI format
  ai_messages = ChatSDK::AI.to_ai_messages(messages, include_names: true)

  # 3. Call your LLM (any provider)
  response = your_llm_client.chat(messages: ai_messages)

  # 4. Post the response
  thread.post(response.text)
end
```
