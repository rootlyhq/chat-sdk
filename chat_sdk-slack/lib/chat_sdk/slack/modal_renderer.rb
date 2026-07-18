# frozen_string_literal: true

module ChatSDK
  module Slack
    class ModalRenderer
      def render(node)
        view = {
          type: "modal",
          title: { type: "plain_text", text: node.attributes[:title] }
        }
        view[:callback_id] = node.attributes[:callback_id] if node.attributes[:callback_id]
        if node.attributes[:submit_label]
          view[:submit] = { type: "plain_text", text: node.attributes[:submit_label] }
        end
        view[:blocks] = node.children.map { |child| render_block(child) }.compact
        view
      end

      private

      def render_block(node)
        case node.type
        when :input then render_input(node)
        when :text then render_text(node)
        else nil
        end
      end

      def render_input(node)
        block = {
          type: "input",
          block_id: node.attributes[:id],
          label: { type: "plain_text", text: node.attributes[:label] },
          optional: node.attributes[:optional] || false
        }
        block[:element] = case node.attributes[:input_type]
        when :text
          el = {
            type: "plain_text_input",
            action_id: node.attributes[:id],
            multiline: !!node.attributes[:multiline]
          }
          el[:placeholder] = { type: "plain_text", text: node.attributes[:placeholder] } if node.attributes[:placeholder]
          el
        when :select
          el = {
            type: "static_select",
            action_id: node.attributes[:id],
            options: node.children.map { |opt| render_option(opt) }
          }
          el[:placeholder] = { type: "plain_text", text: node.attributes[:placeholder] } if node.attributes[:placeholder]
          el
        end
        block
      end

      def render_text(node)
        {
          type: "section",
          text: { type: "mrkdwn", text: node.attributes[:content] }
        }
      end

      def render_option(node)
        opt = {
          text: { type: "plain_text", text: node.attributes[:text] },
          value: node.attributes[:value]
        }
        opt[:description] = { type: "plain_text", text: node.attributes[:description] } if node.attributes[:description]
        opt
      end
    end
  end
end
