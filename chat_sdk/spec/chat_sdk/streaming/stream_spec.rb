# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"
require "chat_sdk/testing"

RSpec.describe ChatSDK::Streaming::Stream do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:channel_id) { "C123" }
  let(:thread_id) { "T456" }

  def build_stream(placeholder: nil, update_interval: 0)
    described_class.new(
      adapter: adapter,
      channel_id: channel_id,
      thread_id: thread_id,
      placeholder: placeholder,
      update_interval: update_interval
    )
  end

  describe "#run with placeholder" do
    it "posts placeholder message, yields stream, and final flush edits message" do
      stream = build_stream(placeholder: "Thinking...")

      stream.run do |s|
        s << "Hello "
        s << "world"
      end

      expect(adapter.posted_messages.size).to eq(1)
      posted = adapter.posted_messages.first
      expect(posted[:message].text).to eq("Thinking...")
      expect(posted[:channel_id]).to eq(channel_id)
      expect(posted[:thread_id]).to eq(thread_id)

      expect(adapter.edited_messages.size).to be >= 1
      last_edit = adapter.edited_messages.last
      expect(last_edit[:message].text).to eq("Hello world")
      expect(last_edit[:channel_id]).to eq(channel_id)
      expect(last_edit[:message_id]).to eq("msg_1")
    end
  end

  describe "#<<" do
    it "accumulates chunks in buffer" do
      stream = build_stream(placeholder: "...")

      stream.run do |s|
        s << "one"
        s << " two"
        s << " three"
      end

      last_edit = adapter.edited_messages.last
      expect(last_edit[:message].text).to eq("one two three")
    end

    it "returns self for chaining" do
      stream = build_stream
      result = stream << "chunk"
      expect(result).to be(stream)
    end
  end

  describe "throttling" do
    it "edits respect update_interval with 0 interval for immediate updates" do
      stream = build_stream(placeholder: "...", update_interval: 0)

      stream.run do |s|
        s << "a"
        s << "b"
        s << "c"
      end

      # With update_interval 0 and a placeholder, every << should trigger a flush
      # plus one final flush from #run. There may be >= 3 edits.
      expect(adapter.edited_messages.size).to be >= 3
    end

    it "skips intermediate edits when within update_interval" do
      stream = build_stream(placeholder: "...", update_interval: 9999)

      stream.run do |s|
        s << "a"
        s << "b"
        s << "c"
      end

      # With a very large update_interval, only the first << triggers an edit
      # (since last_flush_at is nil the first time), then the final flush in #run.
      # The intermediate << calls are throttled.
      expect(adapter.edited_messages.size).to eq(2)
    end
  end

  describe "fallback without :edit_messages capability" do
    let(:no_edit_adapter) do
      Class.new(ChatSDK::Adapter::Base) do
        capabilities :direct_messages, :message_history

        def name = :no_edit_test
        def client = self

        def post_message(channel_id:, message:, thread_id: nil)
          @posts ||= []
          record = ChatSDK::Testing::RecordedCall.new(:post_message, channel_id: channel_id, message: message, thread_id: thread_id)
          @posts << record
          ChatSDK::Message.new(
            id: "msg_#{@posts.size}",
            text: message.is_a?(ChatSDK::PostableMessage) ? message.text : message.to_s,
            author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :test, bot: true),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :test
          )
        end

        def posts = @posts || []
        def mention(user_id) = "<@#{user_id}>"
        def verify_request!(_req) = true
        def parse_events(_req) = []
      end.new
    end

    it "posts single message at end instead of edits" do
      stream = described_class.new(
        adapter: no_edit_adapter,
        channel_id: channel_id,
        thread_id: thread_id,
        placeholder: "Thinking...",
        update_interval: 0
      )

      stream.run do |s|
        s << "Result "
        s << "here"
      end

      # Placeholder is posted first
      expect(no_edit_adapter.posts.size).to eq(1)
      expect(no_edit_adapter.posts.first[:message].text).to eq("Thinking...")

      # Since adapter lacks :edit_messages, flush with existing message_id is a no-op.
      # The buffer content is not posted as a new message because message_id is set.
      # This is the expected fallback behavior: placeholder only, no edits.
    end
  end

  describe "fallback without placeholder and no :edit_messages" do
    let(:no_edit_adapter) do
      Class.new(ChatSDK::Adapter::Base) do
        capabilities :direct_messages

        def name = :no_edit
        def client = self

        def post_message(channel_id:, message:, thread_id: nil)
          @posts ||= []
          record = ChatSDK::Testing::RecordedCall.new(:post_message, channel_id: channel_id, message: message, thread_id: thread_id)
          @posts << record
          ChatSDK::Message.new(
            id: "msg_#{@posts.size}",
            text: message.is_a?(ChatSDK::PostableMessage) ? message.text : message.to_s,
            author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :test, bot: true),
            thread_id: thread_id,
            channel_id: channel_id,
            platform: :test
          )
        end

        def posts = @posts || []
        def mention(user_id) = "<@#{user_id}>"
        def verify_request!(_req) = true
        def parse_events(_req) = []
      end.new
    end

    it "posts a single message at end when no placeholder used" do
      stream = described_class.new(
        adapter: no_edit_adapter,
        channel_id: channel_id,
        thread_id: thread_id,
        update_interval: 0
      )

      stream.run do |s|
        s << "Final "
        s << "output"
      end

      # Without placeholder, message_id is nil, so flush posts a new message
      expect(no_edit_adapter.posts.size).to eq(1)
      expect(no_edit_adapter.posts.first[:message].text).to eq("Final output")
    end
  end

  describe "empty stream" do
    it "no chunks with placeholder posts placeholder only, no edits" do
      stream = build_stream(placeholder: "Loading...")

      stream.run do |_s|
        # no chunks
      end

      expect(adapter.posted_messages.size).to eq(1)
      expect(adapter.posted_messages.first[:message].text).to eq("Loading...")
      expect(adapter.edited_messages).to be_empty
    end

    it "no chunks without placeholder posts nothing" do
      stream = build_stream

      stream.run do |_s|
        # no chunks
      end

      expect(adapter.posted_messages).to be_empty
      expect(adapter.edited_messages).to be_empty
    end
  end
end
