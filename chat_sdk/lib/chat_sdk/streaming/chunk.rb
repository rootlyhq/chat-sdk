# frozen_string_literal: true

module ChatSDK
  module Streaming
    module Chunk
      module_function

      def normalize(value)
        return value if value.is_a?(MarkdownTextChunk) || value.is_a?(TaskUpdateChunk) || value.is_a?(PlanUpdateChunk)

        if value.is_a?(Hash)
          type = value[:type] || value["type"]
          attributes = value.each_with_object({}) do |(key, entry), result|
            result[key.to_sym] = entry
          end

          return MarkdownTextChunk.new(text: attributes[:text]) if type.to_s == "markdown_text"
          return TaskUpdateChunk.new(**attributes.except(:type)) if type.to_s == "task_update"
          return PlanUpdateChunk.new(**attributes.except(:type)) if type.to_s == "plan_update"

          return nil
        end

        value.to_s
      end

      def text_of(value)
        case value
        when String then value
        when MarkdownTextChunk then value.text
        end
      end
    end
  end
end
