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
        request = Rack::Request.new(env) if defined?(Rack)

        adapter.verify_request!(request || env)

        ack = adapter.ack_response(request || env)
        return ack if ack

        events = adapter.parse_events(request || env)
        events.each { |event| chat.dispatch(event, adapter_name: adapter_name) }

        [200, { "content-type" => "text/plain" }, [""]]
      rescue ChatSDK::SignatureVerificationError => e
        ChatSDK::Log.warn("Signature verification failed: #{e.message}")
        [401, { "content-type" => "text/plain" }, ["Unauthorized"]]
      rescue => e
        ChatSDK::Log.error("Webhook error: #{e.message}")
        [200, { "content-type" => "text/plain" }, [""]]
      end
    end
  end
end
