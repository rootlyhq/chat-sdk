# frozen_string_literal: true

module ChatSDK
  module Twilio
    class FormatConverter < ChatSDK::Format::Converter
      # Twilio SMS → Markdown (pass-through, SMS is plain text)
      def to_markdown(platform_text)
        platform_text.to_s
      end

      # Markdown → Twilio SMS (strip all formatting to plain text)
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        strip_markdown(text)
      end
    end
  end
end
