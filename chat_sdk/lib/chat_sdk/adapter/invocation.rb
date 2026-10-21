# frozen_string_literal: true

module ChatSDK
  module Adapter
    module Invocation
      private

      def call_adapter(method_name, **kwargs)
        params = adapter.method(method_name).parameters
        accepts_thread_id = params.any? do |type, name|
          type == :keyrest || (%i[key keyreq].include?(type) && name == :thread_id)
        end
        kwargs.delete(:thread_id) unless accepts_thread_id
        adapter.public_send(method_name, **kwargs)
      end
    end
  end
end
