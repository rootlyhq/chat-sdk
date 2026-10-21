# frozen_string_literal: true

module ChatSDK
  class Message
    attr_reader :id, :text, :author, :thread_id, :channel_id,
      :platform, :attachments, :links, :reply_to, :subject, :raw, :timestamp
    attr_accessor :is_mention

    def initialize(id:, text:, author:, thread_id:, channel_id:, platform:,
      attachments: [], links: [], reply_to: nil, subject: nil, raw: nil,
      timestamp: nil, is_mention: nil)
      @id = id
      @text = text
      @author = author
      @thread_id = thread_id
      @channel_id = channel_id
      @platform = platform
      @attachments = attachments
      @links = links
      @reply_to = reply_to
      @subject = subject
      @raw = raw
      @timestamp = timestamp
      @is_mention = is_mention
    end

    def ==(other)
      other.is_a?(Message) && id == other.id && platform == other.platform
    end
    alias_method :eql?, :==

    def hash
      [id, platform].hash
    end
  end
end
