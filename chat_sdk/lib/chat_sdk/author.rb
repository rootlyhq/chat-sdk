# frozen_string_literal: true

module ChatSDK
  class Author
    attr_reader :id, :name, :platform, :locale, :raw

    def initialize(id:, name:, platform:, bot: false, locale: nil, raw: nil)
      @id = id
      @name = name
      @platform = platform
      @bot = bot
      @locale = locale
      @raw = raw
    end

    def bot?
      @bot
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
