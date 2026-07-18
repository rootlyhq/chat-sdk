# frozen_string_literal: true

module ChatSDK
  module Cards
    class Node
      attr_reader :type, :attributes, :children

      def initialize(type, attributes: {}, children: [])
        @type = type
        @attributes = attributes
        @children = children.freeze
      end

      def fallback_text
        collect_text.join("\n").strip
      end

      def ==(other)
        other.is_a?(Node) && type == other.type &&
          attributes == other.attributes && children == other.children
      end

      private

      def collect_text(nodes = [self])
        nodes.flat_map do |node|
          case node.type
          when :text
            [node.attributes[:content]]
          when :field
            ["#{node.attributes[:label]}: #{node.attributes[:value]}"]
          when :button, :link_button
            [node.attributes[:text]]
          else
            collect_text(node.children)
          end
        end
      end
    end
  end
end
