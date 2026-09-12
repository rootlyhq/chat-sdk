# frozen_string_literal: true

module ChatSDK
  class Config
    DEFAULTS = {
      dedupe_ttl: 600,
      streaming_update_interval: 0.5,
      on_lock_conflict: :drop,
      concurrency: nil,
      lock_scope: :thread,
      handler_executor: :inline,
      history: {},
      log_level: :info
    }.freeze

    attr_reader :user_name, :adapters, :state, :on_lock_conflict,
      :dedupe_ttl, :streaming_update_interval, :handler_executor, :log_level,
      :history_user, :concurrency

    def initialize(user_name:, adapters:, state:, **options)
      raise ConfigurationError, "user_name is required" if user_name.nil? || user_name.empty?
      raise ConfigurationError, "adapters hash is required" if adapters.nil? || adapters.empty?
      raise ConfigurationError, "state adapter is required" if state.nil?

      @user_name = user_name
      @adapters = adapters
      @state = state
      merged = DEFAULTS.merge(options)
      @on_lock_conflict = merged[:on_lock_conflict]
      @concurrency = normalize_concurrency(merged[:concurrency], lock_scope: merged[:lock_scope])
      @dedupe_ttl = merged[:dedupe_ttl]
      @streaming_update_interval = merged[:streaming_update_interval]
      @handler_executor = merged[:handler_executor]
      history = merged[:history] || {}
      user_history = history[:user] || history["user"] || {}
      @history_user = {
        identity: user_history[:identity] || user_history["identity"] || merged[:identity],
        retention: user_history.fetch(:retention, user_history.fetch("retention", 30 * 24 * 3600)),
        max_per_user: user_history.fetch(:max_per_user, user_history.fetch("max_per_user", 200))
      }
      @log_level = merged[:log_level]

      validate_lock_conflict!
    end

    private

    def validate_lock_conflict!
      return if %i[drop force].include?(@on_lock_conflict) || @on_lock_conflict.respond_to?(:call)
      raise ConfigurationError, "on_lock_conflict must be :drop, :force, or a callable"
    end

    def normalize_concurrency(value, lock_scope:)
      supplied = if value.nil?
        {}
      elsif value.is_a?(Hash)
        value
      else
        {strategy: value}
      end
      supplied = supplied.transform_keys(&:to_sym)
      supplied[:debounce] = supplied.delete(:debounce_ms).to_f / 1000 if supplied.key?(:debounce_ms)
      supplied[:queue_entry_ttl] = supplied.delete(:queue_entry_ttl_ms).to_f / 1000 if supplied.key?(:queue_entry_ttl_ms)
      supplied[:max_lock_lifetime] = supplied.delete(:max_lock_lifetime_ms).to_f / 1000 if supplied.key?(:max_lock_lifetime_ms)
      supplied[:lock_ttl] = supplied.delete(:lock_ttl_ms).to_f / 1000 if supplied.key?(:lock_ttl_ms)
      config = {
        strategy: :drop,
        max_queue_size: 10,
        on_queue_full: :drop_oldest,
        queue_entry_ttl: 90,
        debounce: 1.5,
        lock_ttl: 30,
        max_lock_lifetime: 600,
        max_concurrent: nil,
        lock_scope: lock_scope
      }.merge(supplied)
      config[:strategy] = config[:strategy].to_sym
      config[:on_queue_full] = config[:on_queue_full].to_s.tr("-", "_").to_sym
      unless %i[drop force queue burst debounce concurrent].include?(config[:strategy])
        raise ConfigurationError, "concurrency strategy must be :drop, :queue, :burst, :debounce, or :concurrent"
      end
      if config[:max_concurrent] && config[:max_concurrent].to_i < 1
        raise ConfigurationError, "max_concurrent must be at least 1"
      end
      config
    end
  end
end
