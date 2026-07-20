# frozen_string_literal: true

module ChatSDK
  module Messenger
    class FormatConverter < ChatSDK::Format::Converter
      # Messenger → Markdown (pass-through, Messenger messages are plain text)
      def to_markdown(platform_text)
        platform_text.to_s
      end

      # Markdown → Messenger (strip all formatting to plain text)
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        strip_markdown(text)
      end
    end
  end
end
