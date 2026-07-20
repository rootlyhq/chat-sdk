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

      private

      def strip_markdown(text)
        result = text

        # Remove fenced code blocks but keep content
        result = result.gsub(/```\w*\n?([\s\S]*?)```/, '\1')

        # Remove inline code markers
        result = result.gsub(/`([^`]+)`/, '\1')

        # Convert links: [text](url) → text (url)
        result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1 (\2)')

        # Remove bold markers: **text** → text
        result = result.gsub(/\*\*(.+?)\*\*/m, '\1')

        # Remove italic markers: *text* → text
        result = result.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/m, '\1')

        # Remove strikethrough markers: ~~text~~ → text
        result.gsub(/~~(.+?)~~/m, '\1')
      end
    end
  end
end
