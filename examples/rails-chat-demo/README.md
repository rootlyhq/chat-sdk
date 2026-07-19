# Rails Chat Demo

A real-time web chat UI powered by ChatSDK, ActionCable, Turbo Streams, Stimulus, and Tailwind CSS. No external API keys needed — runs entirely locally.

## Quick Start

```bash
cd examples/rails-chat-demo
bundle install
bin/rails db:prepare
bin/dev
```

Open [http://localhost:3000](http://localhost:3000) and start chatting.

## What it does

| Message | Bot Response |
|---------|-------------|
| `hello` | "Hello Guest! You said: hello" |
| `deploy to production` | Echo + a rich card with Approve/Reject buttons |
| Anything else | Echoes your message |

Messages appear in real-time — no page reload. The bot responds instantly via ActionCable broadcast.

## Stack

| Layer | Tech |
|-------|------|
| Backend | Rails 8, Ruby 4, Puma |
| Real-time | ActionCable (async adapter) |
| Frontend | Stimulus controller + vanilla JS |
| Updates | ActionCable broadcast (Turbo-compatible) |
| Styling | Tailwind CSS 4 |
| State | ChatSDK::State::Memory (in-process) |

## Architecture

```
Browser
  ↓ ActionCable WebSocket
ChatChannel#receive
  ↓ Broadcast user message as HTML partial
  ↓ Build ChatSDK::Events::Mention
  ↓ ChatBot.instance.dispatch(event)
Bot handler fires
  ↓ thread.post("reply")
  ↓ Web adapter renders _message.html.erb partial
  ↓ ActionCable.server.broadcast(html)
Browser
  ↓ Stimulus controller inserts HTML into DOM
```

## Key Files

| File | Purpose |
|------|---------|
| `config/initializers/chat_sdk.rb` | Web adapter + bot handlers |
| `app/channels/chat_channel.rb` | ActionCable channel (receive + broadcast) |
| `app/javascript/controllers/chat_controller.js` | Stimulus controller (WebSocket + send) |
| `app/views/chat/index.html.erb` | Chat UI container |
| `app/views/chat/_message.html.erb` | Message bubble partial (bot vs user) |
| `app/controllers/chat_controller.rb` | Simple index action |

## Customization

**Add more handlers** in `config/initializers/chat_sdk.rb`:

```ruby
bot.on_new_message(/help/i) do |thread, message|
  thread.post("Available commands: deploy, help, status")
end

bot.on_action("deploy_approve") do |event|
  event.thread.post("Deploy approved!")
end
```

**Connect to Slack** — add `chat_sdk-slack` to the Gemfile and register a second adapter:

```ruby
bot = ChatSDK::Chat.new(
  user_name: "demo-bot",
  adapters: {
    web: ChatSDK::Web::Adapter.new,
    slack: ChatSDK::Slack::Adapter.new
  },
  state: ChatSDK::State::Memory.new
)
```

Same handlers work on both web and Slack — write once, deploy everywhere.
