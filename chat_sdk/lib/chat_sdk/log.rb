require "logger"

module ChatSDK
  module Log
    class << self
      attr_writer :logger

      def logger
        @logger ||= ::Logger.new($stdout, progname: "ChatSDK")
      end

      %i[debug info warn error fatal].each do |level|
        define_method(level) { |msg = nil, &block| logger.send(level, msg, &block) }
      end

      def level=(level)
        logger.level = level
      end
    end
  end
end
