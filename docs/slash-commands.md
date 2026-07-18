# Slash Commands

Slash commands let users invoke your bot with a `/command` prefix. ChatSDK normalizes slash command events across platforms.

## Registering a Command Handler

```ruby
bot.on_slash_command("/deploy") do |event|
  event.thread.post("Deploying: #{event.text}")
end

bot.on_slash_command("/status") do |event|
  card = ChatSDK.card(title: "System Status") do
    fields do
      field "API", "Operational"
      field "Database", "Operational"
      field "Workers", "Degraded"
    end
  end
  event.thread.post(card)
end
```

## The SlashCommand Event

| Attribute | Type | Description |
|-----------|------|-------------|
| `command` | `String` | The command name (e.g., `"/deploy"`) |
| `text` | `String` | Everything the user typed after the command |
| `user_id` | `String` | Who invoked the command |
| `channel_id` | `String` | Where the command was invoked |
| `trigger_id` | `String` | For opening modals (platform-dependent) |
| `thread` | `Thread` | For posting replies |
| `platform` | `Symbol` | Which platform |

## Parsing Arguments

The `event.text` contains everything after the command. Parse it however you like:

```ruby
bot.on_slash_command("/deploy") do |event|
  args = event.text.split
  service = args[0]
  environment = args[1] || "staging"

  event.thread.post("Deploying #{service} to #{environment}...")
end
```

## Opening a Modal from a Command

Slash commands provide a `trigger_id` you can use to open a modal:

```ruby
bot.on_slash_command("/create-ticket") do |event|
  modal = ChatSDK::Modals::Builder.new(
    title: "New Ticket",
    submit_label: "Create",
    callback_id: "new_ticket"
  ) do
    text_input id: "title", label: "Title", placeholder: "Brief description"
    text_input id: "details", label: "Details", multiline: true, optional: true
    select_input id: "priority", label: "Priority" do
      option "High", value: "high"
      option "Medium", value: "medium"
      option "Low", value: "low"
    end
  end.build

  event.thread.open_modal(trigger_id: event.trigger_id, modal: modal)
end
```

## Platform Setup

### Slack

1. Go to your Slack app settings -> Slash Commands.
2. Create a new command (e.g., `/deploy`).
3. Set the Request URL to your webhook endpoint (e.g., `https://your-app.com/webhooks/slack`).
4. Slack sends slash command payloads to the same webhook URL as other events.

### Teams

Slash commands in Teams are handled through the Bot Framework messaging extension. Configure commands in your bot's app manifest.

### Google Chat

Google Chat uses slash commands configured in the Google Cloud Console under your Chat app's settings.

## Testing Slash Commands

```ruby
bot = ChatSDK::Testing.build_bot
adapter = bot.config.adapters[:test]

bot.on_slash_command("/deploy") do |event|
  event.thread.post("Deploying #{event.text}")
end

adapter.simulate_slash_command(bot, command: "/deploy", text: "production v2.0")

assert_equal 1, adapter.posted_messages.size
assert_equal "Deploying production v2.0", adapter.posted_messages.first.message.text
```
