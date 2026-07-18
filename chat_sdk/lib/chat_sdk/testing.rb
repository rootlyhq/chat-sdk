# frozen_string_literal: true

module ChatSDK
  module Testing
    class << self
      def build_bot(adapters: nil, state: nil, **options)
        adapters ||= {test: FakeAdapter.new}
        state ||= State::Memory.new
        Chat.new(user_name: "test-bot", adapters: adapters, state: state, **options)
      end
    end
  end
end
