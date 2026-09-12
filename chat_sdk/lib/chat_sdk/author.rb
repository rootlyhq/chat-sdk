# frozen_string_literal: true

module ChatSDK
  class Author
    attr_reader :id, :name, :platform, :locale, :email, :raw

    def initialize(id:, name:, platform:, bot: false, system: false, locale: nil, email: nil, raw: nil)
      @id = id
      @name = name
      @platform = platform
      @bot = bot
      @system = system
      @locale = locale
      @email = email
      @raw = raw
    end

    def bot?
      @bot
    end

    def system?
      @system
    end

    def ==(other)
      other.is_a?(Author) && id == other.id && platform == other.platform
    end
    alias_method :eql?, :==

    def hash
      [id, platform].hash
    end
  end
end
