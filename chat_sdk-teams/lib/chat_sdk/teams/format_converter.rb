# frozen_string_literal: true

module ChatSDK
  module Teams
    class FormatConverter < ChatSDK::Format::Converter
      # Teams HTML → Markdown
      def to_markdown(platform_text)
        text = platform_text.to_s
        return "" if text.empty?

        # Protect <pre> blocks first — extract them before processing inline HTML
        pre_blocks = []
        text = text.gsub(%r{<pre>(.*?)</pre>}mi) do
          pre_blocks << Regexp.last_match(1)
          "\x00PRE#{pre_blocks.size - 1}\x00"
        end

        # Protect <code> spans
        code_spans = []
        text = text.gsub(%r{<code>(.*?)</code>}mi) do
          code_spans << Regexp.last_match(1)
          "\x00CODE#{code_spans.size - 1}\x00"
        end

        # Convert block-level elements
        text = convert_lists_to_markdown(text)

        # Convert inline formatting
        text = text.gsub(%r{<(?:b|strong)>(.*?)</(?:b|strong)>}mi, '**\1**')
        text = text.gsub(%r{<(?:i|em)>(.*?)</(?:i|em)>}mi, '*\1*')
        text = text.gsub(%r{<(?:s|strike|del)>(.*?)</(?:s|strike|del)>}mi, '~~\1~~')
        text = text.gsub(%r{<a\s+href="([^"]*)"[^>]*>(.*?)</a>}mi, '[\2](\1)')
        text = text.gsub(%r{<at>(.*?)</at>}mi, '@\1')
        text = text.gsub(%r{<br\s*/?>}i, "\n")

        # Decode HTML entities
        text = decode_html_entities(text)

        # Strip any remaining HTML tags
        text = text.gsub(/<[^>]+>/, "")

        # Restore code spans
        code_spans.each_with_index do |content, i|
          text = text.sub("\x00CODE#{i}\x00", "`#{content}`")
        end

        # Restore pre blocks
        pre_blocks.each_with_index do |content, i|
          text = text.sub("\x00PRE#{i}\x00", "```\n#{content}\n```")
        end

        text
      end

      # Markdown → Teams HTML
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        # Protect fenced code blocks first
        code_blocks = []
        text = text.gsub(/```\n?(.*?)\n?```/m) do
          code_blocks << Regexp.last_match(1)
          "\x00CODEBLOCK#{code_blocks.size - 1}\x00"
        end

        # Protect inline code spans
        code_spans = []
        text = text.gsub(/`([^`]+)`/) do
          code_spans << Regexp.last_match(1)
          "\x00CODESPAN#{code_spans.size - 1}\x00"
        end

        # Convert markdown formatting to HTML
        text = text.gsub(/\*\*(.+?)\*\*/m, '<b>\1</b>')
        text = text.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/m, '<i>\1</i>')
        text = text.gsub(/~~(.+?)~~/m, '<s>\1</s>')
        text = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2">\1</a>')
        text = text.gsub("\n", "<br>")

        # Restore inline code spans
        code_spans.each_with_index do |content, i|
          text = text.sub("\x00CODESPAN#{i}\x00", "<code>#{content}</code>")
        end

        # Restore code blocks
        code_blocks.each_with_index do |content, i|
          text = text.sub("\x00CODEBLOCK#{i}\x00", "<pre>#{content}</pre>")
        end

        text
      end

      private

      def convert_lists_to_markdown(html)
        # Convert unordered lists
        html = html.gsub(%r{<ul>(.*?)</ul>}mi) do
          items = Regexp.last_match(1)
          items.gsub(%r{<li>(.*?)</li>}mi) { "- #{Regexp.last_match(1).strip}\n" }.strip
        end

        # Convert ordered lists
        html.gsub(%r{<ol>(.*?)</ol>}mi) do
          items = Regexp.last_match(1)
          index = 0
          items.gsub(%r{<li>(.*?)</li>}mi) do
            index += 1
            "#{index}. #{Regexp.last_match(1).strip}\n"
          end.strip
        end
      end

      def decode_html_entities(text)
        text
          .gsub("&amp;", "&")
          .gsub("&lt;", "<")
          .gsub("&gt;", ">")
          .gsub("&quot;", '"')
          .gsub("&#39;", "'")
          .gsub("&nbsp;", " ")
      end
    end
  end
end
