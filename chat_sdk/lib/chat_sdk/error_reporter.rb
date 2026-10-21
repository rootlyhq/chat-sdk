# frozen_string_literal: true

module ChatSDK
  class ErrorReporter
    def initialize(callback = nil)
      @callback = callback
    end

    def report(error, message, **context)
      context = context.compact
      ChatSDK::Log.error(format_entry(error, message, context))
      reporter = @callback || self.class.default_callback
      reporter&.call(error, context)
    rescue => e
      ChatSDK::Log.error("on_error callback failed: #{e.class}: #{e.message}")
    end

    def self.default_callback
      return unless defined?(::Rails) && ::Rails.respond_to?(:error)

      rails_reporter = ::Rails.error
      return unless rails_reporter.respond_to?(:report)

      ->(error, context) { rails_reporter.report(error, handled: true, severity: :error, context: context) }
    end

    private

    def format_entry(error, message, context)
      details = context.empty? ? "" : " (#{context.map { |key, value| "#{key}=#{value}" }.join(" ")})"
      entry = "#{message}#{details}: #{error.class}: #{error.message}"
      backtrace = error.backtrace
      backtrace ? "#{entry}\n#{backtrace.join("\n")}" : entry
    end
  end
end
