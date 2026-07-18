# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::AI::ToolExecutor do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }
  let(:executor) { described_class.new(chat: chat) }

  describe "#execute" do
    it "raises on unknown tool" do
      expect { executor.execute(:nonexistent, {}) }
        .to raise_error(ChatSDK::Error, /Unknown tool/)
    end

    it "executes post_message" do
      result = executor.execute(:post_message, {adapter_name: "test", channel_id: "C1", text: "hello"})
      expect(result[:text]).to eq("hello")
      expect(result[:id]).to be_a(String)
      expect(adapter.posted_messages.size).to eq(1)
    end

    it "executes post_message with string keys" do
      result = executor.execute("post_message", {"adapter_name" => "test", "channel_id" => "C1", "text" => "hello"})
      expect(result[:text]).to eq("hello")
    end

    it "executes post_message to thread" do
      result = executor.execute(:post_message, {adapter_name: "test", channel_id: "C1", thread_id: "T1", text: "reply"})
      expect(result[:text]).to eq("reply")
      expect(adapter.posted_messages.last[:thread_id]).to eq("T1")
    end

    it "executes send_direct_message" do
      result = executor.execute(:send_direct_message, {adapter_name: "test", user_id: "U1", text: "hi"})
      expect(result[:channel_id]).to eq("dm_U1")
      expect(adapter.dm_channels.size).to eq(1)
    end

    it "executes edit_message" do
      result = executor.execute(:edit_message, {adapter_name: "test", channel_id: "C1", message_id: "M1", text: "updated"})
      expect(result[:success]).to be true
      expect(adapter.edited_messages.size).to eq(1)
    end

    it "executes delete_message" do
      result = executor.execute(:delete_message, {adapter_name: "test", channel_id: "C1", message_id: "M1"})
      expect(result[:success]).to be true
      expect(adapter.deleted_messages.size).to eq(1)
    end

    it "executes add_reaction" do
      result = executor.execute(:add_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_added.size).to eq(1)
    end

    it "executes remove_reaction" do
      result = executor.execute(:remove_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_removed.size).to eq(1)
    end

    it "executes start_typing" do
      result = executor.execute(:start_typing, {adapter_name: "test", channel_id: "C1"})
      expect(result[:success]).to be true
      expect(adapter.typing_started.size).to eq(1)
    end

    it "executes fetch_messages" do
      result = executor.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"})
      expect(result).to eq([])
    end

    it "executes fetch_thread" do
      result = executor.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1", thread_id: "T1"})
      expect(result).to eq([])
    end
  end
end
