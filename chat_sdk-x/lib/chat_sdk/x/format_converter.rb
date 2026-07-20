# frozen_string_literal: true

module ChatSDK
  module X
    class FormatConverter < ChatSDK::Format::Converter
      # X (Twitter) → Markdown (pass-through, X posts are plain text)
      def to_markdown(platform_text)
        platform_text.to_s
      end

      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        strip_markdown(text)
      end
    end
  end
end
