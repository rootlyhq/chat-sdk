# frozen_string_literal: true

module ChatSDK
  module Streaming
    MarkdownTextChunk = Data.define(:text) do
      def type
        "markdown_text"
      end

      def to_h
        {type: type, text: text}
      end
    end
  end
end
