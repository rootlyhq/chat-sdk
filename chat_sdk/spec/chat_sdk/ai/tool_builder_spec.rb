# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"
require "chat_sdk/testing"

RSpec.describe ChatSDK::AI::ToolBuilder do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {test: adapter}, state: state) }

  describe "#build" do
    it "builds reader preset with only read tools" do
      tools = described_class.new(chat: chat, preset: :reader).build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread])
    end

    it "builds messenger preset with read, post, DM, react, and typing tools" do
      tools = described_class.new(chat: chat, preset: :messenger).build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread post_message send_direct_message add_reaction start_typing])
    end

    it "builds moderator preset with edit and delete tools" do
      tools = described_class.new(chat: chat, preset: :moderator).build
      expect(tools.keys).to include(:edit_message, :delete_message, :remove_reaction)
    end

    it "marks read-only tools as not requiring approval" do
      tools = described_class.new(chat: chat, preset: :messenger, require_approval: true).build
      expect(tools[:fetch_messages][:requires_approval]).to be false
      expect(tools[:fetch_thread][:requires_approval]).to be false
    end

    it "marks write tools as requiring approval when enabled" do
      tools = described_class.new(chat: chat, preset: :messenger, require_approval: true).build
      expect(tools[:post_message][:requires_approval]).to be true
      expect(tools[:send_direct_message][:requires_approval]).to be true
      expect(tools[:add_reaction][:requires_approval]).to be true
    end

    it "disables approval for write tools when require_approval is false" do
      tools = described_class.new(chat: chat, preset: :messenger, require_approval: false).build
      expect(tools[:post_message][:requires_approval]).to be false
    end

    it "raises on unknown preset" do
      expect { described_class.new(chat: chat, preset: :unknown) }
        .to raise_error(ChatSDK::ConfigurationError, /Unknown preset/)
    end

    it "accepts string preset and converts to symbol" do
      tools = described_class.new(chat: chat, preset: "reader").build
      expect(tools.keys).to eq(%i[fetch_messages fetch_thread])
    end

    it "includes description and parameters for each tool" do
      tools = described_class.new(chat: chat, preset: :reader).build
      tools.each_value do |defn|
        expect(defn).to have_key(:description)
        expect(defn).to have_key(:parameters)
        expect(defn[:parameters]).to have_key(:properties)
        expect(defn[:parameters]).to have_key(:required)
      end
    end
  end

  describe "#execute" do
    let(:builder) { described_class.new(chat: chat, preset: :moderator) }

    it "raises on unknown tool" do
      expect { builder.execute(:nonexistent, {}) }
        .to raise_error(ChatSDK::Error, /Unknown tool/)
    end

    it "executes post_message" do
      result = builder.execute(:post_message, {adapter_name: "test", channel_id: "C1", text: "hello"})
      expect(result[:text]).to eq("hello")
      expect(result[:id]).to be_a(String)
      expect(adapter.posted_messages.size).to eq(1)
    end

    it "executes post_message with string keys" do
      result = builder.execute("post_message", {"adapter_name" => "test", "channel_id" => "C1", "text" => "hello"})
      expect(result[:text]).to eq("hello")
    end

    it "executes send_direct_message" do
      result = builder.execute(:send_direct_message, {adapter_name: "test", user_id: "U1", text: "hi"})
      expect(result[:channel_id]).to eq("dm_U1")
      expect(adapter.dm_channels.size).to eq(1)
    end

    it "executes edit_message" do
      result = builder.execute(:edit_message, {adapter_name: "test", channel_id: "C1", message_id: "M1", text: "updated"})
      expect(result[:success]).to be true
      expect(adapter.edited_messages.size).to eq(1)
    end

    it "executes delete_message" do
      result = builder.execute(:delete_message, {adapter_name: "test", channel_id: "C1", message_id: "M1"})
      expect(result[:success]).to be true
      expect(adapter.deleted_messages.size).to eq(1)
    end

    it "executes add_reaction" do
      result = builder.execute(:add_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_added.size).to eq(1)
    end

    it "executes remove_reaction" do
      result = builder.execute(:remove_reaction, {adapter_name: "test", channel_id: "C1", message_id: "M1", emoji: "thumbsup"})
      expect(result[:success]).to be true
      expect(adapter.reactions_removed.size).to eq(1)
    end

    it "executes start_typing" do
      result = builder.execute(:start_typing, {adapter_name: "test", channel_id: "C1"})
      expect(result[:success]).to be true
      expect(adapter.typing_started.size).to eq(1)
    end

    it "executes fetch_messages" do
      result = builder.execute(:fetch_messages, {adapter_name: "test", channel_id: "C1"})
      expect(result).to eq([])
    end

    it "executes fetch_thread" do
      result = builder.execute(:fetch_thread, {adapter_name: "test", channel_id: "C1", thread_id: "T1"})
      expect(result).to eq([])
    end
  end
end
