# frozen_string_literal: true

module ChatSDK
  module Slack
    class BlockKitRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else [render_node(node)]
        end
      end

      private

      def render_card(node)
        node.children.map { |child| render_node(child) }.compact
      end

      def render_node(node)
        case node.type
        when :text then render_text(node)
        when :divider then { type: "divider" }
        when :image then render_image(node)
        when :fields then render_fields(node)
        when :section then render_section(node)
        when :actions then render_actions(node)
        else nil
        end
      end

      def render_text(node)
        {
          type: "section",
          text: { type: "mrkdwn", text: node.attributes[:content] }
        }
      end

      def render_image(node)
        block = { type: "image", image_url: node.attributes[:url] }
        block[:alt_text] = node.attributes[:alt] || " "
        block
      end

      def render_fields(node)
        {
          type: "section",
          fields: node.children.map do |field|
            { type: "mrkdwn", text: "*#{field.attributes[:label]}*\n#{field.attributes[:value]}" }
          end
        }
      end

      def render_section(node)
        block = { type: "section" }
        text_children = node.children.select { |c| c.type == :text }
        if text_children.any?
          block[:text] = { type: "mrkdwn", text: text_children.map { |t| t.attributes[:content] }.join("\n") }
        end
        block
      end

      def render_actions(node)
        {
          type: "actions",
          elements: node.children.map { |child| render_action_element(child) }.compact
        }
      end

      def render_action_element(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then render_select(node)
        else nil
        end
      end

      def render_button(node)
        btn = {
          type: "button",
          text: { type: "plain_text", text: node.attributes[:text] },
          action_id: node.attributes[:id]
        }
        btn[:value] = node.attributes[:value] if node.attributes[:value]
        if node.attributes[:style] == :primary
          btn[:style] = "primary"
        elsif node.attributes[:style] == :danger
          btn[:style] = "danger"
        end
        btn
      end

      def render_link_button(node)
        {
          type: "button",
          text: { type: "plain_text", text: node.attributes[:text] },
          url: node.attributes[:url],
          action_id: "link_#{node.attributes[:url].hash.abs}"
        }
      end

      def render_select(node)
        sel = {
          type: "static_select",
          action_id: node.attributes[:id],
          options: node.children.map { |opt| render_option(opt) }
        }
        if node.attributes[:placeholder]
          sel[:placeholder] = { type: "plain_text", text: node.attributes[:placeholder] }
        end
        sel
      end

      def render_option(node)
        opt = {
          text: { type: "plain_text", text: node.attributes[:text] },
          value: node.attributes[:value]
        }
        if node.attributes[:description]
          opt[:description] = { type: "plain_text", text: node.attributes[:description] }
        end
        opt
      end
    end
  end
end
