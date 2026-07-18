module ChatSDK
  class Chat
    attr_reader :config, :state

    def initialize(user_name:, adapters:, state:, **options)
      @config = Config.new(user_name: user_name, adapters: adapters, state: state, **options)
      @state = state
      @adapters = adapters
      @registry = EventRegistry.new
      @webhooks = {}

      ChatSDK::Log.level = @config.log_level
    end

    # Event registration
    def on_new_mention(&block)
      @registry.register(:mention, &block)
    end

    def on_subscribed_message(&block)
      @registry.register(:subscribed_message, &block)
    end

    def on_new_message(pattern = nil, &block)
      @registry.register(:mention, matcher: pattern, &block)
    end

    def on_direct_message(&block)
      @registry.register(:direct_message, &block)
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

    # Webhook endpoints (Rack apps)
    def webhooks
      @webhook_accessor ||= WebhookAccessor.new(self, @adapters)
    end

    # Event dispatch (called by webhook endpoints)
    def dispatch(event, adapter_name:)
      adp = adapter(adapter_name)

      handlers = @registry.handlers_for(event)
      return if handlers.empty?

      thread = build_thread(event, adp)

      handlers.each do |handler|
        execute_handler(handler, event, thread)
      end
    rescue => e
      ChatSDK::Log.error("Error dispatching event: #{e.message}")
      ChatSDK::Log.debug(e.backtrace&.first(5)&.join("\n"))
    end

    private

    def build_thread(event, adapter)
      thread_id = extract_thread_id(event)
      channel_id = extract_channel_id(event)
      return nil unless thread_id && channel_id

      ChatSDK::Thread.new(id: thread_id, channel_id: channel_id, adapter: adapter, chat: self)
    end

    def extract_thread_id(event)
      return event.thread_id if event.respond_to?(:thread_id)
      nil
    end

    def extract_channel_id(event)
      return event.channel_id if event.respond_to?(:channel_id)
      nil
    end

    def execute_handler(handler, event, thread)
      case event.type
      when :mention, :subscribed_message, :direct_message
        handler.block.call(thread, event.message)
      when :reaction, :action, :slash_command
        add_thread_to_event(event, thread)
        handler.block.call(event)
      end
    rescue => e
      ChatSDK::Log.error("Handler error (#{event.type}): #{e.message}")
      ChatSDK::Log.debug(e.backtrace&.first(5)&.join("\n"))
    end

    def add_thread_to_event(event, thread)
      event.instance_variable_set(:@thread, thread)
      unless event.respond_to?(:thread)
        event.define_singleton_method(:thread) { @thread }
      end
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
