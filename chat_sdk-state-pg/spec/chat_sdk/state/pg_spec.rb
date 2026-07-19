# frozen_string_literal: true

require_relative "../../spec_helper"

def pg_url
  ENV["DATABASE_URL"] || ENV["POSTGRES_URL"] || "postgresql://localhost/chat_sdk_dev"
end

def pg_available?
  conn = PG.connect(pg_url)
  conn.exec("SELECT 1")
  conn.close
  true
rescue PG::Error
  false
end

RSpec.describe ChatSDK::State::Pg, if: pg_available? do
  subject { described_class.new(url: pg_url) }

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
      result = subject.conn.exec_params(
        "SELECT 1 FROM chat_sdk_cache WHERE cache_key = $1",
        ["k1"]
      )
      expect(result.ntuples).to eq(0)
    end

    it "removes expired locks" do
      subject.acquire_lock("l1", owner: "a", ttl: 0.1)
      sleep 0.15
      subject.cleanup_expired
      result = subject.conn.exec_params(
        "SELECT 1 FROM chat_sdk_locks WHERE lock_key = $1",
        ["l1"]
      )
      expect(result.ntuples).to eq(0)
    end
  end

  describe "auto_migrate" do
    it "creates tables automatically" do
      conn = PG.connect(pg_url)
      described_class.new(connection: conn, auto_migrate: true)
      result = conn.exec("SELECT tablename FROM pg_tables WHERE tablename LIKE 'chat_sdk_%' ORDER BY tablename")
      table_names = result.map { |row| row["tablename"] }
      expect(table_names).to include("chat_sdk_subscriptions", "chat_sdk_locks", "chat_sdk_cache")
      conn.close
    end
  end

  describe "key_prefix isolation" do
    it "isolates state between different prefixes" do
      adapter_a = described_class.new(url: pg_url, key_prefix: "app_a")
      adapter_b = described_class.new(url: pg_url, key_prefix: "app_b")

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
