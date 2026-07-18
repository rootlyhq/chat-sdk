# frozen_string_literal: true

module ChatSDK
  module Discord
    class EmbedRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else render_single(node)
        end
      end

      private

      def render_card(node)
        embed = {}
        description_parts = []
        fields = []
        components = []

        embed["title"] = node.attributes[:title] if node.attributes[:title]

        if node.attributes[:subtitle]
          description_parts << node.attributes[:subtitle]
        end

        node.children.each do |child|
          case child.type
          when :text
            description_parts << child.attributes[:content]
          when :divider
            description_parts << "───"
          when :image
            embed["image"] = {"url" => child.attributes[:url]}
          when :fields
            child.children.each do |field|
              fields << {
                "name" => field.attributes[:label],
                "value" => field.attributes[:value],
                "inline" => true
              }
            end
          when :section
            render_section_into(child, description_parts, fields, components)
          when :actions
            row = render_action_row(child)
            components << row if row
          when :button, :link_button, :select
            row = {"type" => 1, "components" => [render_component(child)].compact}
            components << row
          end
        end

        embed["description"] = description_parts.join("\n") unless description_parts.empty?
        embed["fields"] = fields unless fields.empty?

        result = {"embeds" => [embed]}
        result["components"] = components unless components.empty?
        result
      end

      def render_section_into(node, description_parts, fields, components)
        description_parts << "**#{node.attributes[:title]}**" if node.attributes[:title]

        node.children.each do |child|
          case child.type
          when :text
            description_parts << child.attributes[:content]
          when :fields
            child.children.each do |field|
              fields << {
                "name" => field.attributes[:label],
                "value" => field.attributes[:value],
                "inline" => true
              }
            end
          when :actions
            row = render_action_row(child)
            components << row if row
          when :button, :link_button, :select
            row = {"type" => 1, "components" => [render_component(child)].compact}
            components << row
          end
        end
      end

      def render_action_row(node)
        comps = node.children.filter_map { |child| render_component(child) }
        return nil if comps.empty?

        {"type" => 1, "components" => comps}
      end

      def render_component(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then render_select(node)
        end
      end

      def render_button(node)
        style = case node.attributes[:style]
        when :primary then 1
        when :danger then 4
        else 2
        end

        {
          "type" => 2,
          "style" => style,
          "label" => node.attributes[:text],
          "custom_id" => node.attributes[:id] || "button"
        }
      end

      def render_link_button(node)
        {
          "type" => 2,
          "style" => 5,
          "label" => node.attributes[:text],
          "url" => node.attributes[:url]
        }
      end

      def render_select(node)
        options = node.children.map do |opt|
          option = {
            "label" => opt.attributes[:text],
            "value" => opt.attributes[:value]
          }
          option["description"] = opt.attributes[:description] if opt.attributes[:description]
          option
        end

        component = {
          "type" => 3,
          "custom_id" => node.attributes[:id] || "select",
          "options" => options
        }
        component["placeholder"] = node.attributes[:placeholder] if node.attributes[:placeholder]
        component
      end

      def render_single(node)
        case node.type
        when :text
          {"embeds" => [{"description" => node.attributes[:content]}]}
        else
          {"embeds" => [{"description" => node.fallback_text}]}
        end
      end
    end
  end
end
