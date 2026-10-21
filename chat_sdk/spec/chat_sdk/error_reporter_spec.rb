# frozen_string_literal: true

require_relative "../../../spec/spec_helper"
require "logger"
require "stringio"

RSpec.describe ChatSDK::ErrorReporter do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }

  around do |example|
    original_logger = ChatSDK::Log.logger
    example.run
  ensure
    ChatSDK::Log.logger = original_logger
  end

  before do
    ChatSDK::Log.logger = logger
  end

  describe "#report" do
    it "logs exception details, context, and the full backtrace at error level" do
      error = RuntimeError.new("something failed")
      error.set_backtrace(%w[app/bot.rb:10 app/worker.rb:20])

      described_class.new.report(error, "Handler error", source: :handler, adapter: :slack)

      expect(log_output.string).to include("ERROR", "Handler error (source=handler adapter=slack)")
      expect(log_output.string).to include("RuntimeError: something failed", "app/bot.rb:10", "app/worker.rb:20")
    end

    it "calls the configured callback with compacted context" do
      error = RuntimeError.new("failure")
      callback = double(:callback)
      expect(callback).to receive(:call).with(error, {source: :webhook, adapter: :slack})

      described_class.new(callback).report(error, "Webhook error", source: :webhook, adapter: :slack, thread_id: nil)
    end

    it "reports to Rails.error when no callback is configured" do
      error = RuntimeError.new("failure")
      rails_reporter = double(:rails_reporter)
      expect(rails_reporter).to receive(:report).with(
        error,
        handled: true,
        severity: :error,
        context: {source: :handler}
      )
      stub_const("Rails", double(error: rails_reporter))

      described_class.new.report(error, "Handler error", source: :handler)
    end

    it "does nothing when Rails.error is unavailable" do
      hide_const("Rails") if Object.const_defined?(:Rails)

      expect {
        described_class.new.report(RuntimeError.new("failure"), "Handler error")
      }.not_to raise_error
    end

    it "logs callback failures without raising" do
      callback = ->(_error, _context) { raise "callback failed" }

      expect {
        described_class.new(callback).report(RuntimeError.new("failure"), "Handler error")
      }.not_to raise_error
      expect(log_output.string).to include("on_error callback failed: RuntimeError: callback failed")
    end
  end
end
