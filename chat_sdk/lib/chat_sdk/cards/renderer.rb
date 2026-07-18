module ChatSDK
  module Cards
    class Renderer
      def render(node)
        case node.type
        when :card then render_card(node)
        when :text then node.attributes[:content]
        when :divider then "---"
        when :image then "![#{node.attributes[:alt]}](#{node.attributes[:url]})"
        when :fields then render_fields(node)
        when :field then "**#{node.attributes[:label]}**: #{node.attributes[:value]}"
        when :section then render_section(node)
        when :actions then render_actions(node)
        when :button then "[#{node.attributes[:text]}]"
        when :link_button then "[#{node.attributes[:text]}](#{node.attributes[:url]})"
        when :select then "_#{node.attributes[:placeholder] || "Select"}_"
        else ""
        end
      end

      private

      def render_card(node)
        parts = []
        parts << "**#{node.attributes[:title]}**" if node.attributes[:title]
        parts << "*#{node.attributes[:subtitle]}*" if node.attributes[:subtitle]
        parts.concat(node.children.map { |c| render(c) })
        parts.reject(&:empty?).join("\n\n")
      end

      def render_fields(node)
        node.children.map { |c| render(c) }.join(" | ")
      end

      def render_section(node)
        parts = []
        parts << "### #{node.attributes[:title]}" if node.attributes[:title]
        parts.concat(node.children.map { |c| render(c) })
        parts.join("\n")
      end

      def render_actions(node)
        node.children.map { |c| render(c) }.join(" | ")
      end
    end
  end
end
