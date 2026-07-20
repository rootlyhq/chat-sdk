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
    end
  end
end
