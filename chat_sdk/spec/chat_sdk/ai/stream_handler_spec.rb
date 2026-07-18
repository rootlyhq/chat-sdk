# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"
require "chat_sdk/testing"

RSpec.describe ChatSDK::AI::StreamHandler do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:thread) { ChatSDK::Thread.new(id: "T1", channel_id: "C1", adapter: adapter, chat: chat) }

  describe ".stream_to_thread" do
    it "streams an array to the thread" do
      described_class.stream_to_thread(thread, %w[Hello World])
      expect(adapter.posted_messages.size).to be >= 1
    end

    it "streams an Enumerator to the thread" do
      enum = Enumerator.new do |y|
        y << "chunk1"
        y << "chunk2"
      end
      described_class.stream_to_thread(thread, enum)
      expect(adapter.posted_messages.size).to be >= 1
    end

    it "accepts a custom placeholder" do
      described_class.stream_to_thread(thread, ["data"], placeholder: "Loading...")
      first_post = adapter.posted_messages.first
      expect(first_post[:message].text).to eq("Loading...")
    end
  end

  describe "Thread#post_ai_stream" do
    it "delegates to StreamHandler" do
      thread.post_ai_stream(%w[Hello World])
      expect(adapter.posted_messages.size).to be >= 1
    end

    it "passes placeholder option" do
      thread.post_ai_stream(["data"], placeholder: "Working...")
      first_post = adapter.posted_messages.first
      expect(first_post[:message].text).to eq("Working...")
    end
  end
end
