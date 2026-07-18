# frozen_string_literal: true

module ChatSDK
  module Webhook
    class Router
      def initialize(chat, adapters)
        @chat = chat
        @adapters = adapters
      end

      def call(env)
        path = env["PATH_INFO"].to_s.split("/").last&.to_sym
        adapter = @adapters[path]

        unless adapter
          return [404, {"content-type" => "text/plain"}, ["Unknown adapter: #{path}"]]
        end

        endpoint = Endpoint.new(chat: @chat, adapter: adapter, adapter_name: path)
        endpoint.call(env)
      end
    end
  end
end
