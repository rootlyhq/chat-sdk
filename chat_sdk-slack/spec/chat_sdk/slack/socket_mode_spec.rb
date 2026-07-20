# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::Slack::SocketMode do
  let(:app_token) { "xapp-test-app-token" }
  let(:bot_client) { instance_double(::Slack::Web::Client) }
  let(:app_client) { instance_double(::Slack::Web::Client) }

  before do
    # Stub the app-level client creation and apps_connections_open
    allow(::Slack::Web::Client).to receive(:new)
      .with(token: app_token)
      .and_return(app_client)
    allow(app_client).to receive(:apps_connections_open)
      .and_return({"url" => "wss://wss-primary.slack.com/link/?ticket=abc123"})
  end

  describe "#start" do
    it "raises ArgumentError without a block" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      allow(socket).to receive(:load_websocket_driver!)

      expect { socket.start }.to raise_error(ArgumentError, /requires a block/)
    end

    it "obtains a websocket URL via apps.connections.open" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      allow(socket).to receive(:load_websocket_driver!)
      allow(socket).to receive(:run_connection) do
        socket.stop
      end

      socket.start { |_event| }

      expect(app_client).to have_received(:apps_connections_open)
    end

    it "reconnects when the WebSocket closes" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      allow(socket).to receive(:load_websocket_driver!)

      call_count = 0
      allow(socket).to receive(:run_connection) do
        call_count += 1
        socket.stop if call_count >= 2
      end

      socket.start { |_event| }

      expect(call_count).to eq(2)
      expect(app_client).to have_received(:apps_connections_open).twice
    end
  end

  describe "#stop" do
    it "sets running to false" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      allow(socket).to receive(:load_websocket_driver!)
      allow(socket).to receive(:run_connection) do
        socket.stop
      end

      socket.start { |_event| }

      expect(socket.instance_variable_get(:@running)).to be false
    end
  end

  describe "message handling" do
    # Test handle_message directly since we can't easily test EM in unit tests
    it "parses event_callback envelopes and yields ChatSDK events" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "env-123",
        "type" => "events_api",
        "payload" => {
          "type" => "event_callback",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "<@B456> hello from socket mode",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      socket.send(:handle_message, ws_event) { |event| collected_events << event }

      expect(collected_events.size).to eq(1)
      event = collected_events.first
      expect(event).to be_a(ChatSDK::Events::Mention)
      expect(event.message.text).to eq("<@B456> hello from socket mode")
      expect(event.message.author.id).to eq("U123")
      expect(event.channel_id).to eq("C789")
    end

    it "parses interactive envelopes (block_actions) and yields Action events" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "env-456",
        "type" => "interactive",
        "payload" => {
          "type" => "block_actions",
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:approve", "value" => "yes"}
          ]
        }
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      socket.send(:handle_message, ws_event) { |event| collected_events << event }

      expect(collected_events.size).to eq(1)
      event = collected_events.first
      expect(event).to be_a(ChatSDK::Events::Action)
      expect(event.action_id).to eq("btn:approve")
      expect(event.value).to eq("yes")
    end

    it "parses slash_commands envelopes and yields SlashCommand events" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "env-789",
        "type" => "slash_commands",
        "payload" => {
          "command" => "/incident",
          "text" => "create outage",
          "user_id" => "U123",
          "channel_id" => "C789",
          "trigger_id" => "T999"
        }
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      socket.send(:handle_message, ws_event) { |event| collected_events << event }

      expect(collected_events.size).to eq(1)
      event = collected_events.first
      expect(event).to be_a(ChatSDK::Events::SlashCommand)
      expect(event.command).to eq("/incident")
      expect(event.text).to eq("create outage")
    end

    it "parses DM message events from socket mode" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "env-dm1",
        "type" => "events_api",
        "payload" => {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "hello via DM",
            "ts" => "1234567890.123456",
            "channel" => "D789",
            "channel_type" => "im"
          }
        }
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      socket.send(:handle_message, ws_event) { |event| collected_events << event }

      expect(collected_events.size).to eq(1)
      expect(collected_events.first).to be_a(ChatSDK::Events::DirectMessage)
      expect(collected_events.first.message.text).to eq("hello via DM")
    end

    it "acknowledges each envelope by sending back the envelope_id" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "ack-me-123",
        "type" => "events_api",
        "payload" => {
          "type" => "event_callback",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "hi",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      ws_mock = double("ws")
      allow(ws_mock).to receive(:send)
      socket.instance_variable_set(:@ws, ws_mock)

      socket.send(:handle_message, ws_event) { |_event| }

      expect(ws_mock).to have_received(:send)
        .with(JSON.generate({envelope_id: "ack-me-123"}))
    end

    it "ignores envelopes without a payload" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      envelope = {
        "envelope_id" => "env-empty",
        "type" => "hello"
      }

      ws_event = double("ws_event", data: JSON.generate(envelope))
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      socket.send(:handle_message, ws_event) { |event| collected_events << event }

      expect(collected_events).to be_empty
    end

    it "ignores malformed JSON frames" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      ws_event = double("ws_event", data: "not-json{{{")
      socket.instance_variable_set(:@ws, double("ws", send: nil))

      collected_events = []
      expect {
        socket.send(:handle_message, ws_event) { |event| collected_events << event }
      }.not_to raise_error

      expect(collected_events).to be_empty
    end
  end

  describe "websocket driver loading" do
    it "raises ConfigurationError when faye-websocket is not installed" do
      socket = described_class.new(app_token: app_token, bot_client: bot_client)
      allow(socket).to receive(:require).with("faye/websocket").and_raise(LoadError)
      allow(socket).to receive(:load_websocket_driver!).and_call_original

      expect { socket.start { |_| } }
        .to raise_error(ChatSDK::ConfigurationError, /faye-websocket/)
    end
  end
end
