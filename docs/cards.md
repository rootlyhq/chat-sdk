# Cards

Cards are rich, structured messages that render natively on each platform: Block Kit on Slack, Adaptive Cards on Teams, and Card v2 on Google Chat. ChatSDK provides a Ruby DSL for building cards that is platform-agnostic.

## Building a Card

Use `ChatSDK.card` with a block:

```ruby
card = ChatSDK.card(title: "Incident Report", subtitle: "INC-42") do
  text "Database connection pool exhausted"

  fields do
    field "Severity", "SEV1"
    field "Status", "Investigating"
    field "Duration", "12 minutes"
  end

  divider

  section "Affected Services" do
    text "- API Gateway"
    text "- User Service"
  end

  image url: "https://example.com/chart.png", alt: "Error rate graph"

  actions do
    button "Acknowledge", id: "ack_btn", style: :primary, value: "inc-42"
    button "Escalate", id: "escalate_btn", style: :danger
    link_button "View Dashboard", url: "https://example.com/dashboard"
  end
end
```

Post the card like any other message:

```ruby
thread.post(card)
```

## Node Types

### text

Renders a block of text content.

```ruby
ChatSDK.card do
  text "Hello, **world**!"
end
```

### fields

Renders key-value pairs in a compact layout (two columns on most platforms).

```ruby
ChatSDK.card do
  fields do
    field "Status", "Active"
    field "Region", "us-east-1"
    field "Uptime", "99.9%"
  end
end
```

### divider

A horizontal rule separating sections.

```ruby
ChatSDK.card do
  text "Above the line"
  divider
  text "Below the line"
end
```

### image

Displays an image.

```ruby
ChatSDK.card do
  image url: "https://example.com/logo.png", alt: "Company logo"
end
```

### section

Groups child elements under an optional title.

```ruby
ChatSDK.card do
  section "Details" do
    text "Some details here"
    fields do
      field "Key", "Value"
    end
  end
end
```

### actions

Contains interactive elements: buttons, link buttons, and select menus.

```ruby
ChatSDK.card do
  actions do
    button "Click me", id: "btn_1"
    button "Danger", id: "btn_2", style: :danger, value: "dangerous"
    link_button "Open URL", url: "https://example.com"

    select id: "priority_select", placeholder: "Choose priority" do
      option "Low", value: "low"
      option "Medium", value: "medium", description: "Default priority"
      option "High", value: "high"
    end
  end
end
```

## Button Styles

Buttons accept an optional `style:` parameter:

- `:primary` -- Emphasized button (green on Slack, accent color on Teams)
- `:danger` -- Destructive action (red on most platforms)
- `nil` -- Default/neutral style

## Button Values

Attach a `value:` to buttons to distinguish which option was selected when handling the action:

```ruby
actions do
  button "Approve", id: "review_btn", value: "approve"
  button "Reject", id: "review_btn", value: "reject"
end
```

In your action handler:

```ruby
bot.on_action("review_btn") do |event|
  case event.value
  when "approve" then event.thread.post("Approved!")
  when "reject"  then event.thread.post("Rejected.")
  end
end
```

## Select Menus

Select menus let users choose from a list of options.

```ruby
ChatSDK.card do
  actions do
    select id: "env_select", placeholder: "Choose environment" do
      option "Production", value: "prod"
      option "Staging", value: "staging"
      option "Development", value: "dev", description: "Local dev cluster"
    end
  end
end
```

Handle selections with `on_action`:

```ruby
bot.on_action("env_select") do |event|
  event.thread.post("You selected: #{event.value}")
end
```

## Cards with Text Fallback

When you pass a card to `thread.post`, ChatSDK automatically generates a plain-text fallback from the card's content. This fallback is used for push notifications and platforms that cannot render rich cards.

If you need to customize the fallback, use `PostableMessage` directly:

```ruby
msg = ChatSDK::PostableMessage.new(
  text: "Custom notification text",
  card: ChatSDK.card(title: "Rich Card") { text "Details" }
)
thread.post(msg)
```

## How Cards Render

The same card DSL renders differently depending on the adapter:

- **Slack** -- Rendered as Block Kit JSON via `BlockKitRenderer`
- **Teams** -- Rendered as Adaptive Card JSON via `AdaptiveCardRenderer`
- **Google Chat** -- Rendered as Card v2 JSON via `CardV2Renderer`

You never need to interact with these renderers directly. The adapter handles it when you call `thread.post(card)`.
