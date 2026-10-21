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
  tenant_id: ENV["TEAMS_TENANT_ID"],      # optional, set TEAMS_TENANT_ID env var
  service_url: ENV["TEAMS_SERVICE_URL"]   # optional fallback for proactive messages
)
```

`app_id` and `app_password` are required. `tenant_id` is optional. Incoming activities register their service URL per conversation, and ChatSDK persists it in the configured state store. `service_url` (or `TEAMS_SERVICE_URL`) is used only when no conversation-specific URL is known; it defaults to `https://smba.trafficmanager.net/teams/`.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TEAMS_APP_ID` | Bot's Application (client) ID from Azure AD |
| `TEAMS_APP_PASSWORD` | Bot's client secret |
| `TEAMS_TENANT_ID` | Azure AD tenant ID (optional) |
| `TEAMS_SERVICE_URL` | Fallback Bot Framework service URL for conversations without a cached URL |
| `TEAMS_GRAPH_CLIENT_ID` | Entra application client ID for Graph message history and file references |
| `TEAMS_GRAPH_CLIENT_SECRET` | Entra application secret for Graph access |
| `TEAMS_GRAPH_TENANT_ID` | Entra tenant used to acquire Graph access tokens |

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

Teams requires a `serviceUrl` to send messages. ChatSDK automatically caches and persists the URL from incoming activities under `chat_sdk:teams:service_url:<conversation_id>`. For proactive messaging, you may register it manually:

```ruby
teams_adapter = bot.adapter(:teams)
teams_adapter.register_service_url(
  "conversation-id-123",
  "https://smba.trafficmanager.net/..."
)
```

Set `service_url:` or `TEAMS_SERVICE_URL` to override the fallback for a deployment whose Bot Framework service endpoint is not the standard Teams endpoint. A service URL from an activity takes precedence.

Top-level posts to channel conversations return a thread ID containing `;messageid=<activity_id>`. Use that returned ID for follow-up replies.

## Cards Rendering

Cards are rendered as Adaptive Cards using the `AdaptiveCardRenderer`. Text inputs become `Input.Text` elements; their submitted values are available as `event.values` in `on_action`. The IDs `actionId`, `value`, and `msteams` are reserved for Teams submission metadata. Tables render as native Adaptive Card `Table` elements, including weighted columns, alignment, and grid options. When `ai_generated: true` is set on a postable message, Teams receives its `AIGeneratedContent` entity.

Adaptive Card invoke activities are acknowledged with a non-empty Bot Framework message response to avoid retries. Graph message history follows the `@odata.nextLink` cursor returned by Microsoft Graph; cursor URLs must use `https://graph.microsoft.com`. Graph `reference` attachments are resolved through the Graph Shares API and exposed as message attachments with a preauthenticated download URL. Graph history and attachment access require the corresponding application permissions.

## Installation lifecycle

Teams `installationUpdate` activities (`add`, `add-upgrade`, `remove`, and `remove-upgrade`) dispatch to `on_installed` and `on_uninstalled`. See [Handling Events](../handling-events.md#on_installed-and-on_uninstalled) for event fields and examples. The adapter does not map `conversationUpdate` membership events to installation callbacks.

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
