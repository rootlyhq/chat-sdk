# Emoji & Reactions

ChatSDK provides a unified API for adding and removing emoji reactions, and for handling reaction events from users.

## Adding Reactions

Use `thread.react` to add an emoji reaction to a message:

```ruby
bot.on_new_mention do |thread, message|
  # Add an "eyes" reaction to acknowledge receipt
  thread.react(message.id, "eyes")

  # Do work...
  result = process_request(message.text)

  # Replace with a checkmark when done
  thread.unreact(message.id, "eyes")
  thread.react(message.id, "white_check_mark")
  thread.post(result)
end
```

Emoji names are platform-specific shortcodes (e.g., `"thumbsup"`, `"rocket"`, `"white_check_mark"`). On Google Chat, unicode emoji characters are used.

## Removing Reactions

```ruby
thread.unreact(message.id, "eyes")
```

## Handling Reaction Events

Register `on_reaction` to respond when users react to messages:

```ruby
bot.on_reaction do |event|
  if event.added?
    puts "#{event.user_id} added :#{event.emoji}: to #{event.message_id}"
  else
    puts "#{event.user_id} removed :#{event.emoji}: from #{event.message_id}"
  end
end
```

### Filtering by Emoji

Pass an array of emoji names to filter:

```ruby
bot.on_reaction(%w[thumbsup thumbsdown]) do |event|
  if event.emoji == "thumbsup"
    event.thread.post("Thanks for the upvote!")
  else
    event.thread.post("Sorry to hear that.")
  end
end
```

Only events with matching emoji will trigger the handler. Unmatched reactions are ignored.

## The Reaction Event

| Attribute | Type | Description |
|-----------|------|-------------|
| `emoji` | `String` | Emoji name (e.g., `"thumbsup"`) |
| `user_id` | `String` | Who reacted |
| `message_id` | `String` | The message that was reacted to |
| `thread_id` | `String` | Thread identifier |
| `channel_id` | `String` | Channel identifier |
| `added?` | `Boolean` | `true` if the reaction was added |
| `removed?` | `Boolean` | `true` if the reaction was removed |
| `thread` | `Thread` | For posting replies |
| `platform` | `Symbol` | Which platform |

## Platform Support

| Platform | Add Reaction | Remove Reaction | Inbound Events |
|----------|-------------|-----------------|----------------|
| Slack | Yes | Yes | Yes |
| Teams | No (declared but raises PlatformError) | No | Yes |
| Google Chat | Yes (unicode) | Yes | Yes |

Teams declares the `:reactions` capability because it parses inbound reaction events, but the Bot Framework API does not support programmatically adding or removing reactions.

## Common Patterns

### Reaction-Based Voting

```ruby
bot.on_reaction(%w[thumbsup thumbsdown]) do |event|
  return unless event.added?

  # Track votes in thread state
  votes = event.thread.state || { "up" => 0, "down" => 0 }
  key = event.emoji == "thumbsup" ? "up" : "down"
  votes[key] += 1
  event.thread.set_state(votes)

  event.thread.post("Votes: #{votes["up"]} up / #{votes["down"]} down")
end
```

### Reaction as Trigger

```ruby
bot.on_reaction(%w[rocket]) do |event|
  return unless event.added?
  event.thread.post("Launching deployment...")
end
```

## Testing Reactions

```ruby
bot = ChatSDK::Testing.build_bot
adapter = bot.config.adapters[:test]

bot.on_reaction do |event|
  event.thread.react(event.message_id, "thumbsup") if event.added?
end

adapter.simulate_reaction(bot, emoji: "wave", added: true)

assert_equal 1, adapter.reactions_added.size
assert_equal "thumbsup", adapter.reactions_added.first.emoji
```
