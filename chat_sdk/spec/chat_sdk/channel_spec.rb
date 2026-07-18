# frozen_string_literal: true

require_relative "../../../spec/spec_helper"

RSpec.describe ChatSDK::Channel do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:channel) { described_class.new(id: "C123", adapter: adapter, chat: chat) }

  describe "#post" do
    it "posts through adapter" do
      channel.post("hello channel")
      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].text).to eq("hello channel")
    end
  end

  describe "#thread" do
    it "returns a Thread for the channel" do
      thread = channel.thread("T456")
      expect(thread).to be_a(ChatSDK::Thread)
      expect(thread.id).to eq("T456")
    end

    it "inherits the channel's adapter and chat" do
      thread = channel.thread("T456")
      expect(thread.adapter).to eq(adapter)
      expect(thread.chat).to eq(chat)
    end
  end

  describe "equality" do
    it "equals another channel with the same id" do
      other = described_class.new(id: "C123", adapter: adapter, chat: chat)
      expect(channel).to eq(other)
    end

    it "does not equal a channel with a different id" do
      other = described_class.new(id: "C999", adapter: adapter, chat: chat)
      expect(channel).not_to eq(other)
    end

    it "supports eql? for hash key usage" do
      other = described_class.new(id: "C123", adapter: adapter, chat: chat)
      expect(channel).to eql(other)
    end

    it "produces the same hash for equal channels" do
      other = described_class.new(id: "C123", adapter: adapter, chat: chat)
      expect(channel.hash).to eq(other.hash)
    end
  end
end
