# Microsoft Teams Adapter

The Teams adapter (`chat_sdk-teams`) integrates with Microsoft Teams via the Bot Framework.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-teams"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/teams"

teams = ChatSDK::Teams::Adapter.new(
  app_id: ENV["TEAMS_APP_ID"],           # or set TEAMS_APP_ID env var
  app_password: ENV["TEAMS_APP_PASSWORD"], # or set TEAMS_APP_PASSWORD env var
  tenant_id: ENV["TEAMS_TENANT_ID"]       # optional, set TEAMS_TENANT_ID env var
)
```

`app_id` and `app_password` are required. `tenant_id` is optional.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TEAMS_APP_ID` | Bot's Application (client) ID from Azure AD |
| `TEAMS_APP_PASSWORD` | Bot's client secret |
| `TEAMS_TENANT_ID` | Azure AD tenant ID (optional) |

## Azure Bot Setup

1. Register a bot in the [Azure Portal](https://portal.azure.com) under **Bot Services**.
2. Note the Application (client) ID and create a client secret.
3. Configure the messaging endpoint to your webhook URL (e.g., `https://your-app.com/webhooks/teams`).
4. Create a Teams app manifest and install it in your Teams organization.

## Webhook URL

```
https://your-domain.com/webhooks/teams
```

```ruby
map "/webhooks/teams" do
  run bot.webhooks[:teams]
end
```

## Capabilities

| Capability | Supported | Notes |
|------------|-----------|-------|
| `edit_messages` | Yes | |
| `delete_messages` | Yes | |
| `ephemeral_messages` | No | Raises `NotSupportedError` |
| `file_uploads` | Yes | Via Base64-encoded attachments |
| `reactions` | Inbound only | Parsing works, but adding/removing raises `PlatformError` |
| `modals` | No | Raises `NotSupportedError` |
| `typing_indicator` | No | Raises `NotSupportedError` |
| `streaming_edit` | Yes | |
| `threads` | Yes | Uses `replyToId` |
| `direct_messages` | Yes | Creates 1:1 conversations |
| `message_history` | Declared | Returns empty (Bot Framework limitation) |

## Service URL Registration

Teams requires a `serviceUrl` to send messages. ChatSDK automatically caches the service URL from incoming activities. For proactive messaging, you may need to register it manually:

```ruby
teams_adapter = bot.adapter(:teams)
teams_adapter.register_service_url(
  "conversation-id-123",
  "https://smba.trafficmanager.net/..."
)
```

## Cards Rendering

Cards are rendered as Adaptive Cards using the `AdaptiveCardRenderer`. They are sent as message attachments with content type `application/vnd.microsoft.card.adaptive`.

## Direct Client Access

```ruby
teams_adapter = bot.adapter(:teams)
client = teams_adapter.client  # BotFrameworkClient
```

## Mention Formatting

Teams mentions use the format `<at>USER_ID</at>`:

```ruby
thread.mention_user("user-id-123")  # => "<at>user-id-123</at>"
```
