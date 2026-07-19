# frozen_string_literal: true

module ChatSDK
  module Cards
    module TextHelpers
      private

      def collect_text_parts(node)
        parts = []
        node.children.each do |child|
          case child.type
          when :text
            parts << child.attributes[:content]
          when :divider
            parts << "---"
          when :fields
            child.children.each do |field|
              parts << "#{field.attributes[:label]}: #{field.attributes[:value]}"
            end
          when :section
            parts << child.attributes[:title] if child.attributes[:title]
            parts.concat(collect_text_parts(child))
          end
        end
        parts
      end

      def truncate(text, max)
        return "" unless text
        (text.length > max) ? "#{text[0..max - 4]}..." : text
      end
    end
  end
end
