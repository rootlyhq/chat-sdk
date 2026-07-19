# frozen_string_literal: true

require_relative "../../spec_helper"

def mysql_url
  ENV["MYSQL_URL"] || "mysql2://root@localhost/chat_sdk_dev"
end

def mysql_available?
  conn = Mysql2::Client.new(mysql_url)
  conn.query("SELECT 1")
  conn.close
  true
rescue Mysql2::Error
  false
end

RSpec.describe ChatSDK::State::Mysql, if: mysql_available? do
  subject { described_class.new(url: mysql_url) }

  before { subject.clear }

  it_behaves_like "a chat_sdk state adapter"

  describe "TTL expiration" do
    it "expires cached keys" do
      subject.set("k1", "v1", ttl: 0.1)
      sleep 0.15
      expect(subject.get("k1")).to be_nil
    end

    it "expires locks" do
      subject.acquire_lock("l1", owner: "a", ttl: 0.1)
      sleep 0.15
      expect(subject.acquire_lock("l1", owner: "b", ttl: 10)).to be true
    end
  end

  describe "#cleanup_expired" do
    it "removes expired cache entries" do
      subject.set("k1", "v1", ttl: 0.1)
      sleep 0.15
      subject.cleanup_expired
      result = subject.conn.prepare(
        "SELECT 1 FROM chat_sdk_cache WHERE cache_key = ?"
      ).execute("k1")
      expect(result.count).to eq(0)
    end

    it "removes expired locks" do
      subject.acquire_lock("l1", owner: "a", ttl: 0.1)
      sleep 0.15
      subject.cleanup_expired
      result = subject.conn.prepare(
        "SELECT 1 FROM chat_sdk_locks WHERE lock_key = ?"
      ).execute("l1")
      expect(result.count).to eq(0)
    end
  end

  describe "auto_migrate" do
    it "creates tables automatically" do
      conn = Mysql2::Client.new(mysql_url)
      described_class.new(connection: conn, auto_migrate: true)
      result = conn.query("SHOW TABLES LIKE 'chat_sdk_%'")
      table_names = result.map { |row| row.values.first }
      expect(table_names).to include("chat_sdk_subscriptions", "chat_sdk_locks", "chat_sdk_cache")
      conn.close
    end
  end

  describe "key_prefix isolation" do
    it "isolates state between different prefixes" do
      adapter_a = described_class.new(url: mysql_url, key_prefix: "app_a")
      adapter_b = described_class.new(url: mysql_url, key_prefix: "app_b")

      adapter_a.clear
      adapter_b.clear

      adapter_a.subscribe("t1")
      adapter_a.set("k1", "from_a")

      expect(adapter_a.subscribed?("t1")).to be true
      expect(adapter_b.subscribed?("t1")).to be false
      expect(adapter_a.get("k1")).to eq("from_a")
      expect(adapter_b.get("k1")).to be_nil

      adapter_a.clear
      adapter_b.clear
    end
  end

  describe "#clear" do
    it "removes all state for the prefix" do
      subject.subscribe("t1")
      subject.set("k1", "v1")
      subject.acquire_lock("l1", owner: "a", ttl: 10)
      subject.clear
      expect(subject.subscribed?("t1")).to be false
      expect(subject.get("k1")).to be_nil
      expect(subject.acquire_lock("l1", owner: "b", ttl: 10)).to be true
    end
  end
end
