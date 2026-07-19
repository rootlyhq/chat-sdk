# Rack Bot Example

Minimal ChatSDK bot running on plain Rack. No framework, no database — just a Slack webhook handler in 50 lines.

## Setup

1. **Create a Slack app** at [api.slack.com/apps](https://api.slack.com/apps):
   - Enable **Event Subscriptions** (subscribe to `app_mention`)
   - Enable **Interactivity** (for button clicks)
   - Add **Bot Token Scopes**: `chat:write`, `app_mentions:read`
   - Install to your workspace

2. **Configure environment**:
   ```bash
   export SLACK_BOT_TOKEN="xoxb-..."
   export SLACK_SIGNING_SECRET="..."
   ```

3. **Install and run**:
   ```bash
   bundle install
   bundle exec rackup config.ru -p 3000
   ```

4. **Set webhook URL** in Slack app settings:
   - Event Subscriptions → `https://your-domain.com/webhooks/slack`
   - Interactivity → `https://your-domain.com/webhooks/slack`

   For local development, use [ngrok](https://ngrok.com): `ngrok http 3000`

## What it does

| Trigger | Response |
|---------|----------|
| `@bot hello` | Echoes "Hello! You said: hello" |
| `@bot deploy` | Posts a card with Approve/Reject buttons |
| Click "Approve" | Acknowledges the action |

## Files

```
config.ru   ← Bot setup + Rack app (everything in one file)
Gemfile     ← Dependencies (chat_sdk + chat_sdk-slack)
```

## Architecture

```
Slack webhook POST → /webhooks/slack
  → HMAC-SHA256 signature verification
  → Parse Events API / Interactivity payload
  → Dispatch to ChatSDK handler
  → Handler calls thread.post()
  → Slack Web API ← chat.postMessage
```
