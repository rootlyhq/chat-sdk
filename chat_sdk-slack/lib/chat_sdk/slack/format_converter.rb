# frozen_string_literal: true

module ChatSDK
  module Slack
    class FormatConverter < ChatSDK::Format::Converter
      # Slack mrkdwn -> standard Markdown
      def to_markdown(mrkdwn)
        return "" if mrkdwn.nil? || mrkdwn.empty?

        parts = split_code_blocks(mrkdwn)
        parts.map.with_index { |part, i| i.odd? ? part : convert_mrkdwn_to_md(part) }.join
      end

      # Standard Markdown -> Slack mrkdwn
      def from_markdown(markdown)
        return "" if markdown.nil? || markdown.empty?

        parts = split_code_blocks(markdown)
        parts.map.with_index { |part, i| i.odd? ? part : convert_md_to_mrkdwn(part) }.join
      end

      private

      # ── Slack mrkdwn → Markdown ──────────────────────────────────────────

      def convert_mrkdwn_to_md(text)
        result = text

        # Mentions must be processed before generic links to avoid <#C123|name> matching <url|text>
        # User mentions: <@U123ABC> -> @U123ABC
        result = result.gsub(/<@([A-Z0-9]+)>/, '@\1')

        # Channel mentions with label: <#C123|general> -> #general
        result = result.gsub(/<#[A-Z0-9]+\|([^>]+)>/, '#\1')

        # Channel mentions without label: <#C123> -> #C123
        result = result.gsub(/<#([A-Z0-9]+)>/, '#\1')

        # Special mentions: <!everyone>, <!here>, <!channel>
        result = result.gsub("<!everyone>", "@everyone")
        result = result.gsub("<!here>", "@here")
        result = result.gsub("<!channel>", "@channel")

        # Links with labels: <url|text> -> [text](url) (after mentions are consumed)
        result = result.gsub(/<([^>|]+)\|([^>]+)>/) { "[#{Regexp.last_match(2)}](#{Regexp.last_match(1)})" }

        # Bare links: <url> -> url (must come after labeled links)
        result = result.gsub(/<([^@#!][^>|]*)>/, '\1')

        # Bold: *text* -> **text** (only single asterisks, not already doubled)
        # Negative lookbehind/lookahead to avoid matching inside ** pairs
        result = result.gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, '**\1**')

        # Italic: _text_ -> *text*
        result = result.gsub(/(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])/, '*\1*')

        # Strikethrough: ~text~ -> ~~text~~
        result = result.gsub(/(?<!~)~(?!~)(.+?)(?<!~)~(?!~)/, '~~\1~~')

        # HTML entities (must come last so earlier patterns can match on encoded text)
        result = result.gsub("&gt;", ">")
        result = result.gsub("&lt;", "<")
        result.gsub("&amp;", "&")
      end

      # ── Markdown → Slack mrkdwn ──────────────────────────────────────────

      def convert_md_to_mrkdwn(text)
        result = text

        # Links: [text](url) -> <url|text>
        result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "<#{Regexp.last_match(2)}|#{Regexp.last_match(1)}>" }

        # Bold/italic with placeholder to prevent double conversion
        result = convert_bold_and_italic_from_md(result, bold_char: "*", italic_char: "_")

        # Strikethrough: ~~text~~ -> ~text~
        result = result.gsub(/~~(.+?)~~/, '~\1~')

        # Blockquote lines: > text -> &gt; text (only at line start)
        result.gsub(/^> /m, "&gt; ")

        # HTML entities for remaining special chars are not converted here —
        # Slack handles raw < > & in normal text. Only blockquote > needs encoding.
      end
    end
  end
end
