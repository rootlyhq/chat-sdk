# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::State::Mysql do
  describe ".parse_url" do
    it "decodes URL credentials and database names" do
      options = described_class.parse_url(
        "mysql2://test%40user:p%40ss%3Aword%2B@db.example.test:3310/chat%20sdk"
      )

      expect(options).to eq(
        host: "db.example.test",
        port: 3310,
        username: "test@user",
        password: "p@ss:word+",
        database: "chat sdk"
      )
    end

    it "omits the port when none is provided" do
      options = described_class.parse_url("mysql2://test@db.example.test/chat_sdk")

      expect(options).not_to have_key(:port)
    end

    it "omits the password when none is provided" do
      options = described_class.parse_url("mysql2://test@db.example.test/chat_sdk")

      expect(options).not_to have_key(:password)
    end

    it "includes supported query options" do
      options = described_class.parse_url(
        "mysql2://test@db.example.test/chat_sdk?ssl_mode=VERIFY_IDENTITY&encoding=utf8mb4"
      )

      expect(options).to include(ssl_mode: "VERIFY_IDENTITY", encoding: "utf8mb4")
    end
  end
end
