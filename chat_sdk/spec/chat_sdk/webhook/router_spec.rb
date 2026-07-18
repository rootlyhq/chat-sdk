# frozen_string_literal: true

require_relative "../../../../spec/spec_helper"

RSpec.describe ChatSDK::Webhook::Router do
  let(:adapter) { ChatSDK::Testing::FakeAdapter.new }
  let(:state) { ChatSDK::State::Memory.new }
  let(:chat) { ChatSDK::Chat.new(user_name: "test-bot", adapters: {slack: adapter, teams: adapter}, state: state) }
  let(:router) { described_class.new(chat, {slack: adapter, teams: adapter}) }

  def rack_env(path)
    {"PATH_INFO" => path, "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new("")}
  end

  describe "routing to adapters" do
    it "routes POST /slack to the slack adapter's endpoint" do
      status, _headers, _body = router.call(rack_env("/slack"))
      expect(status).to eq(200)
    end

    it "routes POST /teams to the teams adapter's endpoint" do
      status, _headers, _body = router.call(rack_env("/teams"))
      expect(status).to eq(200)
    end
  end

  describe "unknown adapter" do
    it "returns 404 for unknown adapter path" do
      status, headers, body = router.call(rack_env("/unknown"))
      expect(status).to eq(404)
      expect(headers).to eq({"content-type" => "text/plain"})
      expect(body).to eq(["Unknown adapter: unknown"])
    end
  end

  describe "event dispatching" do
    it "dispatches events through the Chat instance" do
      event = ChatSDK::Events::Mention.new(
        message: ChatSDK::Message.new(
          id: "evt_1",
          text: "hello from webhook",
          author: ChatSDK::Author.new(id: "U1", name: "user", platform: :test),
          thread_id: "T1",
          channel_id: "C1",
          platform: :test
        ),
        thread_id: "T1",
        channel_id: "C1",
        platform: :test,
        adapter_name: :slack
      )

      allow(adapter).to receive(:parse_events).and_return([event])

      received = nil
      chat.on_new_mention { |_thread, msg| received = msg.text }

      router.call(rack_env("/slack"))

      expect(received).to eq("hello from webhook")
    end
  end
end
