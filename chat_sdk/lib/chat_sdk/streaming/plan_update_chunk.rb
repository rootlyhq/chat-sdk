# frozen_string_literal: true

module ChatSDK
  module Streaming
    PlanUpdateChunk = Data.define(:title) do
      def type
        "plan_update"
      end

      def to_h
        {type: type, title: title}
      end
    end
  end
end
