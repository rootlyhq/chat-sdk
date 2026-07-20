# frozen_string_literal: true

require "commonmarker"

module ChatSDK
  module Format
    class Converter
      def to_markdown(platform_text)
        platform_text
      end

      def from_markdown(markdown)
        markdown
      end

      def parse(markdown)
        Commonmarker.parse(markdown)
      end

      def render_markdown(node)
        node.to_commonmark
      end

      def render_html(node)
        node.to_html
      end

      private

      def split_code_blocks(text)
        text.split(/(```[\s\S]*?```|`[^`]+`)/)
      end

      def strip_markdown(text)
        result = text.gsub(/```\w*\n?([\s\S]*?)```/, '\1')
        result = result.gsub(/`([^`]+)`/, '\1')
        result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1 (\2)')
        result = result.gsub(/\*\*(.+?)\*\*/, '\1')
        result = result.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, '\1')
        result.gsub(/~~(.+?)~~/, '\1')
      end

      def convert_bold_and_italic_from_md(text, bold_char: "*", italic_char: "_")
        result = text.gsub(/\*\*(.+?)\*\*/, "\x00BOLD\\1BOLD\x00")
        result = result.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, "#{italic_char}\\1#{italic_char}")
        result.gsub(/\x00BOLD(.+?)BOLD\x00/, "#{bold_char}\\1#{bold_char}")
      end
    end
  end
end
