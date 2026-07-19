# frozen_string_literal: true

module ChatSDK
  module Twilio
    class EventParser
      class << self
        def parse(params)
          return [] unless params.is_a?(Hash) && params["MessageSid"]

          author = ChatSDK::Author.new(
            id: params["From"] || "unknown",
            name: params["From"] || "unknown",
            platform: :twilio,
            bot: false
          )

          attachments = extract_attachments(params)

          text = params["Body"] || ""
          text = "#{text}\n#{attachments.map { |a| a[:url] }.join("\n")}" if attachments.any? && !text.empty?
          text = attachments.map { |a| a[:url] }.join("\n") if attachments.any? && (params["Body"].nil? || params["Body"].empty?)

          msg = ChatSDK::Message.new(
            id: params["MessageSid"],
            text: text,
            author: author,
            thread_id: params["MessageSid"],
            channel_id: params["To"] || "unknown",
            platform: :twilio,
            raw: params
          )

          [ChatSDK::Events::DirectMessage.new(
            message: msg,
            thread_id: params["MessageSid"],
            channel_id: params["To"] || "unknown",
            platform: :twilio,
            adapter_name: :twilio,
            raw: params
          )]
        end

        private

        def extract_attachments(params)
          num_media = (params["NumMedia"] || "0").to_i
          return [] if num_media.zero?

          (0...num_media).map do |i|
            {
              url: params["MediaUrl#{i}"],
              content_type: params["MediaContentType#{i}"]
            }
          end
        end
      end
    end
  end
end
