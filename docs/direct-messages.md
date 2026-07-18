# Direct Messages

ChatSDK lets you open DM conversations and send private messages to individual users across all supported platforms.

## Opening a DM

Use `bot.open_dm` to start or find a DM conversation with a user:

```ruby
dm_channel = bot.open_dm("U12345", adapter_name: :slack)
dm_channel.post("Hello! This is a private message.")
```

`open_dm` calls the platform API to open (or locate) the DM channel and returns a `ChatSDK::Channel` object. You can then post messages to it like any other channel.

If you only have one adapter, you can omit `adapter_name:`:

```ruby
dm_channel = bot.open_dm("U12345")
dm_channel.post("Just between us.")
```

## Handling Incoming DMs

Register `on_direct_message` to handle messages users send directly to your bot:

```ruby
bot.on_direct_message do |thread, message|
  thread.post("You said: #{message.text}")
end
```

The handler receives the same `(thread, message)` signature as `on_new_mention`. The `thread` object lets you reply in the DM conversation.

## DM Conversations with Context

Combine DMs with thread state for multi-turn conversations:

```ruby
bot.on_direct_message do |thread, message|
  state = thread.state || { "step" => "greeting" }

  case state["step"]
  when "greeting"
    thread.post("What is your name?")
    state["step"] = "name"
  when "name"
    thread.post("Nice to meet you, #{message.text}!")
    state["step"] = "done"
  end

  thread.set_state(state)
  thread.subscribe
end

bot.on_subscribed_message do |thread, message|
  state = thread.state || {}
  if state["step"] == "name"
    thread.post("Nice to meet you, #{message.text}!")
    thread.set_state(state.merge("step" => "done"))
    thread.unsubscribe
  end
end
```

## Platform Support

| Platform | DM Support |
|----------|-----------|
| Slack | Yes -- uses `conversations.open` |
| Teams | Yes -- creates a 1:1 conversation |
| Google Chat | Yes -- uses `setup_space` with `DIRECT_MESSAGE` |

All three adapters declare the `:direct_messages` capability. If you build a custom adapter without DM support, calling `open_dm` raises `ChatSDK::NotSupportedError`.

## Proactive DMs

You can send a DM at any time, not just in response to events:

```ruby
# In a controller, job, or cron task
bot = ChatBot.instance
dm = bot.open_dm("U12345", adapter_name: :slack)
dm.post("Reminder: your deploy is waiting for approval.")
```
