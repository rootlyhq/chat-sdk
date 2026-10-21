# frozen_string_literal: true

module ChatSDK
  class StreamingPlan
    GROUP_TASKS = %w[plan timeline].freeze

    attr_reader :stream, :options

    def initialize(stream, group_tasks: nil, end_with: nil, update_interval: nil, ai_generated: false)
      if group_tasks && !GROUP_TASKS.include?(group_tasks.to_s)
        raise ArgumentError, "group_tasks must be :plan or :timeline"
      end

      @stream = stream
      @options = {
        group_tasks: group_tasks&.to_s,
        end_with: end_with,
        update_interval: update_interval,
        ai_generated: ai_generated
      }.compact
    end

    def to_stream_options
      {
        task_display_mode: options[:group_tasks],
        stop_blocks: options[:end_with],
        update_interval: options[:update_interval],
        ai_generated: (true if options[:ai_generated])
      }.compact
    end
  end
end
