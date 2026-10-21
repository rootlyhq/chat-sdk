# frozen_string_literal: true

require "date"

module ChatSDK
  module Slack
    class ModalRenderer
      def render(node)
        view = {
          type: "modal",
          title: {type: "plain_text", text: node.attributes[:title]}
        }
        view[:callback_id] = node.attributes[:callback_id] if node.attributes[:callback_id]
        if node.attributes[:close_label] && !node.attributes[:close_label].empty?
          view[:close] = {type: "plain_text", text: node.attributes[:close_label]}
        end
        if node.attributes[:submit_label]
          view[:submit] = {type: "plain_text", text: node.attributes[:submit_label]}
        end
        view[:blocks] = node.children.map { |child| render_block(child) }.compact
        view
      end

      private

      def render_block(node)
        case node.type
        when :input then render_input(node)
        when :text then render_text(node)
        when :fields then render_fields(node)
        end
      end

      def render_input(node)
        block = {
          type: "input",
          block_id: node.attributes[:id],
          label: {type: "plain_text", text: node.attributes[:label]},
          optional: node.attributes[:optional] || false
        }
        block[:element] = case node.attributes[:input_type]
        when :text
          el = {
            type: "plain_text_input",
            action_id: node.attributes[:id],
            multiline: !!node.attributes[:multiline]
          }
          el[:placeholder] = {type: "plain_text", text: node.attributes[:placeholder]} if node.attributes[:placeholder]
          if node.attributes[:initial_value] && !node.attributes[:initial_value].empty?
            el[:initial_value] = node.attributes[:initial_value]
          end
          el[:max_length] = node.attributes[:max_length] if node.attributes[:max_length] && !node.attributes[:max_length].zero?
          el
        when :select
          el = {
            type: "static_select",
            action_id: node.attributes[:id],
            options: node.children.map { |opt| render_option(opt) }
          }
          el[:placeholder] = {type: "plain_text", text: node.attributes[:placeholder]} if node.attributes[:placeholder]
          if node.attributes[:initial_option] && !node.attributes[:initial_option].empty?
            initial_option = el[:options].find { |option| option[:value] == node.attributes[:initial_option] }
            el[:initial_option] = initial_option if initial_option
          end
          el
        when :radio_select
          options = node.children.first(10).map { |option| render_radio_option(option) }
          el = {type: "radio_buttons", action_id: node.attributes[:id], options: options}
          if node.attributes[:initial_option] && !node.attributes[:initial_option].empty?
            initial_option = options.find { |option| option[:value] == node.attributes[:initial_option] }
            el[:initial_option] = initial_option if initial_option
          end
          el
        when :external_select
          el = {type: "external_select", action_id: node.attributes[:id]}
          el[:placeholder] = {type: "plain_text", text: node.attributes[:placeholder]} if node.attributes[:placeholder]
          el[:min_query_length] = node.attributes[:min_query_length] unless node.attributes[:min_query_length].nil?
          if node.attributes[:initial_option]
            el[:initial_option] = render_external_option(node.attributes[:initial_option])
          end
          el
        when :date
          el = {type: "datepicker", action_id: node.attributes[:id]}
          initial_date = valid_initial_date(node.attributes[:initial_value])
          el[:initial_date] = initial_date if initial_date
          el[:placeholder] = {type: "plain_text", text: node.attributes[:placeholder]} if node.attributes[:placeholder]
          el
        when :number
          el = {
            type: "number_input",
            action_id: node.attributes[:id],
            is_decimal_allowed: !!node.attributes[:decimal]
          }
          el[:min_value] = node.attributes[:min].to_s unless node.attributes[:min].nil?
          el[:max_value] = node.attributes[:max].to_s unless node.attributes[:max].nil?
          el[:initial_value] = node.attributes[:initial_value].to_s unless node.attributes[:initial_value].nil?
          el[:placeholder] = {type: "plain_text", text: node.attributes[:placeholder]} if node.attributes[:placeholder]
          el
        end
        block[:dispatch_action] = node.attributes[:dispatch_action] unless node.attributes[:dispatch_action].nil?
        block
      end

      def valid_initial_date(value)
        return unless value

        parsed = Date.iso8601(value.to_s)
        value.to_s if parsed.iso8601 == value.to_s
      rescue Date::Error
        ChatSDK::Log.warn("Ignoring invalid modal initial date: #{value.inspect}")
        nil
      end

      def render_text(node)
        {
          type: "section",
          text: {type: "mrkdwn", text: node.attributes[:content]}
        }
      end

      def render_option(node)
        opt = {
          text: {type: "plain_text", text: node.attributes[:text]},
          value: node.attributes[:value]
        }
        opt[:description] = {type: "plain_text", text: node.attributes[:description]} if node.attributes[:description]
        opt
      end

      def render_radio_option(node)
        option = {
          text: {type: "mrkdwn", text: node.attributes[:text]},
          value: node.attributes[:value]
        }
        option[:description] = {type: "mrkdwn", text: node.attributes[:description]} if node.attributes[:description]
        option
      end

      def render_external_option(option)
        label = option[:label] || option["label"]
        value = option[:value] || option["value"]
        description = option[:description] || option["description"]
        rendered = {text: {type: "plain_text", text: label}, value: value}
        rendered[:description] = {type: "plain_text", text: description} if description
        rendered
      end

      def render_fields(node)
        {
          type: "section",
          fields: node.children.map do |field|
            {type: "mrkdwn", text: "*#{field.attributes[:label]}*\n#{field.attributes[:value]}"}
          end
        }
      end
    end
  end
end
