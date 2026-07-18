module ChatSDK
  module Adapter
    class Base
      include Capabilities

      def name
        raise NotImplementedError
      end

      def client
        raise NotImplementedError
      end

      # Inbound
      def verify_request!(rack_request)
        raise NotImplementedError
      end

      def ack_response(rack_request)
        nil
      end

      def parse_events(rack_request)
        raise NotImplementedError
      end

      # Outbound
      def post_message(channel_id:, message:, thread_id: nil)
        raise NotImplementedError
      end

      def edit_message(channel_id:, message_id:, message:)
        require_capability!(:edit_messages)
        raise NotImplementedError
      end

      def delete_message(channel_id:, message_id:)
        require_capability!(:delete_messages)
        raise NotImplementedError
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        require_capability!(:ephemeral_messages)
        raise NotImplementedError
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        require_capability!(:file_uploads)
        raise NotImplementedError
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        raise NotImplementedError
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        require_capability!(:reactions)
        raise NotImplementedError
      end

      def open_dm(user_id)
        require_capability!(:direct_messages)
        raise NotImplementedError
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        require_capability!(:message_history)
        raise NotImplementedError
      end

      def open_modal(trigger_id:, modal:)
        require_capability!(:modals)
        raise NotImplementedError
      end

      def start_typing(channel_id:, thread_id: nil)
        require_capability!(:typing_indicator)
        raise NotImplementedError
      end

      def mention(user_id)
        raise NotImplementedError
      end

      def render(postable_message)
        Cards::Renderer.new.render(postable_message.card)
      end

      private

      def require_capability!(cap)
        raise NotSupportedError.new(cap, name) unless supports?(cap)
      end
    end
  end
end
