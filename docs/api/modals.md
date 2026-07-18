# API Reference: Modals

The modals system provides `Modals::Builder` for constructing modal dialogs.

## Modals::Builder

```ruby
modal = ChatSDK::Modals::Builder.new(
  title: "Form Title",
  submit_label: "Submit",    # optional
  callback_id: "my_form"     # optional
) do
  text_input id: "name", label: "Name"
  select_input id: "role", label: "Role" do
    option "Admin", value: "admin"
    option "User", value: "user"
  end
  static_text "Help text here"
end.build
```

### Constructor Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `title` | `String` | Yes | Modal title |
| `submit_label` | `String` | No | Text for the submit button |
| `callback_id` | `String` | No | Identifier for submission handling |

### Methods

#### text_input(id:, label:, placeholder:, multiline:, optional:)

Adds a text input field.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id` | `String` | -- | Unique input identifier |
| `label` | `String` | -- | Display label |
| `placeholder` | `String` | `nil` | Placeholder text |
| `multiline` | `Boolean` | `false` | Multi-line text area |
| `optional` | `Boolean` | `false` | Whether the field is optional |

#### select_input(id:, label:, placeholder:, optional:, &block)

Adds a select dropdown. The block uses the same `SelectContext` as card selects.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id` | `String` | -- | Unique input identifier |
| `label` | `String` | -- | Display label |
| `placeholder` | `String` | `nil` | Placeholder text |
| `optional` | `Boolean` | `false` | Whether the field is optional |

Inside the block:

```ruby
option "Display Text", value: "val", description: "Help text"
```

#### static_text(content)

Adds non-interactive text content to the modal.

| Parameter | Type | Description |
|-----------|------|-------------|
| `content` | `String` | Text to display |

### build

Returns a `Cards::Node` of type `:modal` with the following attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `title` | `String` | Modal title |
| `submit_label` | `String` | Submit button text |
| `callback_id` | `String` | Submission callback identifier |

Children are `:input` nodes (for text_input and select_input) and `:text` nodes (for static_text).

## Input Node Attributes

For `:input` nodes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | `String` | Input identifier |
| `label` | `String` | Display label |
| `input_type` | `Symbol` | `:text` or `:select` |
| `multiline` | `Boolean` | Multi-line flag |
| `optional` | `Boolean` | Optional flag |
| `placeholder` | `String` | Placeholder text |

## Opening a Modal

```ruby
# From an action handler
bot.on_action("open_form") do |event|
  modal = ChatSDK::Modals::Builder.new(title: "Form") do
    text_input id: "name", label: "Name"
  end.build

  event.thread.open_modal(trigger_id: event.trigger_id, modal: modal)
end
```

Only Slack supports modals. See [Modals](../modals.md) for usage details.
