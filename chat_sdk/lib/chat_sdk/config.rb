# frozen_string_literal: true

module ChatSDK
  class Config
    DEFAULTS = {
      dedupe_ttl: 600,
      streaming_update_interval: 0.5,
      on_lock_conflict: :drop,
      handler_executor: :inline,
      log_level: :info
    }.freeze

    attr_reader :user_name, :adapters, :state, :on_lock_conflict,
      :dedupe_ttl, :streaming_update_interval, :handler_executor, :log_level

    def initialize(user_name:, adapters:, state:, **options)
      raise ConfigurationError, "user_name is required" if user_name.nil? || user_name.empty?
      raise ConfigurationError, "adapters hash is required" if adapters.nil? || adapters.empty?
      raise ConfigurationError, "state adapter is required" if state.nil?

      @user_name = user_name
      @adapters = adapters
      @state = state
      merged = DEFAULTS.merge(options)
      @on_lock_conflict = merged[:on_lock_conflict]
      @dedupe_ttl = merged[:dedupe_ttl]
      @streaming_update_interval = merged[:streaming_update_interval]
      @handler_executor = merged[:handler_executor]
      @log_level = merged[:log_level]

      validate_lock_conflict!
    end

    private

    def validate_lock_conflict!
      return if %i[drop force].include?(@on_lock_conflict) || @on_lock_conflict.respond_to?(:call)
      raise ConfigurationError, "on_lock_conflict must be :drop, :force, or a callable"
    end
  end
end
