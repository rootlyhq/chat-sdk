# frozen_string_literal: true

module ChatSDK
  module Teams
    class AdaptiveCardRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else wrap_card([render_node(node)].compact)
        end
      end

      private

      def render_card(node)
        body = []
        pending_separator = false

        node.children.each do |child|
          if child.type == :divider
            pending_separator = true
            next
          end

          element = render_node(child)
          next unless element

          if pending_separator
            element["separator"] = true
            pending_separator = false
          end

          if element.is_a?(Array)
            body.concat(element)
          else
            body << element
          end
        end

        wrap_card(body, width: node.attributes[:width])
      end

      def wrap_card(body, width: nil)
        card = {
          "type" => "AdaptiveCard",
          "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
          "version" => "1.5",
          "body" => body
        }
        card["msteams"] = {"width" => "full"} if width.to_s == "full"
        card
      end

      def render_node(node)
        case node.type
        when :text then render_text(node)
        when :divider then nil # handled in render_card
        when :image then render_image(node)
        when :fields then render_fields(node)
        when :section then render_section(node)
        when :actions then render_actions(node)
        when :button then render_action_submit(node)
        when :link_button then render_action_open_url(node)
        when :select then render_select(node)
        when :text_input then render_text_input(node)
        when :table then render_table(node)
        when :chart then render_chart(node)
        end
      end

      def render_text(node)
        {
          "type" => "TextBlock",
          "text" => node.attributes[:content],
          "wrap" => true
        }
      end

      def render_image(node)
        block = {
          "type" => "Image",
          "url" => node.attributes[:url]
        }
        block["altText"] = node.attributes[:alt] if node.attributes[:alt]
        block
      end

      def render_fields(node)
        {
          "type" => "FactSet",
          "facts" => node.children.map do |field|
            {
              "title" => field.attributes[:label],
              "value" => field.attributes[:value]
            }
          end
        }
      end

      def render_section(node)
        elements = []
        if node.attributes[:title]
          elements << {
            "type" => "TextBlock",
            "text" => node.attributes[:title],
            "weight" => "bolder",
            "size" => "medium",
            "wrap" => true
          }
        end
        node.children.each do |child|
          el = render_node(child)
          next unless el
          if el.is_a?(Array)
            elements.concat(el)
          else
            elements << el
          end
        end
        {
          "type" => "Container",
          "items" => elements
        }
      end

      def render_actions(node)
        actions = node.children.filter_map { |child| render_action_element(child) }
        {
          "type" => "ActionSet",
          "actions" => actions
        }
      end

      def render_action_element(node)
        case node.type
        when :button then render_action_submit(node)
        when :link_button then render_action_open_url(node)
        when :select then render_select(node)
        end
      end

      def render_action_submit(node)
        action = {
          "type" => "Action.Submit",
          "title" => node.attributes[:text],
          "data" => {"actionId" => node.attributes[:id]}
        }
        action["data"]["value"] = node.attributes[:value] if node.attributes[:value]
        action["tooltip"] = node.attributes[:tooltip] if node.attributes[:tooltip]
        if node.attributes[:style] == :primary
          action["style"] = "positive"
        elsif node.attributes[:style] == :danger
          action["style"] = "destructive"
        end
        action
      end

      def render_action_open_url(node)
        action = {
          "type" => "Action.OpenUrl",
          "title" => node.attributes[:text],
          "url" => node.attributes[:url]
        }
        action["id"] = node.attributes[:id] if node.attributes[:id]
        action["tooltip"] = node.attributes[:tooltip] if node.attributes[:tooltip]
        action
      end

      def render_select(node)
        input = {
          "type" => "Input.ChoiceSet",
          "id" => node.attributes[:id],
          "choices" => node.children.map do |opt|
            {
              "title" => opt.attributes[:text],
              "value" => opt.attributes[:value]
            }
          end
        }
        input["placeholder"] = node.attributes[:placeholder] if node.attributes[:placeholder]
        input
      end

      def render_text_input(node)
        input = {
          "type" => "Input.Text",
          "id" => node.attributes[:id],
          "label" => node.attributes[:label],
          "isMultiline" => node.attributes[:multiline],
          "isRequired" => !node.attributes[:optional]
        }
        input["placeholder"] = node.attributes[:placeholder] if node.attributes[:placeholder]
        input["value"] = node.attributes[:value] unless node.attributes[:value].nil?
        input
      end

      def render_table(node)
        headers = Array(node.attributes[:headers])
        data_rows = Array(node.attributes[:rows])
        column_count = data_rows.reduce(headers.length) { |count, row| [count, Array(row).length].max }
        return if column_count.zero?

        alignment = {left: "Left", center: "Center", right: "Right"}
        vertical_alignment = {top: "Top", center: "Center", bottom: "Bottom"}
        widths = Array(node.attributes[:widths])
        aligns = Array(node.attributes[:align])
        rows = data_rows.map { |row| Array(row) }
        rows.unshift(headers) unless headers.empty?

        {
          "type" => "Table",
          "firstRowAsHeaders" => !headers.empty?,
          "showGridLines" => node.attributes.fetch(:grid_lines, true),
          "columns" => Array.new(column_count) do |index|
            width = widths[index]
            column_width = width
            column_width = 1 unless column_width.is_a?(Integer) && column_width.positive?
            column = {"width" => column_width}
            column_alignment = alignment[aligns[index]&.to_sym]
            column["horizontalCellContentAlignment"] = column_alignment if column_alignment
            column
          end,
          "rows" => rows.each_with_index.map do |row, index|
            {
              "type" => "TableRow",
              "cells" => Array.new(column_count) do |cell_index|
                {
                  "type" => "TableCell",
                  "items" => [{
                    "type" => "TextBlock",
                    "text" => Array(row)[cell_index].to_s,
                    "weight" => ("Bolder" if index.zero? && !headers.empty?),
                    "wrap" => true
                  }.compact]
                }
              end
            }
          end,
          "gridStyle" => node.attributes[:grid_style],
          "verticalCellContentAlignment" => vertical_alignment[node.attributes[:vertical_align]&.to_sym]
        }
          .compact
      end

      def render_chart(node)
        {
          "type" => "TextBlock",
          "text" => node.fallback_text,
          "wrap" => true,
          "fontType" => "Monospace"
        }
      end
    end
  end
end
