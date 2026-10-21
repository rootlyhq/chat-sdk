# Slack Adapter

The Slack adapter (`chat_sdk-slack`) provides full integration with Slack's Web API and Block Kit.

## Installation

```ruby
# Gemfile
gem "chat_sdk"
gem "chat_sdk-slack"
```

## Configuration

```ruby
require "chat_sdk"
require "chat_sdk/slack"

slack = ChatSDK::Slack::Adapter.new(
  bot_token: ENV["SLACK_BOT_TOKEN"],       # or set SLACK_BOT_TOKEN env var
  signing_secret: ENV["SLACK_SIGNING_SECRET"], # or set SLACK_SIGNING_SECRET env var
  proxy: ENV["HTTPS_PROXY"],               # optional Web API egress proxy
  bot_user_id: ENV["SLACK_BOT_USER_ID"],    # optional bot user ID
  native_streaming: true,                   # use Slack's native streaming API
  stream_segment_max_age: 240              # rotate long streams after 240 seconds
)
```

Both parameters fall back to environment variables if not provided. A signing secret is optional when you provide `webhook_verifier`.

## Native Streaming

The Slack adapter uses `chat.startStream`, `chat.appendStream`, and `chat.stopStream` for eligible `Thread#post_stream` calls. Native streaming requires a thread ID and either a direct-message channel or both recipient user and team IDs. Recipient IDs are derived from the current inbound message when available. If those requirements are not met, or native streaming is disabled, ChatSDK uses its post-and-edit fallback.

Native streams use the same per-request bot token resolution as other API calls: the installation, `with_bot_token`, or the `bot_token` resolver.

`native_streaming:` defaults to `true`. Set it to `false` to always use the fallback. `stream_segment_max_age:` defaults to `240` seconds and controls when long streams rotate into a new Slack message; it must be positive. Set it to `Float::INFINITY` to disable segment rotation.

If Slack rejects the native API before any output has rendered, the adapter falls back to post-and-edit. Unsupported-method errors are remembered by the adapter so later streams use the fallback immediately. Errors after native output has rendered are raised.

Structured task and plan chunks require the Slack app's `assistant:write` scope. Plain markdown text does not need this scope.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SLACK_BOT_TOKEN` | Bot User OAuth Token (starts with `xoxb-`) |
| `SLACK_SIGNING_SECRET` | Signing Secret from your Slack app settings |
| `SLACK_CLIENT_ID` | OAuth client ID for multi-workspace installations |
| `SLACK_CLIENT_SECRET` | OAuth client secret for multi-workspace installations |
| `SLACK_ENCRYPTION_KEY` | Optional 32-byte token encryption key in hex or base64 |
| `SLACK_APP_TOKEN` | App-level token for Socket Mode |
| `HTTPS_PROXY` | Optional HTTP(S) proxy used for Slack Web API and upload requests |
| `SLACK_BOT_USER_ID` | Optional bot user ID used to classify mentions without an `auth.test` lookup |

## Multi-workspace installations

Pass `client_id` and `client_secret`, then provide a state store with `set_state`. Use `handle_oauth_callback` to exchange an OAuth code and save the installation. Workspace installs use the team ID as the storage key. Enterprise Grid organization installs use the enterprise ID; workspace installs in Grid retain their enterprise metadata.

You can load installations from your own store with `installation_provider`. It can be an object with `get_installation(installation_id, enterprise_install:)` or a callable with the same arguments. Return a string- or symbol-keyed hash with `bot_token` and optional `bot_user_id`, or return `nil` when the installation is unavailable. When a provider is set, the adapter does not fall back to its state store.

```ruby
slack = ChatSDK::Slack::Adapter.new(
  client_id: ENV["SLACK_CLIENT_ID"],
  client_secret: ENV["SLACK_CLIENT_SECRET"],
  signing_secret: ENV["SLACK_SIGNING_SECRET"],
  installation_provider: ->(installation_id, enterprise_install:) {
    InstallationStore.get(installation_id, enterprise_install: enterprise_install)
  }
)
```

For a single installation, `bot_token` can be a zero-argument callable. The adapter calls it on each `client` access, so it can return a rotated token. Use `with_bot_token` to scope a token to an out-of-webhook operation:

