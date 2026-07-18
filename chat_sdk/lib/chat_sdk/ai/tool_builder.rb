# frozen_string_literal: true

module ChatSDK
  module AI
    class ToolBuilder
      PRESETS = {
        reader: %i[fetch_messages fetch_thread],
        messenger: %i[fetch_messages fetch_thread post_message send_direct_message add_reaction start_typing],
        moderator: %i[fetch_messages fetch_thread post_message send_direct_message add_reaction
          edit_message delete_message remove_reaction start_typing]
      }.freeze

      TOOL_DEFINITIONS = {
        fetch_messages: {
          description: "Fetch recent messages from a channel or thread",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name (e.g., 'slack', 'teams')"},
              channel_id: {type: "string", description: "Channel ID"},
              thread_id: {type: "string", description: "Thread ID (optional)"},
              limit: {type: "integer", description: "Max messages to fetch", default: 20}
            },
            required: %w[adapter_name channel_id]
          },
          read_only: true
        },
        fetch_thread: {
          description: "Fetch all messages in a specific thread",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              thread_id: {type: "string", description: "Thread ID"}
            },
            required: %w[adapter_name channel_id thread_id]
          },
          read_only: true
        },
        post_message: {
          description: "Post a message to a channel or thread",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              thread_id: {type: "string", description: "Thread ID (optional, for replies)"},
              text: {type: "string", description: "Message text (markdown)"}
            },
            required: %w[adapter_name channel_id text]
          },
          read_only: false
        },
        send_direct_message: {
          description: "Send a direct message to a user",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              user_id: {type: "string", description: "User ID"},
              text: {type: "string", description: "Message text"}
            },
            required: %w[adapter_name user_id text]
          },
          read_only: false
        },
        edit_message: {
          description: "Edit an existing message",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              message_id: {type: "string", description: "Message ID to edit"},
              text: {type: "string", description: "New message text"}
            },
            required: %w[adapter_name channel_id message_id text]
          },
          read_only: false
        },
        delete_message: {
          description: "Delete a message",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              message_id: {type: "string", description: "Message ID to delete"}
            },
            required: %w[adapter_name channel_id message_id]
          },
          read_only: false
        },
        add_reaction: {
          description: "Add an emoji reaction to a message",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              message_id: {type: "string", description: "Message ID"},
              emoji: {type: "string", description: "Emoji name (e.g., 'thumbsup')"}
            },
            required: %w[adapter_name channel_id message_id emoji]
          },
          read_only: false
        },
        remove_reaction: {
          description: "Remove an emoji reaction from a message",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              message_id: {type: "string", description: "Message ID"},
              emoji: {type: "string", description: "Emoji name"}
            },
            required: %w[adapter_name channel_id message_id emoji]
          },
          read_only: false
        },
        start_typing: {
          description: "Show typing indicator in a channel",
          parameters: {
            type: "object",
            properties: {
              adapter_name: {type: "string", description: "Adapter name"},
              channel_id: {type: "string", description: "Channel ID"},
              thread_id: {type: "string", description: "Thread ID (optional)"}
            },
            required: %w[adapter_name channel_id]
          },
          read_only: false
        }
      }.freeze

      def initialize(preset: :messenger, require_approval: true)
        @preset = preset.to_sym
        @require_approval = require_approval
        raise ChatSDK::ConfigurationError, "Unknown preset: #{@preset}" unless PRESETS.key?(@preset)
      end

      def build
        tool_names = PRESETS[@preset]
        tool_names.each_with_object({}) do |name, tools|
          defn = TOOL_DEFINITIONS[name].dup
          defn[:requires_approval] = @require_approval && !defn[:read_only]
          tools[name] = defn
        end
      end
    end
  end
end
