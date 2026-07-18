# frozen_string_literal: true

module ChatSDK
  module Testing
    class FakeAdapter < Adapter::Base
      capabilities :edit_messages, :delete_messages, :ephemeral_messages,
        :file_uploads, :reactions, :modals, :typing_indicator,
        :streaming_edit, :threads, :direct_messages, :message_history

      attr_reader :posted_messages, :edited_messages, :deleted_messages,
        :ephemeral_messages_sent, :reactions_added, :reactions_removed,
        :files_uploaded, :modals_opened, :typing_started, :dm_channels

      def initialize
        reset!
      end

      def name
        :test
      end

      def client
        self
      end

      def verify_request!(rack_request)
        true
      end

      def ack_response(rack_request)
        nil
      end

      def parse_events(rack_request)
        []
      end

      def post_message(channel_id:, message:, thread_id: nil)
        record = RecordedCall.new(:post_message, channel_id: channel_id, message: message, thread_id: thread_id)
        @posted_messages << record
        Message.new(
          id: "msg_#{@posted_messages.size}",
          text: message.is_a?(PostableMessage) ? message.text : message.to_s,
          author: Author.new(id: "bot", name: "test-bot", platform: :test, bot: true),
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :test
        )
      end

      def edit_message(channel_id:, message_id:, message:)
        record = RecordedCall.new(:edit_message, channel_id: channel_id, message_id: message_id, message: message)
        @edited_messages << record
        record
      end

      def delete_message(channel_id:, message_id:)
        record = RecordedCall.new(:delete_message, channel_id: channel_id, message_id: message_id)
        @deleted_messages << record
        record
      end

      def post_ephemeral(channel_id:, user_id:, message:, thread_id: nil)
        record = RecordedCall.new(:post_ephemeral, channel_id: channel_id, user_id: user_id, message: message, thread_id: thread_id)
        @ephemeral_messages_sent << record
        record
      end

      def upload_file(channel_id:, io:, filename:, thread_id: nil, comment: nil)
        record = RecordedCall.new(:upload_file, channel_id: channel_id, filename: filename, thread_id: thread_id, comment: comment)
        @files_uploaded << record
        record
      end

      def add_reaction(channel_id:, message_id:, emoji:)
        record = RecordedCall.new(:add_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji)
        @reactions_added << record
        record
      end

      def remove_reaction(channel_id:, message_id:, emoji:)
        record = RecordedCall.new(:remove_reaction, channel_id: channel_id, message_id: message_id, emoji: emoji)
        @reactions_removed << record
        record
      end

      def open_dm(user_id)
        channel_id = "dm_#{user_id}"
        @dm_channels << RecordedCall.new(:open_dm, user_id: user_id, channel_id: channel_id)
        channel_id
      end

      def fetch_messages(channel_id:, thread_id: nil, cursor: nil, limit: 50)
        [[], nil]
      end

      def open_modal(trigger_id:, modal:)
        record = RecordedCall.new(:open_modal, trigger_id: trigger_id, modal: modal)
        @modals_opened << record
        record
      end

      def start_typing(channel_id:, thread_id: nil)
        record = RecordedCall.new(:start_typing, channel_id: channel_id, thread_id: thread_id)
        @typing_started << record
        record
      end

      def mention(user_id)
        "<@#{user_id}>"
      end

      def render(postable_message)
        Cards::Renderer.new.render(postable_message.card)
      end

      # Simulation helpers
      def simulate_mention(chat, text:, user_id: "U123", user_name: "testuser", channel_id: "C123", thread_id: nil)
        thread_id ||= "T#{rand(1000..9999)}"
        author = Author.new(id: user_id, name: user_name, platform: :test)
        message = Message.new(
          id: "evt_#{rand(10000..99999)}",
          text: text,
          author: author,
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :test
        )
        event = Events::Mention.new(
          message: message,
          thread_id: thread_id,
          channel_id: channel_id,
          platform: :test,
          adapter_name: :test
        )
        chat.dispatch(event, adapter_name: :test)
      end

      def simulate_action(chat, action_id:, value: nil, user_id: "U123", channel_id: "C123", thread_id: "T123", trigger_id: nil)
        user = Author.new(id: user_id, name: "testuser", platform: :test)
        event = Events::Action.new(
          action_id: action_id,
          value: value,
          user: user,
          thread_id: thread_id,
          channel_id: channel_id,
          trigger_id: trigger_id,
          platform: :test,
          adapter_name: :test
        )
        chat.dispatch(event, adapter_name: :test)
      end

      def simulate_reaction(chat, emoji:, user_id: "U123", message_id: "M123", channel_id: "C123", thread_id: "T123", added: true)
        event = Events::Reaction.new(
          emoji: emoji,
          user_id: user_id,
          message_id: message_id,
          thread_id: thread_id,
          channel_id: channel_id,
          added: added,
          platform: :test,
          adapter_name: :test
        )
        chat.dispatch(event, adapter_name: :test)
      end

      def simulate_slash_command(chat, command:, text: "", user_id: "U123", channel_id: "C123", trigger_id: nil)
        event = Events::SlashCommand.new(
          command: command,
          text: text,
          user_id: user_id,
          channel_id: channel_id,
          trigger_id: trigger_id,
          platform: :test,
          adapter_name: :test
        )
        chat.dispatch(event, adapter_name: :test)
      end

      def reset!
        @posted_messages = []
        @edited_messages = []
        @deleted_messages = []
        @ephemeral_messages_sent = []
        @reactions_added = []
        @reactions_removed = []
        @files_uploaded = []
        @modals_opened = []
        @typing_started = []
        @dm_channels = []
      end
    end
  end
end
