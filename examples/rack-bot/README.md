# Rack Bot

A minimal Slack bot running on bare Rack + Puma. No Rails required.

## Setup

```bash
# 1. Install dependencies
bundle install

# 2. Set environment variables
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_SIGNING_SECRET=...

# 3. Start the server
bundle exec rackup -p 3000

# 4. Point your Slack app's event subscription URL to:
#    https://your-host/webhooks/slack
```

## What it does

- Echoes back any @-mention
- Responds to messages containing "deploy" with an interactive card
- Handles Approve / Reject button clicks
