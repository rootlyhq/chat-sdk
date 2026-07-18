module ChatSDK
  class Author
    attr_reader :id, :name, :platform, :raw

    def initialize(id:, name:, platform:, bot: false, raw: nil)
      @id = id
      @name = name
      @platform = platform
      @bot = bot
      @raw = raw
    end

    def bot?
      @bot
    end

    def ==(other)
      other.is_a?(Author) && id == other.id && platform == other.platform
    end
    alias eql? ==

    def hash
      [id, platform].hash
    end
  end
end
