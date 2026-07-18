# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "rack"

RSpec.describe "Integration: full stack end-to-end" do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }

  describe "mention → reply → action → reply" do
    it "handles a full conversation flow" do
      mentions = []
      bot.on_new_mention do |thread, msg|
        mentions << msg.text
        thread.subscribe
        thread.post("Got: #{msg.text}")
      end

      bot.on_action("btn:ack") do |event|
        event.thread.post("Acked: #{event.value}")
      end

      adapter.simulate_mention(bot, text: "help me", channel_id: "C001", thread_id: "T001")

      expect(mentions).to eq(["help me"])
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].text).to eq("Got: help me")

      adapter.simulate_action(bot, action_id: "btn:ack", value: "incident-42", channel_id: "C001", thread_id: "T001")

      expect(adapter.posted_messages.size).to eq(2)
      expect(adapter.posted_messages.last[:message].text).to eq("Acked: incident-42")
    end
  end

  describe "thread subscribe + state persistence" do
    it "persists subscription and state across dispatches" do
      bot.on_new_mention do |thread, _msg|
        thread.subscribe
        thread.set_state({count: 1})
      end

      bot.on_subscribed_message do |thread, _msg|
        current = thread.state
        thread.set_state({count: current[:count] + 1})
        thread.post("Count: #{current[:count] + 1}")
      end

      adapter.simulate_mention(bot, text: "start", channel_id: "C1", thread_id: "T1")

      event = ChatSDK::Events::SubscribedMessage.new(
        message: ChatSDK::Message.new(id: "m2", text: "follow up", author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test),
        thread_id: "T1", channel_id: "C1", platform: :test, adapter_name: :test
      )
      bot.dispatch(event, adapter_name: :test)

      expect(adapter.posted_messages.last[:message].text).to eq("Count: 2")
    end
  end

  describe "cards DSL → post → verify structure" do
    it "posts a card and preserves AST structure" do
      card = ChatSDK.card(title: "Incident #42", subtitle: "SEV1") do
        text "Database CPU at 98%"
        fields do
          field "Service", "postgres"
          field "On-call", "@quentin"
        end
        divider
        actions do
          button "Ack", id: "btn:ack", style: :primary, value: "42"
          link_button "Runbook", url: "https://example.com/runbook"
          select id: "severity", placeholder: "Severity" do
            option "SEV1", value: "sev1"
            option "SEV2", value: "sev2"
          end
        end
      end

      expect(card.type).to eq(:card)
      expect(card.attributes[:title]).to eq("Incident #42")
      expect(card.children.size).to eq(4)
      expect(card.children.map(&:type)).to eq(%i[text fields divider actions])

      actions = card.children.last
      expect(actions.children.size).to eq(3)
      expect(actions.children.map(&:type)).to eq(%i[button link_button select])

      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: bot)
      thread.post(card)

      posted = adapter.posted_messages.last[:message]
      expect(posted.card?).to be true
      expect(posted.card).to eq(card)
      expect(posted.text).to include("Database CPU")
    end
  end

  describe "streaming" do
    it "streams chunks via progressive edit" do
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: bot)

      thread.post_stream(placeholder: "Thinking...") do |stream|
        stream << "Hello "
        stream << "world!"
      end

      expect(adapter.posted_messages.size).to be >= 1
      expect(adapter.edited_messages.size).to be >= 1
    end
  end

  describe "AI message conversion" do
    it "converts message history to AI format" do
      messages = [
        ChatSDK::Message.new(id: "1", text: "Debug this error", timestamp: "1",
          author: ChatSDK::Author.new(id: "U1", name: "quentin", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test),
        ChatSDK::Message.new(id: "2", text: "Checking logs now", timestamp: "2",
          author: ChatSDK::Author.new(id: "bot", name: "rootly-bot", platform: :test, bot: true),
          thread_id: "T1", channel_id: "C1", platform: :test),
        ChatSDK::Message.new(id: "3", text: "", timestamp: "3",
          author: ChatSDK::Author.new(id: "U1", name: "quentin", platform: :test),
          thread_id: "T1", channel_id: "C1", platform: :test)
      ]

      ai_msgs = ChatSDK::AI.to_ai_messages(messages, include_names: true)

      expect(ai_msgs.size).to eq(2)
      expect(ai_msgs[0]).to eq({role: "user", content: "[quentin]: Debug this error"})
      expect(ai_msgs[1]).to eq({role: "assistant", content: "Checking logs now"})
    end
  end

  describe "AI tool executor" do
    it "dispatches tool calls through domain objects" do
      executor = ChatSDK::AI.create_executor(chat: bot)

      result = executor.execute(:post_message, {adapter_name: "test", channel_id: "C1", text: "Hello from AI"})
      expect(result[:text]).to eq("Hello from AI")
      expect(adapter.posted_messages.size).to eq(1)

      result = executor.execute(:send_direct_message, {adapter_name: "test", user_id: "U1", text: "DM from AI"})
      expect(result[:channel_id]).to eq("dm_U1")
      expect(adapter.posted_messages.size).to eq(2)
    end
  end

  describe "multiple event types" do
    it "handles reactions and slash commands" do
      reactions = []
      commands = []

      bot.on_reaction(%w[fire]) { |event| reactions << event.emoji }
      bot.on_slash_command("/deploy") { |event| commands << event.text }

      adapter.simulate_reaction(bot, emoji: "fire", channel_id: "C1", thread_id: "T1")
      adapter.simulate_slash_command(bot, command: "/deploy", text: "production")

      expect(reactions).to eq(["fire"])
      expect(commands).to eq(["production"])
    end
  end

  describe "webhook endpoint" do
    it "processes events through the Rack endpoint" do
      received = []
      bot.on_new_mention { |_thread, msg| received << msg.text }

      endpoint = bot.webhooks[:test]
      expect(endpoint).to be_a(ChatSDK::Webhook::Endpoint)

      env = {"rack.input" => StringIO.new("{}")}
      status, = endpoint.call(env)
      expect(status).to eq(200)
    end
  end

  describe "escape hatches" do
    it "allows direct adapter access at all 3 tiers" do
      # Tier 1: normalized
      thread = ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: bot)
      thread.post("tier 1")

      # Tier 2: adapter contract
      bot.adapter(:test).post_message(
        channel_id: "C2",
        message: ChatSDK::PostableMessage.new(text: "tier 2")
      )

      # Tier 3: raw client
      expect(bot.adapter(:test).client).to eq(adapter)

      expect(adapter.posted_messages.size).to eq(2)
      expect(adapter.posted_messages[0][:channel_id]).to eq("C1")
      expect(adapter.posted_messages[1][:channel_id]).to eq("C2")
    end
  end
end
