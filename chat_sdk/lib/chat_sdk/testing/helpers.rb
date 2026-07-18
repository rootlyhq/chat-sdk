module ChatSDK
  module Testing
    module Helpers
      def build_bot(**options)
        ChatSDK::Testing.build_bot(**options)
      end

      def fake_adapter
        @fake_adapter ||= FakeAdapter.new
      end

      def build_message(text: "hello", user_id: "U123", user_name: "testuser", channel_id: "C123", thread_id: "T123")
        author = Author.new(id: user_id, name: user_name, platform: :test)
        Message.new(
          id: "msg_#{rand(10000..99999)}",
          text: text,
          author: author,
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :test
        )
      end

      def build_card(title: "Test Card", &block)
        ChatSDK.card(title: title, &block)
      end
    end
  end
end
