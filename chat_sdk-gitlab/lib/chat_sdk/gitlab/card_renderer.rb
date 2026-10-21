# frozen_string_literal: true

module ChatSDK
  module GitLab
    class CardRenderer
      MARKDOWN_ESCAPED = ["\\", "*", "_", "[", "]"].freeze
      URL_UNSAFE = /[\s()<>]/

      def render(card)
        lines = []
        title = card.attributes[:title]
        subtitle = card.attributes[:subtitle]
        lines << "**#{escape_markdown(title)}**" if title
        lines << escape_markdown(subtitle) if subtitle
        lines << "" if (title || subtitle) && card.children.any?

        children = card.children.map { |child| render_child(child) }.reject(&:empty?)
        children.each_with_index do |child, index|
          lines << "" if index.positive?
          lines << child
        end
        lines.join("\n")
      end

      private

      def render_child(child)
        attributes = child.attributes

        case child.type
        when :text
          render_text(attributes[:content], attributes[:style])
        when :field
          "**#{escape_markdown(attributes[:label])}:** #{escape_markdown(attributes[:value])}"
        when :fields
          child.children.map { |field| render_child(field) }.reject(&:empty?).join("\n")
        when :actions
          child.children.map { |action| render_action(action) }.reject(&:empty?).join(" • ")
        when :section
          section = attributes[:title] ? "### #{escape_markdown(attributes[:title])}" : nil
          ([section] + child.children.map { |nested| render_child(nested) }).compact.reject(&:empty?).join("\n")
        when :image
          alt = escape_markdown(attributes[:alt])
          "![#{alt}](#{escape_url(attributes[:url])})"
        when :divider
          "---"
        when :table
          render_table(attributes)
        else
          child.fallback_text
        end
      end

      def render_text(content, style)
        case style&.to_sym
        when :bold then "**#{content}**"
        when :muted then "_#{content}_"
        else content.to_s
        end
      end

      def render_action(action)
        attributes = action.attributes
        label = escape_markdown(attributes[:text])

        if action.type == :link_button
          "[#{label}](#{escape_url(attributes[:url])})"
        else
          "**[#{label}]**"
        end
      end

      def render_table(attributes)
        headers = Array(attributes[:headers]).map { |value| escape_cell(value) }
        rows = Array(attributes[:rows]).map do |row|
          Array(row).map { |value| escape_cell(value) }
        end
        lines = []
        lines << attributes[:caption].to_s if attributes[:caption]

        unless headers.empty?
          alignments = Array(attributes[:align])
          lines << "| #{headers.join(" | ")} |"
          lines << "| #{headers.each_index.map { |index| alignment_marker(alignments[index]) }.join(" | ")} |"
        end
        rows.each { |row| lines << "| #{row.join(" | ")} |" }
        lines.join("\n")
      end

      def alignment_marker(alignment)
        case alignment&.to_sym
        when :center then ":---:"
        when :right then "---:"
        else "---"
        end
      end

      def escape_cell(value)
        value.to_s.gsub("|") { "\\|" }.gsub(/[\r\n]+/, " ")
      end

      def escape_markdown(value)
        value.to_s.each_char.map do |character|
          MARKDOWN_ESCAPED.include?(character) ? "\\#{character}" : character
        end.join
      end

      def escape_url(value)
        value.to_s.gsub(URL_UNSAFE) { |character| format("%%%02X", character.ord) }
      end
    end
  end
end
