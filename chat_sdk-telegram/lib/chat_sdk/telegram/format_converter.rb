# frozen_string_literal: true

module ChatSDK
  module Telegram
    class FormatConverter < ChatSDK::Format::Converter
      SPECIAL_CHARS = %w[_ * [ ] ( ) ~ \\ ` > # + - = | { } . !].freeze

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

        parts = split_code_blocks(text)
        parts.map.with_index { |part, i| i.odd? ? part : escape_special_chars(part) }.join
      end

      def truncate_markdown_v2(text, limit)
        text = text.to_s
        return text if text.length <= limit

        ellipsis = "\\.\\.\\."
        slice = text[0, limit - ellipsis.length]
        "#{trim_to_safe_boundary(slice)}#{ellipsis}"
      end

      private

      def trim_to_safe_boundary(text)
        text = text[0...-1] while trailing_backslashes(text).odd?
        link_start = incomplete_link_start(text)
        text = text[0...link_start] if link_start

        masked_links = mask_links(text)
        masked, incomplete_code_start = mask_code_spans(masked_links)
        text = text[0...incomplete_code_start] if incomplete_code_start
        return text unless incomplete_code_start.nil?

        marker_positions = Hash.new { |hash, key| hash[key] = [] }
        chars = masked.chars
        index = 0
        while index < chars.length
          if chars[index] == "\\"
            index += 2
            next
          end
          if %w[* _ ~].include?(chars[index])
            run_length = 1
            run_length += 1 while chars[index + run_length] == chars[index]
            marker_positions[[chars[index], run_length]] << index
            index += run_length
          else
            index += 1
          end
        end

        cut = marker_positions.values
          .select { |positions| positions.length.odd? }
          .map(&:last)
          .min
        cut ? text[0...cut] : text
      end

      def trailing_backslashes(text)
        text[/\\+\z/].to_s.length
      end

      def incomplete_link_start(text)
        chars = text.chars
        openings = []
        index = 0
        while index < chars.length
          if chars[index] == "\\"
            index += 2
            next
          elsif chars[index] == "["
            openings << index
          elsif chars[index] == "]" && !openings.empty?
            opening = openings.pop
            if chars[index + 1] == "("
              closing = index + 2
              closing += 1 while closing < chars.length &&
                  (chars[closing] != ")" || escaped_at?(chars, closing))
              return opening if closing == chars.length
            end
          end
          index += 1
        end
        openings.last
      end

      def mask_code_spans(text)
        chars = text.chars
        masked = chars.dup
        index = 0
        while index < chars.length
          if chars[index] == "\\"
            index += 2
            next
          end
          unless chars[index] == "`"
            index += 1
            next
          end

          run_length = 1
          run_length += 1 while chars[index + run_length] == "`"
          closing = index + run_length
          closing += 1 while closing < chars.length &&
              !(chars[closing] == "`" && backtick_run_length(chars, closing) == run_length)
          return [masked.join, index] if closing >= chars.length

          closing_end = closing + run_length
          (index...closing_end).each { |position| masked[position] = " " }
          index = closing_end
        end
        [masked.join, nil]
      end

      def mask_links(text)
        chars = text.chars
        masked = chars.dup
        openings = []
        index = 0
        while index < chars.length
          if chars[index] == "\\"
            index += 2
            next
          elsif chars[index] == "["
            openings << index
          elsif chars[index] == "]" && !openings.empty? && chars[index + 1] == "("
            opening = openings.pop
            closing = index + 2
            closing += 1 while closing < chars.length &&
                (chars[closing] != ")" || escaped_at?(chars, closing))
            if closing < chars.length
              (opening..closing).each { |position| masked[position] = " " }
              index = closing
            end
          end
          index += 1
        end
        masked.join
      end

      def backtick_run_length(chars, index)
        length = 1
        length += 1 while chars[index + length] == "`"
        length
      end

      def escaped_at?(chars, index)
        backslashes = 0
        backslashes += 1 while index - backslashes - 1 >= 0 &&
            chars[index - backslashes - 1] == "\\"
        backslashes.odd?
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
