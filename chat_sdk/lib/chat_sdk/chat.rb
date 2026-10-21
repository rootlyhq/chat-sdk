# frozen_string_literal: true

module ChatSDK
  class Chat
    attr_reader :config, :state, :history
    # @api private
    attr_reader :error_reporter

    def initialize(user_name:, adapters:, state:, **options)
      @config = Config.new(user_name: user_name, adapters: adapters, state: state, **options)
      @state = state
      ChatSDK::Log.logger = @config.logger if @config.logger
      ChatSDK::Log.level = @config.log_level if @config.log_level
      @adapters = adapters
      @adapters.each_value { |adapter| adapter.set_state(state) if adapter.respond_to?(:set_state) }
      @registry = EventRegistry.new
      @history = History.new(self)
      @webhooks = {}
      @error_reporter = ErrorReporter.new(@config.on_error)
      @dispatcher = Dispatcher.new(
        chat: self,
        config: @config,
        state: @state,
        registry: @registry,
        error_reporter: @error_reporter
      )
    end

    # Event registration
    def on_new_mention(&block)
      @registry.register(:mention, &block)
    end

    def on_subscribed_message(&block)
      @registry.register(:subscribed_message, &block)
    end

    def on_new_message(pattern = nil, &block)
      unless pattern.nil? || pattern.is_a?(Regexp)
        raise ChatSDK::ConfigurationError, "on_new_message pattern must be a Regexp or nil"
      end
      raise ChatSDK::ConfigurationError, "on_new_message requires a block" unless block

      @registry.register(:new_message, matcher: pattern, &block)
    end

    def on_direct_message(&block)
      @registry.register(:direct_message, &block)
    end

    def on_message_updated(&block)
      @registry.register(:message_updated, &block)
    end

    def on_message_deleted(&block)
      @registry.register(:message_deleted, &block)
    end

    def on_reaction(emojis = nil, &block)
      @registry.register(:reaction, matcher: emojis, &block)
    end

    def on_action(action_id, &block)
      @registry.register(:action, matcher: action_id, &block)
    end

    def on_slash_command(command, &block)
      @registry.register(:slash_command, matcher: command, &block)
    end

    def on_installed(&block)
      @registry.register(:installed, &block)
    end

    def on_uninstalled(&block)
      @registry.register(:uninstalled, &block)
    end

    # Adapter access
    def adapter(name)
      @adapters.fetch(name) { raise ChatSDK::ConfigurationError, "Unknown adapter: #{name}" }
    end

    # Channel/DM access
    def channel(id, adapter_name: nil)
      adp = adapter_name ? adapter(adapter_name) : @adapters.values.first
      Channel.new(id: id, adapter: adp, chat: self)
    end

    def open_dm(user_id, adapter_name: nil)
      adp = adapter_name ? adapter(adapter_name) : @adapters.values.first
      channel_id = adp.open_dm(user_id)
      Channel.new(id: channel_id, adapter: adp, chat: self)
    end

    def thread(id, channel_id:, adapter_name: nil)
      adp = adapter_name ? adapter(adapter_name) : @adapters.values.first
      Thread.new(id: id, channel_id: channel_id, adapter: adp, chat: self)
    end

    # Webhook endpoints (Rack apps)
    def webhooks
      @webhook_accessor ||= WebhookAccessor.new(self, @adapters)
    end

    # Event dispatch (called by webhook endpoints)
    def dispatch(event, adapter_name:)
      adp = adapter(adapter_name)
      executor = @config.handler_executor
      return @dispatcher.dispatch(event, adapter: adp, adapter_name: adapter_name) if executor == :inline

      if executor == :thread
        ::Thread.new { run_background_dispatch(event, adp, adapter_name) }
      else
        payload = {"adapter_name" => adapter_name.to_s, "event" => EventSerializer.dump(event)}
        begin
          executor.call(payload)
        rescue => e
          raise HandlerExecutorError, "handler_executor failed for #{event.type}: #{e.class}: #{e.message}"
        end
      end
      nil
    end

    # Runs a payload produced for a callable handler_executor, such as from a background job.
    def dispatch_serialized(payload)
      payload = payload.transform_keys(&:to_s)
      adapter_name = payload.fetch("adapter_name").to_sym
      event = EventSerializer.load(payload.fetch("event"))
      @dispatcher.dispatch(event, adapter: adapter(adapter_name), adapter_name: adapter_name)
    end

    # Deprecated compatibility alias for Vercel Chat SDK's former API.
    def transcripts
      history.user
    end

    private

    def run_background_dispatch(event, adp, adapter_name)
      @dispatcher.dispatch(event, adapter: adp, adapter_name: adapter_name)
    rescue => e
      # Nothing above this background thread can rescue errors raised during dispatch.
      @error_reporter.report(
        e,
        "Background dispatch error (#{event.type})",
        source: :dispatch,
        adapter: adapter_name,
        event_type: event.type,
        thread_id: event.respond_to?(:thread_id) ? event.thread_id : nil,
        channel_id: event.respond_to?(:channel_id) ? event.channel_id : nil
      )
    end
  end

  class WebhookAccessor
    def initialize(chat, adapters)
      @chat = chat
      @adapters = adapters
      @endpoints = {}
    end

    def [](adapter_name)
      @endpoints[adapter_name] ||= Webhook::Endpoint.new(chat: @chat, adapter: @chat.adapter(adapter_name), adapter_name: adapter_name)
    end

    def router
      @router ||= Webhook::Router.new(@chat, @adapters)
    end
  end
end
