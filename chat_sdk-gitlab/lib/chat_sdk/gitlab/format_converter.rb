# frozen_string_literal: true

module ChatSDK
  module GitLab
    class FormatConverter < ChatSDK::Format::Converter
      def to_markdown(platform_text)
        platform_text.to_s
      end

      def from_markdown(markdown)
        markdown.to_s
      end
    end
  end
end
