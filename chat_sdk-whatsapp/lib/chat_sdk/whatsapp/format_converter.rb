# frozen_string_literal: true

module ChatSDK
  module WhatsApp
    class FormatConverter < ChatSDK::Format::Converter
      # WhatsApp → Markdown
      def to_markdown(platform_text)
        text = platform_text.to_s
        return "" if text.empty?

        parts = split_code_blocks(text)
        parts.map.with_index { |part, i| i.odd? ? part : convert_whatsapp_to_md(part) }.join
      end

      # Markdown → WhatsApp
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        parts = split_code_blocks(text)
        parts.map.with_index { |part, i| i.odd? ? part : convert_md_to_whatsapp(part) }.join
      end

      private

      def convert_whatsapp_to_md(text)
        result = text

        # Bold: *text* → **text** (must come before italic)
        result = result.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/m, '**\1**')

        # Italic: _text_ → *text*
        result = result.gsub(/(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])/m, '*\1*')

        # Strikethrough: ~text~ → ~~text~~
        result.gsub(/(?<!~)~(?!~)(.+?)(?<!~)~(?!~)/m, '~~\1~~')
      end

      def convert_md_to_whatsapp(text)
        result = text

        # Bold/italic with placeholder to prevent double conversion
        result = convert_bold_and_italic_from_md(result, bold_char: "*", italic_char: "_")

        # Strikethrough: ~~text~~ → ~text~
        result.gsub(/~~(.+?)~~/m, '~\1~')
      end
    end
  end
end
