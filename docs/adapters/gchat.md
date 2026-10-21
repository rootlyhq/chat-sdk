# Google Chat Adapter

The Google Chat adapter (`chat_sdk-gchat`) integrates with Google Chat using the Google Chat API and Card v2.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-gchat"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/gchat"

gchat = ChatSDK::GChat::Adapter.new(
  project_number: ENV["GOOGLE_CHAT_PROJECT_NUMBER"],
  endpoint_url: "https://your-domain.com/webhooks/gchat",
  pubsub_audience: ENV["GOOGLE_CHAT_PUBSUB_AUDIENCE"],
  pubsub_service_account_email: ENV["GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL"],
  workspace_add_on_service_account_email: ENV["GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL"],
  credentials: nil  # Uses Application Default Credentials
)
```

### Credentials Options

The `credentials` parameter accepts several formats:

```ruby
# 1. nil -- Use Application Default Credentials (ADC)
gchat = ChatSDK::GChat::Adapter.new(project_number: "123456")

# 2. String -- Path to a service account JSON file
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: "/path/to/service-account.json"
)

# 3. Hash -- Service account JSON as a Ruby hash
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: {
    "type" => "service_account",
    "project_id" => "my-project",
    # ...
  }
)

# 4. Pre-built credentials object
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials: my_credentials_object
)
```

## Per-request credentials

Per-request credentials are a chat-sdk extension; upstream `vercel/chat` configures one credentials value per adapter. A resolver can select credentials for each outbound channel:

```ruby
gchat = ChatSDK::GChat::Adapter.new(
  project_number: "123456",
  credentials_resolver: ->(channel_id) { credentials_for_channel(channel_id) }
)
```

The resolver receives the channel ID and may return any value accepted by `credentials:`. Returning `nil` uses the adapter-wide credentials or Application Default Credentials. Alternatively, `with_credentials` scopes credentials to outbound calls made inside its block:

```ruby
gchat.with_credentials(tenant_credentials) do
  gchat.post_message(channel_id: "SPACE_ID", message: "Hello")
end
```

Opening a new direct-message space has no channel ID yet, so it uses the scoped or adapter-wide credentials rather than calling the resolver.

The resolver is evaluated when an outbound call runs, including in background jobs dispatched by `handler_executor`. The `with_credentials` scope is thread-local and does not carry into those jobs; establish the scope inside the job or use the resolver.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GOOGLE_CHAT_PROJECT_NUMBER` | Your Google Cloud project number |
| `GOOGLE_CHAT_PUBSUB_AUDIENCE` | The expected OIDC audience for Pub/Sub push requests |
| `GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL` | The exact service-account email configured for Pub/Sub push authentication |
| `GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL` | The exact Workspace Add-on service-account email allowed for endpoint-URL webhooks |
| `GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION` | Set to `true` to accept unverified webhook transports without a configured verifier; not recommended in production |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON (for ADC) |

## Webhook Verification

Direct Google Chat webhooks support two authentication audience modes:

- **Project number:** Set `project_number` or `GOOGLE_CHAT_PROJECT_NUMBER`. Tokens are verified against Google's X.509 certificates for `chat@system.gserviceaccount.com`, with the project number as the audience.
- **HTTP endpoint URL:** Set `endpoint_url` to the configured public webhook URL. This value has no environment-variable fallback and is used as the exact OIDC audience. The verified token must identify `chat@system.gserviceaccount.com` or exactly match the configured `workspace_add_on_service_account_email`.

When both direct-webhook options are configured, either token mode is accepted. The endpoint URL is never inferred from the incoming request.

The normal webhook endpoint also accepts Pub/Sub pushes. Configure both `pubsub_audience` and `pubsub_service_account_email` (or their environment variables) to validate the OIDC audience and exact, verified service-account email. The endpoint detects Pub/Sub envelopes, verifies them with this separate verifier, and `parse_events` decodes them; a direct-webhook verifier alone does not authenticate Pub/Sub pushes.

The adapter requires at least one direct-webhook verifier, a Pub/Sub audience, or `disable_signature_verification: true`. The explicit disable option (or `GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION=true`) accepts requests without a verifier for that transport and logs a warning once. Use it only when verification is intentionally handled elsewhere.

## Google Cloud Setup

1. In the [Google Cloud Console](https://console.cloud.google.com), enable the Google Chat API.
2. Create a service account with the Chat Bot scope.
3. Configure your Chat app in the Google Cloud Console:
   - Set the app URL to your webhook endpoint.
   - Configure slash commands if needed.
4. Publish the app to your organization or make it available in Google Workspace Marketplace.

## Webhook URL

```
https://your-domain.com/webhooks/gchat
```

```ruby
map "/webhooks/gchat" do
  run bot.webhooks[:gchat]
end
```

## Capabilities

| Capability | Supported | Notes |
|------------|-----------|-------|
| `edit_messages` | Yes | Uses `update_message` |
| `delete_messages` | Yes | Uses `delete_message` |
| `ephemeral_messages` | Yes | Uses `private_message_viewer` |
| `file_uploads` | No | Raises `NotSupportedError` |
| `reactions` | Yes | Uses unicode emoji |
| `modals` | No | Raises `NotSupportedError` |
| `typing_indicator` | No | Raises `NotSupportedError` |
| `streaming_edit` | Yes | |
| `threads` | Yes | Uses Google Chat thread names |
| `direct_messages` | Yes | Uses `setup_space` with `DIRECT_MESSAGE` |
| `message_history` | Yes | Uses `list_messages` |

## Resource Names

Google Chat uses resource names like `spaces/SPACE_ID/messages/MESSAGE_ID`. ChatSDK extracts the last segment as the ID, so `message.id` returns just `MESSAGE_ID` and `channel_id` is `SPACE_ID`.

Edit, delete, and reaction operations accept either a bare message ID or a full resource name. Full resource names must belong to the same space as the operation's `channel_id`; malformed or cross-space names are rejected before making an API request.

## Cards Rendering

Cards are rendered as Google Chat Card v2 JSON using `CardV2Renderer`.

## Mention Formatting

Google Chat uses the format `<users/USER_ID>`:

```ruby
thread.mention_user("12345")  # => "<users/12345>"
```

## Direct Client Access

```ruby
gchat_adapter = bot.adapter(:gchat)
client = gchat_adapter.client  # Google::Apps::Chat::V1::ChatService::Client
```

## Pub/Sub Events

For apps using [Google Workspace Events](https://developers.google.com/workspace/events) with a Cloud Pub/Sub subscription, configure pushes to the normal Google Chat webhook endpoint shown above. That endpoint verifies the Pub/Sub token and `parse_events` decodes the envelope's base64-encoded `message.data`.

If a custom route calls `parse_pubsub_event` directly, verify the request first. The parser does not authenticate requests:

```ruby
post "/custom/pubsub/gchat" do
  gchat_adapter.verify_request!(request)
  events = gchat_adapter.parse_pubsub_event(request)
  events.each { |event| handle(event) }
  status 200
end
```

The adapter delegates decoded payloads to the same `EventParser` used for direct webhooks.
