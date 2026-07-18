# frozen_string_literal: true

module ChatSDK
  module Telegram
    class KeyboardRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else render_single(node)
        end
      end

      private

      def render_card(node)
        text_parts = []
        keyboard_rows = []

        text_parts << "*#{node.attributes[:title]}*" if node.attributes[:title]
        text_parts << "_#{node.attributes[:subtitle]}_" if node.attributes[:subtitle]

        node.children.each do |child|
          case child.type
          when :text
            text_parts << child.attributes[:content]
          when :divider
            text_parts << "───"
          when :image
            text_parts << "[Image](#{child.attributes[:url]})"
          when :fields
            child.children.each do |field|
              text_parts << "*#{field.attributes[:label]}*: #{field.attributes[:value]}"
            end
          when :section
            render_section_into(child, text_parts, keyboard_rows)
          when :actions
            render_actions_into(child, keyboard_rows)
          when :button
            keyboard_rows << [render_button(child)]
          when :link_button
            keyboard_rows << [render_link_button(child)]
          when :select
            render_select_into(child, keyboard_rows)
          end
        end

        result = {text: text_parts.join("\n")}
        unless keyboard_rows.empty?
          result[:reply_markup] = {"inline_keyboard" => keyboard_rows}
        end
        result
      end

      def render_section_into(node, text_parts, keyboard_rows)
        text_parts << "*#{node.attributes[:title]}*" if node.attributes[:title]

        node.children.each do |child|
          case child.type
          when :text
            text_parts << child.attributes[:content]
          when :fields
            child.children.each do |field|
              text_parts << "*#{field.attributes[:label]}*: #{field.attributes[:value]}"
            end
          when :actions
            render_actions_into(child, keyboard_rows)
          when :button
            keyboard_rows << [render_button(child)]
          when :link_button
            keyboard_rows << [render_link_button(child)]
          when :select
            render_select_into(child, keyboard_rows)
          end
        end
      end

      def render_actions_into(node, keyboard_rows)
        row = []
        node.children.each do |child|
          if child.type == :select
            keyboard_rows << row unless row.empty?
            row = []
            render_select_into(child, keyboard_rows)
          else
            comp = render_component(child)
            row << comp if comp
          end
        end
        keyboard_rows << row unless row.empty?
      end

      def render_component(node)
        case node.type
        when :button then render_button(node)
        when :link_button then render_link_button(node)
        when :select then nil # selects expand into separate rows
        end
      end

      def render_button(node)
        callback_data = if node.attributes[:value]
          "#{node.attributes[:id]}:#{node.attributes[:value]}"
        else
          node.attributes[:id] || "button"
        end

        {"text" => node.attributes[:text], "callback_data" => callback_data}
      end

      def render_link_button(node)
        {"text" => node.attributes[:text], "url" => node.attributes[:url]}
      end

      def render_select_into(node, keyboard_rows)
        node.children.each do |opt|
          callback_data = "#{node.attributes[:id]}:#{opt.attributes[:value]}"
          keyboard_rows << [{"text" => opt.attributes[:text], "callback_data" => callback_data}]
        end
      end

      def render_single(node)
        case node.type
        when :text
          {text: node.attributes[:content]}
        else
          {text: node.fallback_text}
        end
      end
    end
  end
end
