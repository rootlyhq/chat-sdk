# frozen_string_literal: true

module ChatSDK
  module Events
    # rubocop:disable Style/RedundantStructKeywordInit
    AssistantContext = Struct.new(
      :channel_id,
      :team_id,
      :enterprise_id,
      :thread_entry_point,
      :force_search,
      keyword_init: true
    )
    # rubocop:enable Style/RedundantStructKeywordInit

    def AssistantContext.coerce(value)
      return value if value.is_a?(self)

      value = {} if value.nil?
      return value unless value.is_a?(Hash)

      new(**value.transform_keys(&:to_sym).slice(*members))
    end
  end
end
