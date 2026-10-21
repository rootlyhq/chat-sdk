# frozen_string_literal: true

module ChatSDK
  module AI
    class StreamHandler
      def self.stream_to_thread(thread, enumerable, placeholder: "Thinking...", **plan_options)
        thread.post_stream(placeholder: placeholder, **plan_options) do |stream|
          enumerable.each { |chunk| stream << chunk }
        end
      end
    end
  end
end
