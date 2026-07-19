# Rails Chat Demo

A working Rails 8 example showing ChatSDK with ActionCable, Stimulus, and Tailwind.
Messages are sent over WebSocket and bot replies are broadcast as HTML partials.

## Quick start

```bash
# 1. Create a fresh Rails 8 app
rails new my-chat-bot --css tailwind --javascript esbuild
cd my-chat-bot

# 2. Add chat_sdk to your Gemfile
bundle add chat_sdk

# 3. Copy these files into your app:
#    config/initializers/chat_sdk.rb   - adapter, bot setup, handlers
#    app/channels/chat_channel.rb      - ActionCable channel
#    app/controllers/chat_controller.rb
#    app/views/chat/index.html.erb     - chat UI
#    app/views/chat/_message.html.erb  - message bubble partial
#    app/javascript/controllers/chat_controller.js - Stimulus controller

# 4. Add the route
#    root "chat#index"

# 5. Start the server
bin/dev
```

## How it works

1. **Stimulus controller** connects to ActionCable's `ChatChannel` on page load
2. User types a message, Stimulus sends it via `subscription.send()`
3. **ChatChannel** receives the data, broadcasts the user's message as HTML
4. ChatChannel builds a `ChatSDK::Events::Mention` and dispatches it to the bot
5. Bot handlers call `thread.post(...)` which triggers the **Web adapter**
6. The adapter renders the bot's reply partial and broadcasts it via ActionCable
7. Stimulus inserts the HTML into the messages container

## Files

| File | Purpose |
|------|---------|
| `config/initializers/chat_sdk.rb` | Web adapter + bot handlers |
| `app/channels/chat_channel.rb` | ActionCable channel for send/receive |
| `app/controllers/chat_controller.rb` | Renders the chat page |
| `app/views/chat/index.html.erb` | Chat UI with Stimulus bindings |
| `app/views/chat/_message.html.erb` | Single message bubble |
| `app/javascript/controllers/chat_controller.js` | Stimulus + ActionCable client |
| `config/routes.rb` | Routes `root` to the chat page |
