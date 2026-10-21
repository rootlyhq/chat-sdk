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

        response = adapter.webhook_response(events)
        return response if response

        [200, {"content-type" => "text/plain"}, [""]]
      rescue ChatSDK::SignatureVerificationError => e
        ChatSDK::Log.warn("Signature verification failed: #{e.message}")
        [401, {"content-type" => "text/plain"}, ["Unauthorized"]]
      rescue ChatSDK::HandlerExecutorError => e
        chat.error_reporter.report(
          e,
          "Handler executor error",
          **error_context(source: :executor, event: current_event)
        )
        # Platforms redeliver non-2xx responses; handlers did not run in this request, and workers deduplicate already-enqueued events.
        [500, {"content-type" => "text/plain"}, [""]]
      rescue => e
        chat.error_reporter.report(
          e,
          "Webhook error",
          **error_context(source: :webhook, event: current_event)
        )
        # Platforms retry non-2xx responses, which can repeat handler side effects.
        # Logging and on_error surface failures without causing a redelivery.
        [200, {"content-type" => "text/plain"}, [""]]
      end

      private

      def error_context(source:, event:)
        {
          source: source,
          adapter: adapter_name,
          event_type: event&.type,
          thread_id: event&.respond_to?(:thread_id) ? event.thread_id : nil,
          channel_id: event&.respond_to?(:channel_id) ? event.channel_id : nil
        }
      end
    end
  end
end
