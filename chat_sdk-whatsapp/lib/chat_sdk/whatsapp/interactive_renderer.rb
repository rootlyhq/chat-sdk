# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class InteractiveRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else render_single(node)
        end
      end

      private

      def render_card(node)
        buttons = collect_reply_buttons(node)
        title = node.attributes[:title]
        subtitle = node.attributes[:subtitle]
        text_parts = collect_text_parts(node)
        body_text = [subtitle, *text_parts].compact.reject(&:empty?).join("\n")
        body_text = title if body_text.empty? && title

        if title && buttons.any? && buttons.length <= 3
          # Interactive button message
          interactive = {
            "type" => "button",
            "body" => {"text" => body_text.empty? ? title : body_text}
          }
          interactive["header"] = {"type" => "text", "text" => truncate(title, 60)} if title
          interactive["action"] = {
            "buttons" => buttons.first(3).map do |btn|
              {
                "type" => "reply",
                "reply" => {
                  "id" => btn[:id],
                  "title" => truncate(btn[:text], 20)
                }
              }
            end
          }

          {type: "interactive", interactive: interactive}
        else
          # Fallback to plain text
          fallback = [title, subtitle, *text_parts].compact.reject(&:empty?).join("\n")
          if buttons.any?
            button_text = buttons.map { |b| b[:text] }.join(", ")
            fallback = "#{fallback}\n[#{button_text}]" unless button_text.empty?
          end
          {text: fallback}
        end
      end

      def collect_reply_buttons(node)
        buttons = []
        node.children.each do |child|
          case child.type
          when :button
            buttons << {id: child.attributes[:id] || "button", text: child.attributes[:text] || ""}
          when :link_button
            # WhatsApp reply buttons can't have URLs; skip link buttons
            next
          when :actions
            child.children.each do |action_child|
              case action_child.type
              when :button
                buttons << {id: action_child.attributes[:id] || "button", text: action_child.attributes[:text] || ""}
              when :link_button
                next
              end
            end
          when :section
            buttons.concat(collect_reply_buttons(child))
          end
        end
        buttons
      end

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

      def render_single(node)
        case node.type
        when :text
          {text: node.attributes[:content]}
        else
          {text: node.fallback_text}
        end
      end

      def truncate(text, max)
        return "" unless text

        (text.length > max) ? "#{text[0..max - 4]}..." : text
      end
    end
  end
end
