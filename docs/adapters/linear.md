# Linear Adapter

The Linear adapter (`chat_sdk-linear`) integrates with the Linear GraphQL API for issue comments, reactions, and HMAC-SHA256 webhook signature verification.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-linear"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/linear"

linear = ChatSDK::Linear::Adapter.new(
  api_key: ENV["LINEAR_API_KEY"],             # Linear API key
  webhook_secret: ENV["LINEAR_WEBHOOK_SECRET"], # Webhook signing secret
  bot_username: ENV["LINEAR_BOT_USERNAME"]    # Bot display name (for filtering own messages)
)
```

`api_key` and `webhook_secret` are required. `bot_username` is recommended to filter out the bot's own comments from incoming events.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `LINEAR_API_KEY` | API key from Linear Settings > API |
| `LINEAR_WEBHOOK_SECRET` | Webhook signing secret from your Linear webhook configuration |
| `LINEAR_BOT_USERNAME` | The bot's display name in Linear (used to skip own messages in event parsing) |

## Linear Webhook Setup

1. Go to **Settings > API > Webhooks** in your Linear workspace.
2. Create a new webhook with the URL pointing to your server.
3. Select **Comment** events (create action).
4. Copy the webhook signing secret for `LINEAR_WEBHOOK_SECRET`.
5. Note the bot account's display name for `LINEAR_BOT_USERNAME`.

## Webhook URL

```
https://your-domain.com/webhooks/linear
```

```ruby
map "/webhooks/linear" do
  run bot.webhooks[:linear]
end
```

## Capabilities

| Capability | Supported |
|------------|-----------|
| `reactions` | Yes |
| `edit_messages` | No |
| `delete_messages` | No |
| `ephemeral_messages` | No |
| `typing_indicator` | No |
| `streaming_edit` | No |
| `threads` | No |
| `direct_messages` | No |
| `message_history` | No |
| `file_uploads` | No |
| `modals` | No |

## Events

The adapter parses webhook events for new comments:

- **Comment Create** -- When a new comment is created on an issue, parsed as `Events::Mention` with `thread_id: "linear:{issue_id}:c:{comment_id}"`.

Comments from the bot itself (matching `bot_username`) are automatically skipped.

## Direct Client Access

```ruby
linear_adapter = bot.adapter(:linear)
client = linear_adapter.client  # ChatSDK::Linear::ApiClient

# Create a comment on an issue
client.create_comment(issue_id: "issue-id", body: "Hello from ChatSDK!")

# Create a threaded reply
client.create_comment(issue_id: "issue-id", body: "Reply!", parent_id: "parent-comment-id")

# Add a reaction to a comment
client.create_reaction(comment_id: "comment-id", emoji: "thumbsup")

# Remove a reaction from a comment
client.delete_reaction(comment_id: "comment-id", emoji: "thumbsup")
```

## Mention Formatting

Linear mentions use the `@username` format:

```ruby
linear_adapter.mention("quentin")  # => "@quentin"
```

## Message IDs

- **Comments**: Linear comment UUIDs (e.g., `"a1b2c3d4-e5f6-..."`)
- **Thread IDs**: Prefixed strings -- `"linear:{issue_id}:c:{comment_id}"`
- **Channel IDs**: The Linear issue ID
- **Reply routing**: When `thread_id` contains `:c:`, `post_message` creates a threaded reply using the comment ID as `parent_id`
