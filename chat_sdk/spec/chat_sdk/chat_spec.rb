# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Chat do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) { described_class.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }

  describe "initialization" do
    it "creates with valid config" do
      expect(bot.config.user_name).to eq("test-bot")
    end

    it "raises on missing user_name" do
      expect {
        described_class.new(user_name: "", adapters: {test: adapter}, state: state)
      }.to raise_error(ChatSDK::ConfigurationError)
    end

    it "raises on missing adapters" do
      expect {
        described_class.new(user_name: "bot", adapters: {}, state: state)
      }.to raise_error(ChatSDK::ConfigurationError)
    end
  end

  describe "#adapter" do
    it "returns registered adapter" do
      expect(bot.adapter(:test)).to eq(adapter)
    end

    it "raises for unknown adapter" do
      expect { bot.adapter(:unknown) }.to raise_error(ChatSDK::ConfigurationError)
    end
  end

  describe "#channel" do
    it "returns a Channel" do
      ch = bot.channel("C123")
      expect(ch).to be_a(ChatSDK::Channel)
      expect(ch.id).to eq("C123")
    end
  end

  describe "#on_new_mention + dispatch" do
    it "fires handler when mention dispatched" do
      received = nil
      bot.on_new_mention { |thread, msg| received = msg.text }
      adapter.simulate_mention(bot, text: "hello bot")
      expect(received).to eq("hello bot")
    end

    it "provides a thread with subscribe capability" do
      thread_ref = nil
      bot.on_new_mention { |thread, _msg|
        thread_ref = thread
        thread.subscribe
      }
      adapter.simulate_mention(bot, text: "hi")
      expect(thread_ref).to be_a(ChatSDK::Thread)
    end
  end

  describe "#on_action" do
    it "fires handler for matching action_id" do
      received_value = nil
      bot.on_action("btn:click") { |event| received_value = event.value }
      adapter.simulate_action(bot, action_id: "btn:click", value: "42")
      expect(received_value).to eq("42")
    end

    it "does not fire for non-matching action_id" do
      fired = false
      bot.on_action("btn:other") { |_event| fired = true }
      adapter.simulate_action(bot, action_id: "btn:click", value: "42")
      expect(fired).to be false
    end
  end

  describe "#on_reaction" do
    it "fires handler for matching emoji" do
      received_emoji = nil
      bot.on_reaction(%w[fire]) { |event| received_emoji = event.emoji }
      adapter.simulate_reaction(bot, emoji: "fire")
      expect(received_emoji).to eq("fire")
    end
  end

  describe "#on_slash_command" do
    it "fires handler for matching command" do
      received_text = nil
      bot.on_slash_command("/deploy") { |event| received_text = event.text }
      adapter.simulate_slash_command(bot, command: "/deploy", text: "production")
      expect(received_text).to eq("production")
    end
  end

  describe "#on_new_mention posting" do
    it "posts response through adapter" do
      bot.on_new_mention { |thread, _msg| thread.post("got it") }
      adapter.simulate_mention(bot, text: "hello")
      expect(adapter.posted_messages.size).to be >= 1
      last = adapter.posted_messages.last
      expect(last[:message].text).to eq("got it")
    end
  end

  describe "#webhooks" do
    it "returns webhook accessor" do
      expect(bot.webhooks).to be_a(ChatSDK::WebhookAccessor)
    end

    it "returns endpoint for registered adapter" do
      endpoint = bot.webhooks[:test]
      expect(endpoint).to be_a(ChatSDK::Webhook::Endpoint)
    end
  end
end
