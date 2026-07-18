# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"
require "rack/test"

RSpec.describe ChatSDK::Webhook::Endpoint do
  include Rack::Test::Methods

  let(:test_adapter) do
    Class.new(ChatSDK::Adapter::Base) do
      capabilities :edit_messages, :direct_messages, :message_history

      def name = :webhook_test
      def client = self
      def verify_request!(_req) = true
      def ack_response(_req) = nil
      def parse_events(_req) = []

      def post_message(channel_id:, message:, thread_id: nil)
        ChatSDK::Message.new(
          id: "msg_1",
          text: message.is_a?(ChatSDK::PostableMessage) ? message.text : message.to_s,
          author: ChatSDK::Author.new(id: "bot", name: "bot", platform: :test, bot: true),
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :test
        )
      end

      def mention(user_id) = "<@#{user_id}>"
    end.new
  end

  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {webhook_test: test_adapter}, state: state) }
  let(:endpoint) { described_class.new(chat: chat, adapter: test_adapter, adapter_name: :webhook_test) }

  let(:app) { endpoint }

  let(:env) do
    Rack::MockRequest.env_for("/webhook", method: "POST", input: '{"event":"test"}')
  end

  describe "successful dispatch" do
    it "parses events from adapter and dispatches each to chat" do
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(
          id: "evt_1",
          text: "hello",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1",
          channel_id: "C1",
          platform: :test
        ),
        thread_id: "T1",
        channel_id: "C1",
        platform: :test,
        adapter_name: :webhook_test
      )

      allow(test_adapter).to receive(:parse_events).and_return([event])

      received = nil
      chat.on_new_mention { |_thread, msg| received = msg.text }

      status, _headers, _body = endpoint.call(env)

      expect(status).to eq(200)
      expect(received).to eq("hello")
    end

    it "dispatches multiple events" do
      events = 2.times.map do |i|
        ChatSDK::Events::Mention.new(
          message: ChatSDK::Message.new(
            id: "evt_#{i}",
            text: "msg#{i}",
            author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
            thread_id: "T#{i}",
            channel_id: "C1",
            platform: :test
          ),
          thread_id: "T#{i}",
          channel_id: "C1",
          platform: :test,
          adapter_name: :webhook_test
        )
      end

      allow(test_adapter).to receive(:parse_events).and_return(events)

      received_texts = []
      chat.on_new_mention { |_thread, msg| received_texts << msg.text }

      status, _headers, _body = endpoint.call(env)

      expect(status).to eq(200)
      expect(received_texts).to eq(%w[msg0 msg1])
    end
  end

  describe "signature verification failure" do
    it "returns 401 when adapter raises SignatureVerificationError" do
      allow(test_adapter).to receive(:verify_request!).and_raise(
        ChatSDK::SignatureVerificationError, "bad signature"
      )

      status, _headers, body = endpoint.call(env)

      expect(status).to eq(401)
      expect(body).to eq(["Unauthorized"])
    end
  end

  describe "ack response" do
    it "returns ack response when adapter provides one" do
      ack = [200, {"content-type" => "application/json"}, ['{"challenge":"abc"}']]
      allow(test_adapter).to receive(:ack_response).and_return(ack)

      status, headers, body = endpoint.call(env)

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(body).to eq(['{"challenge":"abc"}'])
    end

    it "skips event parsing when ack is returned" do
      ack = [200, {}, ["ok"]]
      allow(test_adapter).to receive(:ack_response).and_return(ack)
      expect(test_adapter).not_to receive(:parse_events)

      endpoint.call(env)
    end
  end

  describe "handler error" do
    it "does not propagate handler errors and returns 200" do
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(
          id: "evt_1",
          text: "boom",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1",
          channel_id: "C1",
          platform: :test
        ),
        thread_id: "T1",
        channel_id: "C1",
        platform: :test,
        adapter_name: :webhook_test
      )

      allow(test_adapter).to receive(:parse_events).and_return([event])

      chat.on_new_mention { |_thread, _msg| raise "handler exploded" }

      status, _headers, _body = endpoint.call(env)

      expect(status).to eq(200)
    end
  end

  describe "general error handling" do
    it "catches non-signature errors and returns 200" do
      allow(test_adapter).to receive(:parse_events).and_raise(RuntimeError, "something broke")

      status, _headers, _body = endpoint.call(env)

      expect(status).to eq(200)
    end
  end
end
