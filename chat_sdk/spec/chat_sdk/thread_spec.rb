# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "chat_sdk/testing"

RSpec.describe ChatSDK::Thread do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:bot) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:thread) { described_class.new(id: "T123", channel_id: "C123", adapter: adapter, chat: bot) }

  describe "#subscribe / #subscribed?" do
    it "subscribes and checks" do
      thread.subscribe
      expect(thread.subscribed?).to be true
    end

    it "unsubscribes" do
      thread.subscribe
      thread.unsubscribe
      expect(thread.subscribed?).to be false
    end
  end

  describe "#post" do
    it "posts a string message" do
      thread.post("hello")
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].text).to eq("hello")
    end

    it "posts a card" do
      card = ChatSDK.card(title: "Test") { text "body" }
      thread.post(card)
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].card?).to be true
    end
  end

  describe "#state / #set_state" do
    it "stores and retrieves state" do
      thread.set_state({count: 1})
      expect(thread.state).to eq({count: 1})
    end
  end

  describe "#mention_user" do
    it "returns platform mention syntax" do
      expect(thread.mention_user("U123")).to eq("<@U123>")
    end
  end

  describe "equality" do
    it "equals thread with same id and channel" do
      other = described_class.new(id: "T123", channel_id: "C123", adapter: adapter, chat: bot)
      expect(thread).to eq(other)
    end
  end
end
