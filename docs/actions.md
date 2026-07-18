# Actions

Actions handle interactive elements in cards: button clicks and select menu choices. When a user interacts with a card element that has an `id`, ChatSDK dispatches an action event.

## Defining Actionable Elements

Add buttons and selects to your cards with unique `id` values:

```ruby
card = ChatSDK.card(title: "Deploy Request") do
  text "Deploy **v2.1.0** to production?"

  actions do
    button "Approve", id: "deploy_approve", style: :primary, value: "v2.1.0"
    button "Reject", id: "deploy_reject", style: :danger, value: "v2.1.0"

    select id: "deploy_env", placeholder: "Or choose environment" do
      option "Production", value: "prod"
      option "Staging", value: "staging"
    end
  end
end

thread.post(card)
```

## Handling Actions

Register handlers that match by `action_id`:

```ruby
bot.on_action("deploy_approve") do |event|
  event.thread.post("Deploy approved by #{event.user.name}!")
end

bot.on_action("deploy_reject") do |event|
  event.thread.post("Deploy rejected by #{event.user.name}.")
end

bot.on_action("deploy_env") do |event|
  event.thread.post("Deploying to #{event.value}...")
end
```

## The Action Event

The event object passed to `on_action` provides:

| Attribute | Type | Description |
|-----------|------|-------------|
| `action_id` | `String` | The `id` of the clicked element |
| `value` | `String` | The `value` attached to the button or selected option |
| `user` | `Author` | The user who performed the action |
| `thread` | `Thread` | For posting replies |
| `trigger_id` | `String` | For opening modals (platform-dependent) |
| `channel_id` | `String` | Channel where the action occurred |
| `thread_id` | `String` | Thread where the action occurred |
| `platform` | `Symbol` | Which platform the action came from |

## Common Patterns

### Confirmation Flow

```ruby
# Post a card with approve/reject buttons
bot.on_new_mention do |thread, message|
  card = ChatSDK.card(title: "Confirm Action") do
    text "Are you sure you want to proceed?"
    actions do
      button "Yes", id: "confirm", style: :primary, value: message.id
      button "No", id: "cancel", style: :danger, value: message.id
    end
  end
  thread.post(card)
end

bot.on_action("confirm") do |event|
  event.thread.post("Confirmed!")
end

bot.on_action("cancel") do |event|
  event.thread.post("Cancelled.")
end
```

### Action with Modal Follow-Up

```ruby
bot.on_action("create_ticket") do |event|
  if event.thread.adapter.supports?(:modals)
    modal = ChatSDK::Modals::Builder.new(title: "New Ticket") do
      text_input id: "title", label: "Title"
      text_input id: "description", label: "Description", multiline: true
    end.build
    event.thread.open_modal(trigger_id: event.trigger_id, modal: modal)
  else
    event.thread.post("Please describe the ticket by replying to this thread.")
    event.thread.subscribe
  end
end
```

### Same ID, Different Values

Use the `value` attribute to distinguish between options with the same action ID:

```ruby
card = ChatSDK.card do
  actions do
    button "High", id: "set_priority", value: "high"
    button "Medium", id: "set_priority", value: "medium"
    button "Low", id: "set_priority", value: "low"
  end
end

bot.on_action("set_priority") do |event|
  event.thread.post("Priority set to: #{event.value}")
end
```

## Testing Actions

```ruby
bot = ChatSDK::Testing.build_bot
adapter = bot.config.adapters[:test]

bot.on_action("my_btn") do |event|
  event.thread.post("Clicked: #{event.value}")
end

adapter.simulate_action(bot, action_id: "my_btn", value: "test-value")

assert_equal 1, adapter.posted_messages.size
assert_equal "Clicked: test-value", adapter.posted_messages.first.message.text
```
