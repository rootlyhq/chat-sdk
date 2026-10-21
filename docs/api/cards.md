# API Reference: Cards

The cards system consists of `Cards::Builder`, `Cards::Node`, and context classes for building structured messages.

## ChatSDK.card

Top-level entry point for building cards:

```ruby
card = ChatSDK.card(title: "My Card", subtitle: "Optional", width: :full) do
  text "Content here"
end
```

Returns a `Cards::Node` of type `:card`.

## Cards::Builder

Block-based DSL for constructing card nodes.

### Methods

| Method | Parameters | Description |
|--------|-----------|-------------|
| `text(content)` | `String` | Add a text block |
| `divider` | -- | Add a horizontal divider |
| `image(url:, alt:)` | `String`, `String?` | Add an image |
| `fields(&block)` | Block | Add key-value fields |
| `section(title = nil, &block)` | `String?`, Block | Add a grouped section |
| `actions(&block)` | Block | Add interactive elements |
| `text_input(id:, label:, placeholder:, multiline:, optional:, value:)` | keyword args | Add a cross-platform text-input placeholder; generic renderers show its label |
| `table(headers:, rows:, ...)` | keyword args | Add tabular data |
| `chart(title:, type:, ...)` | keyword args | Add a pie, bar, line, or area chart |

## Cards::FieldsContext

Available inside a `fields` block:

```ruby
fields do
  field "Label", "Value"
  field "Status", "Active"
end
```

### Methods

| Method | Parameters | Description |
|--------|-----------|-------------|
| `field(label, value)` | `String`, `String` | Add a key-value field |

## Cards::ActionsContext

Available inside an `actions` block:

```ruby
actions do
  button "Click", id: "btn_1"
  link_button "Open", url: "https://example.com"
  select id: "menu", placeholder: "Choose" do
    option "A", value: "a"
  end
end
```

### Methods

| Method | Parameters | Description |
|--------|-----------|-------------|
| `button(text, id:, style:, value:, tooltip:, visible_to:)` | `String`, keyword args | Add a button; `visible_to` is a Slack-only display hint |
| `link_button(text, url:, id:, tooltip:, visible_to:)` | `String`, keyword args | Add a link button; `visible_to` is a Slack-only display hint |
| `select(id:, placeholder:, &block)` | keyword args, Block | Add a select menu |

`visible_to` is a display hint rendered natively only by Slack. Other platforms still show the button, so action handlers must check `event.user` before acting.

## Cards::SelectContext

Available inside a `select` block:

```ruby
select id: "menu" do
  option "Label", value: "val", description: "Help text"
end
```

### Methods

| Method | Parameters | Description |
|--------|-----------|-------------|
| `option(text, value:, description:)` | `String`, keyword args | Add a select option |

## Cards::Node

The immutable tree node that represents a card element.

| Attribute | Type | Description |
|-----------|------|-------------|
| `type` | `Symbol` | Node type (`:card`, `:text`, `:text_input`, `:fields`, etc.) |
| `attributes` | `Hash` | Node-specific attributes |
| `children` | `Array<Node>` | Child nodes (frozen) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `fallback_text` | `String` | Plain-text representation of the card tree |

### Node Types

| Type | Attributes | Children |
|------|-----------|----------|
| `:card` | `title`, `subtitle`, `width` | Any node types |
| `:text` | `content` | None |
| `:divider` | None | None |
| `:image` | `url`, `alt` | None |
| `:fields` | None | `:field` nodes |
| `:field` | `label`, `value` | None |
| `:section` | `title` | Any node types |
| `:actions` | None | Button/select nodes |
| `:button` | `text`, `id`, `style`, `value` | None |
| `:link_button` | `text`, `url` | None |
| `:select` | `id`, `placeholder` | `:option` nodes |
| `:option` | `text`, `value`, `description` | None |
| `:table` | `headers`, `rows`, `align`, `caption`, `page_size` | None |
| `:chart` | `title`, `chart_type`, `segments`, `categories`, `series` | None |
