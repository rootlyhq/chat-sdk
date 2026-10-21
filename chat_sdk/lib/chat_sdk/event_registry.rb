# frozen_string_literal: true

module ChatSDK
  class EventRegistry
    Handler = Struct.new(:type, :matcher, :block)

    def initialize
      @handlers = []
    end

    def register(type, matcher: nil, &block)
      @handlers << Handler.new(type: type, matcher: matcher, block: block)
    end

    def handlers_for(event)
      handlers_for_type(event.type, event: event)
    end

    def handlers_for_type(type, event: nil)
      @handlers.select do |handler|
        handler.type == type && (!event || matches?(handler, event))
      end
    end

    private

    def matches?(handler, event)
      return true if handler.matcher.nil?

      case handler.matcher
      when Regexp
        event.respond_to?(:message) && handler.matcher.match?(event.message&.text)
      when String
        case event.type
        when :action then event.action_id == handler.matcher
        when :slash_command then event.command == handler.matcher
        else false
        end
      when Array
        event.type == :reaction && handler.matcher.include?(event.emoji)
      else
        false
      end
    end
  end
end
