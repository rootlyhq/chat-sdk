# frozen_string_literal: true

module ChatSDK
  module Discord
    class FormatConverter < ChatSDK::Format::Converter
      # Discord → Markdown
      def to_markdown(platform_text)
        text = platform_text.to_s
        return "" if text.empty?

        # Convert user mentions: <@123456> → @123456
        text = text.gsub(/<@!?(\d+)>/, '@\1')

        # Convert channel mentions: <#123456> → #123456
        text = text.gsub(/<#(\d+)>/, '#\1')

        # Convert animated custom emoji: <a:name:id> → :name:
        text = text.gsub(/<a:(\w+):\d+>/, ':\1:')

        # Convert custom emoji: <:name:id> → :name:
        text = text.gsub(/<:(\w+):\d+>/, ':\1:')

        # Strip spoiler markers: ||text|| → text
        text.gsub(/\|\|(.+?)\|\|/m, '\1')
      end

      # Markdown → Discord (mostly pass-through since Discord uses standard markdown)
      def from_markdown(markdown)
        text = markdown.to_s
        return "" if text.empty?

        text
      end
    end
  end
end
