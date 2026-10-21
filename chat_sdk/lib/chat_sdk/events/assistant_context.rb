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
  end
end
