# frozen_string_literal: true

module ChatSDK
  class PostableMessage
    attr_reader :text, :card, :attachments, :metadata

    def initialize(text: nil, card: nil, attachments: [], metadata: {})
      raise ArgumentError, "text or card required" if text.nil? && card.nil?
      @text = text
      @card = card
      @attachments = attachments
      @metadata = metadata
    end

    def card?
      !@card.nil?
    end

    def self.from(content)
      case content
      when PostableMessage then content
      when String then new(text: content)
      when Cards::Node then new(card: content, text: content.fallback_text)
      else raise ArgumentError, "cannot convert #{content.class} to PostableMessage"
      end
    end
  end
end
