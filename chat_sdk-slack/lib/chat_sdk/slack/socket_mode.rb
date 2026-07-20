# frozen_string_literal: true

module ChatSDK
  module Slack
    # Implements Slack Socket Mode: receives events over a WebSocket instead of
    # incoming HTTP webhooks. Useful for local development, firewalled environments,
    # or any setup that cannot expose a public URL.
    #
    # Requires the optional `faye-websocket` gem and an app-level token (xapp-*).
    #
    # Usage:
    #   adapter.start_socket_mode(app_token: "xapp-...") do |event|
    #     # event is a ChatSDK::Events::* instance
    #   end
    class SocketMode
      PING_INTERVAL = 30

      attr_reader :app_token, :bot_client

      def initialize(app_token:, bot_client:)
        @app_token = app_token
        @bot_client = bot_client
        @running = false
      end

      def start(&block)
        raise ArgumentError, "start requires a block" unless block

        load_websocket_driver!

        @running = true
        while @running
          url = obtain_websocket_url
          run_connection(url, &block)
        end
      end

      def stop
        @running = false
        @ws&.close
      end

      private

      def load_websocket_driver!
        require "faye/websocket"
      rescue LoadError
        raise ChatSDK::ConfigurationError,
          "Slack Socket Mode requires the 'faye-websocket' gem. " \
          "Add gem 'faye-websocket' to your Gemfile."
      end

      def obtain_websocket_url
        # apps.connections.open must be called with the app-level token, not the bot token
        app_client = ::Slack::Web::Client.new(token: @app_token)
        response = app_client.apps_connections_open
        response["url"]
      end

      def run_connection(url, &block)
        EM.run do
          @ws = Faye::WebSocket::Client.new(url, nil, ping: PING_INTERVAL)

          @ws.on :message do |ws_event|
            handle_message(ws_event, &block)
          end

          @ws.on :close do |_event|
            @ws = nil
            EM.stop
          end
        end
      rescue
        # Let transient errors trigger a reconnect rather than crashing the loop
        raise unless @running
      end

      def handle_message(ws_event, &block)
        data = JSON.parse(ws_event.data)

        # Acknowledge the envelope so Slack doesn't retry
        acknowledge(data["envelope_id"]) if data["envelope_id"]

        payload = data["payload"]
        return unless payload

        # Socket Mode wraps Events API payloads in an envelope. The inner payload
        # matches the same structure our EventParser already handles from webhooks.
        #
        # Envelope types:
        #   "events_api"       -> payload is an event_callback body
        #   "interactive"      -> payload is a block_actions / view_submission body
        #   "slash_commands"    -> payload is a slash command body
        events = EventParser.parse(payload)
        events.each { |event| block.call(event) }
      rescue JSON::ParserError
        # Ignore malformed frames (e.g. pong/control frames)
      end

      def acknowledge(envelope_id)
        return unless envelope_id && @ws

        @ws.send(JSON.generate({envelope_id: envelope_id}))
      end
    end
  end
end
