# frozen_string_literal: true

module ChatSDK
  module Linear
    class EventParser
      class << self
        def parse(payload, bot_username: nil)
          return [] unless payload.is_a?(Hash)
          return [] unless payload["type"] == "Comment" && payload["action"] == "create"

          data = payload["data"] || {}
          comment_id = data["id"]
          body = data["body"] || ""
          issue_id = data["issueId"] || data.dig("issue", "id")
          user = data["user"] || {}
          user_id = user["id"]
          user_name = user["name"]

          return [] if bot_username && user_name == bot_username

          thread_id = "linear:#{issue_id}:c:#{comment_id}"

          author = ChatSDK::Author.new(
            id: user_id || "unknown",
            name: user_name || "unknown",
            platform: :linear,
            bot: false
          )

          msg = ChatSDK::Message.new(
            id: comment_id&.to_s,
            text: body,
            author: author,
            thread_id: thread_id,
            channel_id: issue_id,
            platform: :linear,
            raw: data
          )

          [
            ChatSDK::Events::Mention.new(
              message: msg,
              thread_id: thread_id,
              channel_id: issue_id,
              platform: :linear,
              adapter_name: :linear,
              raw: data
            )
          ]
        end
      end
    end
  end
end
