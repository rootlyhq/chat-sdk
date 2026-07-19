# frozen_string_literal: true

module ChatSDK
  module Messenger
    class TemplateRenderer
      def render(node)
        case node.type
        when :card then render_card(node)
        else render_single(node)
        end
      end

      private

      def render_card(node)
        buttons = collect_buttons(node)
        title = node.attributes[:title]
        subtitle = node.attributes[:subtitle]
        image_url = find_image_url(node)
        text_parts = collect_text_parts(node)
        body_text = text_parts.join("\n")

        if title && buttons.any?
          # Generic Template: has title and buttons
          element = {"title" => truncate(title, 80)}
          element["subtitle"] = truncate(subtitle || body_text, 80) if subtitle || body_text.length.positive?
          element["image_url"] = image_url if image_url
          element["buttons"] = buttons.first(3)

          {
            attachment: {
              "type" => "template",
              "payload" => {
                "template_type" => "generic",
                "elements" => [element]
              }
            }
          }
        elsif buttons.any? && buttons.length <= 3 && !image_url
          # Button Template: text + buttons, no image
          fallback_text = [title, subtitle, body_text].compact.reject(&:empty?).join(" - ")
          fallback_text = "Choose an option" if fallback_text.empty?

          {
            attachment: {
              "type" => "template",
              "payload" => {
                "template_type" => "button",
                "text" => truncate(fallback_text, 640),
                "buttons" => buttons.first(3)
              }
            }
          }
        else
          # Fallback: plain text
          fallback = [title, subtitle, body_text].compact.reject(&:empty?).join("\n")
          if buttons.any?
            button_text = buttons.map { |b| b["title"] }.join(", ")
            fallback = "#{fallback}\n[#{button_text}]" unless button_text.empty?
          end
          {text: fallback}
        end
      end

      def collect_buttons(node)
        buttons = []
        node.children.each do |child|
          case child.type
          when :button
            buttons << render_postback_button(child)
          when :link_button
            buttons << render_url_button(child)
          when :actions
            child.children.each do |action_child|
              case action_child.type
              when :button
                buttons << render_postback_button(action_child)
              when :link_button
                buttons << render_url_button(action_child)
              end
            end
          when :section
            buttons.concat(collect_buttons(child))
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

      def find_image_url(node)
        node.children.each do |child|
          return child.attributes[:url] if child.type == :image
          if child.type == :section
            url = find_image_url(child)
            return url if url
          end
        end
        nil
      end

      def render_postback_button(node)
        {
          "type" => "postback",
          "title" => truncate(node.attributes[:text], 20),
          "payload" => node.attributes[:id] || "button"
        }
      end

      def render_url_button(node)
        {
          "type" => "web_url",
          "title" => truncate(node.attributes[:text], 20),
          "url" => node.attributes[:url]
        }
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
