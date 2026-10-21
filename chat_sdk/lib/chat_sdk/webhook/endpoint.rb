# frozen_string_literal: true

module ChatSDK
  module Webhook
    class Endpoint
      attr_reader :chat, :adapter, :adapter_name

      def initialize(chat:, adapter:, adapter_name:)
        @chat = chat
        @adapter = adapter
        @adapter_name = adapter_name
      end

      def call(env)
        current_event = nil
        request = Rack::Request.new(env) if defined?(Rack)

        adapter.verify_request!(request || env)

        ack = adapter.ack_response(request || env)
        return ack if ack

        events = adapter.parse_events(request || env)
        events.each do |event|
          current_event = event
          chat.dispatch(event, adapter_name: adapter_name)
        end

        response = if webhook_response_accepts_request?
          adapter.webhook_response(events, request || env)
        else
          adapter.webhook_response(events)
        end
        return response if response

        [200, {"content-type" => "text/plain"}, [""]]
      rescue ChatSDK::SignatureVerificationError => e
        ChatSDK::Log.warn("Signature verification failed: #{e.message}")
        [401, {"content-type" => "text/plain"}, ["Unauthorized"]]
      rescue => e
        chat.error_reporter.report(
          e,
          "Webhook error",
          source: :webhook,
          adapter: adapter_name,
          event_type: current_event&.type,
          thread_id: current_event&.respond_to?(:thread_id) ? current_event.thread_id : nil,
          channel_id: current_event&.respond_to?(:channel_id) ? current_event.channel_id : nil
        )
        # Platforms retry non-2xx responses, which can repeat handler side effects.
        # Logging and on_error surface failures without causing a redelivery.
        [200, {"content-type" => "text/plain"}, [""]]
      end

      private

      def webhook_response_accepts_request?
        parameters = adapter.method(:webhook_response).parameters
        parameters.any? { |type, _| type == :rest } ||
          parameters.count { |type, _| %i[req opt].include?(type) } > 1
      end
    end
  end
end
