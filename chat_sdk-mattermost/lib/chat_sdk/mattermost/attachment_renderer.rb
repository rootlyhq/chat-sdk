# frozen_string_literal: true

module ChatSDK
  module Mattermost
    class AttachmentRenderer
      attr_writer :integration_url

      def initialize(integration_url: nil)
        @integration_url = integration_url
      end

      def render(node)
        case node.type
        when :card then render_card(node)
        else wrap_attachment(render_node(node))
        end
      end

      private

      def render_card(node)
        attachment = {}
        fields = []
        actions = []
        text_parts = []

        node.children.each do |child|
          case child.type
          when :text
            text_parts << child.attributes[:content]
          when :divider
            text_parts << "---"
          when :image
            attachment["image_url"] = child.attributes[:url]
          when :fields
            child.children.each do |field|
              fields << {
                "title" => field.attributes[:label],
                "value" => field.attributes[:value],
                "short" => true
              }
            end
          when :section
            render_section_into(child, text_parts, fields, actions)
          when :actions
            child.children.each do |action_node|
              action = render_action(action_node)
              actions << action if action
            end
          when :button
            action = render_action(child)
            actions << action if action
          when :select
            action = render_action(child)
            actions << action if action
          end
        end

        attachment["text"] = text_parts.join("\n") unless text_parts.empty?
        attachment["fields"] = fields unless fields.empty?
        attachment["actions"] = actions unless actions.empty?

        if node.attributes[:title]
          attachment["title"] = node.attributes[:title]
        end

        [attachment]
      end

      def render_section_into(node, text_parts, fields, actions)
        text_parts << "**#{node.attributes[:title]}**" if node.attributes[:title]

        node.children.each do |child|
          case child.type
          when :text
            text_parts << child.attributes[:content]
          when :fields
            child.children.each do |field|
              fields << {
                "title" => field.attributes[:label],
                "value" => field.attributes[:value],
                "short" => true
              }
            end
          when :actions
            child.children.each do |action_node|
              action = render_action(action_node)
              actions << action if action
            end
          when :button, :select
            action = render_action(child)
            actions << action if action
          end
        end
      end

      def render_action(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then render_select(node)
        end
      end

      def render_button(node)
        action = {
          "id" => node.attributes[:id] || "button",
          "name" => node.attributes[:text],
          "type" => "button"
        }

        if @integration_url
          action["integration"] = {
            "url" => @integration_url,
            "context" => {
              "action" => node.attributes[:id],
              "value" => node.attributes[:value]
            }.compact
          }
        end

        if node.attributes[:style] == :primary
          action["style"] = "primary"
        elsif node.attributes[:style] == :danger
          action["style"] = "danger"
        end

        action
      end

      def render_link_button(node)
        # Mattermost does not have native link buttons in attachments.
        # Render as a button with a URL in the integration context.
        {
          "id" => node.attributes[:id] || "link",
          "name" => node.attributes[:text],
          "type" => "button",
          "integration" => {
            "url" => node.attributes[:url],
            "context" => {"action" => "open_url", "url" => node.attributes[:url]}
          }
        }
      end

      def render_select(node)
        action = {
          "id" => node.attributes[:id] || "select",
          "name" => node.attributes[:placeholder] || "Select",
          "type" => "select",
          "options" => node.children.map do |opt|
            {"text" => opt.attributes[:text], "value" => opt.attributes[:value]}
          end
        }

        if @integration_url
          action["integration"] = {
            "url" => @integration_url,
            "context" => {"action" => node.attributes[:id]}
          }
        end

        action
      end

      def render_node(node)
        case node.type
        when :text
          {"text" => node.attributes[:content]}
        when :fields
          fields = node.children.map do |field|
            {"title" => field.attributes[:label], "value" => field.attributes[:value], "short" => true}
          end
          {"fields" => fields}
        when :actions
          actions = node.children.filter_map { |child| render_action(child) }
          {"actions" => actions}
        else
          {"text" => node.fallback_text}
        end
      end

      def wrap_attachment(content)
        [content]
      end
    end
  end
end
