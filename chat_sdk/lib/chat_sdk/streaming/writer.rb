# frozen_string_literal: true

module ChatSDK
  module Streaming
    class Writer
      def initialize(yielder)
        @yielder = yielder
      end

      def <<(chunk)
        @yielder << chunk
        self
      end
    end
  end
end
