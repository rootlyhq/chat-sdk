# frozen_string_literal: true

module ChatSDK
  module Streaming
    TASK_UPDATE_STATUSES = %w[pending in_progress complete error].freeze
    private_constant :TASK_UPDATE_STATUSES

    TaskUpdateChunk = Data.define(:id, :title, :status, :details, :output) do
      def initialize(id:, title:, status:, details: nil, output: nil)
        unless TASK_UPDATE_STATUSES.include?(status.to_s)
          raise ArgumentError, "status must be one of #{TASK_UPDATE_STATUSES.join(", ")}"
        end

        super(id: id, title: title, status: status.to_s, details: details, output: output)
      end

      def type
        "task_update"
      end

      def to_h
        {type: type, id: id, title: title, status: status, details: details, output: output}.compact
      end
    end
  end
end
