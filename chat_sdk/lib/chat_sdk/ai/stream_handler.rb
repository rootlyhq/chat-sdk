# frozen_string_literal: true

module ChatSDK
  module AI
    class StreamHandler
      def self.stream_to_thread(thread, enumerable, placeholder: "Thinking...")
        thread.post_stream(placeholder: placeholder) do |stream|
          enumerable.each { |chunk| stream << chunk.to_s }
        end
      end
    end
  end
end