```ruby
slack.with_bot_token(ENV.fetch("SLACK_BOT_TOKEN"), installation_id: "T123") do
  slack.post_message(channel_id: "C123", message: "Hello")
end
```

Set `encryption_key` or `SLACK_ENCRYPTION_KEY` to encrypt tokens written by `set_installation`. Use a 64-character hex string or a 44-character base64 string that decodes to 32 bytes. Existing plaintext installations remain readable. Re-encrypt stored tokens with the new key before replacing an encryption key; existing ciphertext cannot be decrypted with a different key.

## Webhook verification

`webhook_verifier` can replace the built-in Slack signature check. It receives the Rack request and raw body. Return a truthy value to accept the request, or return a string to accept it and use that string as the body for parsing. When set, it takes precedence over `signing_secret` and `SLACK_SIGNING_SECRET`, and the built-in timestamp check is skipped. Your verifier must authenticate requests and enforce freshness or replay protection.

```ruby
slack = ChatSDK::Slack::Adapter.new(
  bot_token: ENV["SLACK_BOT_TOKEN"],
  webhook_verifier: ->(request, body) { verify_slack_request(request, body) }
)
```

## Slack App Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app.
2. Under **OAuth & Permissions**, add the bot token scopes your app needs:
   - `chat:write` -- Post messages
   - `chat:write.customize` -- Post with custom username/icon
   - `assistant:write` -- Send structured task and plan streaming chunks
   - `reactions:write` -- Add/remove reactions
   - `reactions:read` -- Read reactions
   - `files:write` -- Upload files
   - `im:history` -- Read DM history
   - `channels:history` -- Read channel history
   - `groups:history` -- Read private channel history
3. Install the app to your workspace and copy the Bot User OAuth Token.
4. Under **Event Subscriptions**, enable events and set the Request URL to your webhook endpoint (e.g., `https://your-app.com/webhooks/slack`).
5. Subscribe to bot events: `app_mention`, `message.im`, `reaction_added`, `reaction_removed`.
6. Under **Interactivity & Shortcuts**, enable interactivity and set the Request URL to the same webhook endpoint.
7. Copy the **Signing Secret** from Basic Information.

## Webhook URL

Your webhook endpoint should be:

```
https://your-domain.com/webhooks/slack
```

Mount it in your Rack app:

```ruby
map "/webhooks/slack" do
  run bot.webhooks[:slack]
end
```

The endpoint handles Slack's URL verification challenge automatically.

## Capabilities

The Slack adapter supports all capabilities:

| Capability | Supported |
|------------|-----------|
| `edit_messages` | Yes |
| `delete_messages` | Yes |
| `ephemeral_messages` | Yes |
| `file_uploads` | Yes |
| `reactions` | Yes |
| `modals` | Yes |
| `typing_indicator` | Yes (declared, no-op) |
| `streaming_edit` | Yes |
| `threads` | Yes |
| `direct_messages` | Yes |
| `message_history` | Yes |

Slack native streaming is available through `Thread#post_stream` when its thread and recipient requirements are met; otherwise it falls back to post-and-edit.

## Direct Client Access

Access the underlying `Slack::Web::Client` for platform-specific API calls:

```ruby
slack_adapter = bot.adapter(:slack)
client = slack_adapter.client

# Any slack-ruby-client method
client.users_info(user: "U12345")
client.conversations_list(types: "public_channel")
```

## Cards Rendering

Cards built with `ChatSDK.card` are rendered as Slack Block Kit JSON. The `BlockKitRenderer` handles the translation automatically.

Inbound Slack text normalizes broadcast, user-group, email, and telephone tokens while preserving code spans. Bot mentions are classified from mrkdwn and rich-text blocks when the bot user ID is available. Multi-workspace dispatch uses the team ID for workspace installs and the enterprise ID for organization installs.

File uploads use Slack's `files_upload_v2` API. Block Kit text is truncated to Slack's field limits without splitting markup tokens, entities, or open code fences.

## Message IDs

Slack uses timestamps (`ts`) as message IDs. The `Message#id` returned from `post` and other methods is the `ts` value (e.g., `"1234567890.123456"`).
