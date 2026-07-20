# frozen_string_literal: true

module ChatSDK
  module Telegram
    class FormatConverter < ChatSDK::Format::Converter
      SPECIAL_CHARS = %w[_ * [ ] ( ) ~ \\ ` > # + - = | { } . !].freeze
      ESCAPE_RE = Regexp.union(SPECIAL_CHARS).freeze

      # Telegram MarkdownV2 → standard Markdown
      def to_markdown(platform_text)
        text = platform_text.to_s
        return "" if text.empty?

        # Convert Telegram user links: [text](tg://user?id=123) → @123
        text = text.gsub(/\[([^\]]*)\]\(tg:\/\/user\?id=(\d+)\)/, '@\2')

        # Strip underline markers: __text__ → text
        # Use a loop to handle nested cases
        text = text.gsub(/(?<!_)__(?!_)(.+?)(?<!_)__(?!_)/m, '\1')

        # Strip spoiler markers: ||text|| → text
        text = text.gsub(/\|\|(.+?)\|\|/m, '\1')

        # Unescape all backslash-escaped characters
        text.gsub(/\\(.)/, '\1')
      end

      # Standard Markdown → Telegram MarkdownV2
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        parts = split_code_segments(text)
        parts.map.with_index { |part, i| i.odd? ? part : escape_special_chars(part) }.join
      end

      private

      # Splits text into alternating [text, code, text, code, ...] segments.
      # Odd-indexed segments are code blocks/inline code and are NOT escaped.
      def split_code_segments(text)
        text.split(/(```[\s\S]*?```|`[^`]+`)/)
      end

      # Escape Telegram MarkdownV2 special chars outside of markdown syntax.
      # Preserves bold (**), italic (*), strikethrough (~~), links, etc.
      def escape_special_chars(text)
        result = +""
        i = 0
        chars = text.chars

        while i < chars.length
          char = chars[i]

          # Bold: **text** — pass through
          if char == "*" && chars[i + 1] == "*"
            close = text.index("**", i + 2)
            if close
              inner = text[(i + 2)...close]
              result << "**#{escape_special_chars(inner)}**"
              i = close + 2
              next
            end
          end

          # Italic: *text* (single asterisk, not preceded/followed by another *)
          if char == "*" && chars[i + 1] != "*"
            close = find_single_asterisk_close(chars, i + 1)
            if close
              inner = chars[(i + 1)...close].join
              result << "*#{escape_special_chars(inner)}*"
              i = close + 1
              next
            end
          end

          # Strikethrough: ~~text~~
          if char == "~" && chars[i + 1] == "~"
            close = text.index("~~", i + 2)
            if close
              inner = text[(i + 2)...close]
              result << "~~#{escape_special_chars(inner)}~~"
              i = close + 2
              next
            end
          end

          # Links: [text](url) — pass through
          if char == "["
            link_match = text[i..].match(/\A\[([^\]]*)\]\(([^)]*)\)/)
            if link_match
              result << link_match[0]
              i += link_match[0].length
              next
            end
          end

          # Escape special characters
          result << if SPECIAL_CHARS.include?(char)
            "\\#{char}"
          else
            char
          end

          i += 1
        end

        result
      end

      # Find closing single * that isn't part of **
      def find_single_asterisk_close(chars, start)
        i = start
        while i < chars.length
          if chars[i] == "*" && chars[i + 1] != "*" && (i == start || chars[i - 1] != "*")
            return i
          end
          i += 1
        end
        nil
      end
    end
  end
end
