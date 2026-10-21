# GitLab Adapter

The GitLab adapter (`chat_sdk-gitlab`) handles issue and merge request notes through the GitLab REST API. It preserves GitLab Markdown, references, and mentions, and renders ChatSDK cards as Markdown.

## Installation

```ruby
gem "chat_sdk"
gem "chat_sdk-gitlab"
```

```ruby
require "chat_sdk"
require "chat_sdk/gitlab"

adapter = ChatSDK::GitLab::Adapter.new(
  token: ENV["GITLAB_TOKEN"],
  webhook_secret: ENV["GITLAB_WEBHOOK_SECRET"],
  bot_user_id: ENV["GITLAB_BOT_USER_ID"],
  bot_username: ENV["GITLAB_BOT_USERNAME"]
)
```

## Configuration

| Option | Environment variable | Required | Description |
| --- | --- | --- | --- |
| `token` | `GITLAB_TOKEN` | Yes | GitLab personal, project, or group access token. |
| `webhook_secret` | `GITLAB_WEBHOOK_SECRET` | One verifier required | Secret token configured on the GitLab webhook. |
| `webhook_signing_token` | `GITLAB_WEBHOOK_SIGNING_TOKEN` | One verifier required | Standard Webhooks signing token; accepts the optional `whsec_` prefix. |
| `api_url` | `GITLAB_API_URL` | No | API base URL. Defaults to `https://gitlab.com/api/v4`. |
| `bot_user_id` | `GITLAB_BOT_USER_ID` | No | Bot's numeric GitLab user ID. If omitted, the adapter lazily calls `GET /user`. |
| `bot_username` | `GITLAB_BOT_USERNAME` | No | Bot username used for mention detection and self-note filtering. Defaults to `gitlab-bot`. |

The adapter requires a token and at least one webhook verifier. When bot identity is incomplete, the adapter lazily looks up `GET /user`; failed lookups are retried on later events.

## Webhook setup

Configure a GitLab project webhook with **Comments** and **Emoji** events and the URL mounted for the `:gitlab` adapter. GitLab sends comment events as `Note Hook` and award changes as `Emoji Hook`.

Standard Webhooks signatures are validated when `webhook-signature` is present and a signing token is configured. Otherwise, the adapter verifies `X-Gitlab-Token` against `webhook_secret`. The signature timestamp is limited to five minutes.

Merge request and issue notes become message events. System, confidential, and bot-authored notes are ignored, as are commit and snippet notes. Mention detection masks Markdown code spans before matching `@bot_username`. GitLab discussion IDs are included in thread IDs when supplied by the webhook.

## Threads and history

Thread IDs use the form `gitlab:{project_id}:{mr|issue}:{iid}` with an optional `:{discussion_id}` suffix. Channel IDs use `gitlab:{project_id}`. Outbound operations validate these IDs and require numeric note IDs.

`fetch_messages` supports a noteable's comments and a specific discussion. Noteable comment pagination uses GitLab's `x-next-page` response header as the next cursor. Channel-wide aggregation across every issue and merge request is not available through this API.

## Capabilities

| Capability | Supported |
| --- | --- |
| Posting, editing, and deleting notes | Yes |
| Reactions | Yes |
| Thread-level message history | Yes |
| Typing indicator | No-op |
| Cards | Markdown fallback |
| Files, direct messages, modals, and streaming | No |

The adapter's `mention(user)` helper formats the supplied GitLab username as `@username`. `start_typing` is intentionally a no-op because GitLab does not expose a typing-indicator API.
