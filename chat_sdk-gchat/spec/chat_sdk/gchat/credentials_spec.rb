# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ChatSDK::GChat::Adapter do
  let(:default_credentials) { Object.new }
  let(:default_client) { instance_double(Google::Apps::Chat::V1::ChatService::Client) }
  let(:client_class) { Google::Apps::Chat::V1::ChatService::Client }

  before do
    allow(client_class).to receive(:new).and_return(default_client)
    allow(default_client).to receive(:delete_message)
  end

  def build_adapter(credentials_resolver: nil, credentials: default_credentials)
    described_class.new(
      project_number: "123456789",
      credentials: credentials,
      credentials_resolver: credentials_resolver
    )
  end

  def stub_clients(*clients)
    allow(client_class).to receive(:new).and_return(*clients)
  end

  describe "credentials_resolver" do
    it "uses the resolved credentials for the outbound channel" do
      credentials = Object.new
      resolver = double("credentials resolver")
      resolved_client = instance_double(client_class)
      allow(resolved_client).to receive(:delete_message)
      allow(resolver).to receive(:call).with("SPACE1").and_return(credentials)
      stub_clients(default_client, resolved_client)
      adapter = build_adapter(credentials_resolver: resolver)

      expect(resolved_client).to receive(:delete_message)
        .with(name: "spaces/SPACE1/messages/MSG1")
      adapter.delete_message(channel_id: "SPACE1", message_id: "MSG1")
      expect(resolver).to have_received(:call).with("SPACE1")
    end

    it "uses the default client when the resolver returns nil" do
      resolver = ->(channel_id) do
        expect(channel_id).to eq("SPACE1")
        nil
      end
      adapter = build_adapter(credentials_resolver: resolver)

      expect(default_client).to receive(:delete_message)
        .with(name: "spaces/SPACE1/messages/MSG1")
      adapter.delete_message(channel_id: "SPACE1", message_id: "MSG1")
    end
  end

  describe "#with_credentials" do
    it "overrides the resolver and restores it after the block" do
      scoped_credentials = Object.new
      resolver_credentials = Object.new
      scoped_client = instance_double(client_class)
      resolver_client = instance_double(client_class)
      allow(scoped_client).to receive(:delete_message)
      allow(resolver_client).to receive(:delete_message)
      resolved_channels = []
      resolver = ->(channel_id) do
        resolved_channels << channel_id
        resolver_credentials
      end
      stub_clients(default_client, scoped_client, resolver_client)
      adapter = build_adapter(credentials_resolver: resolver)

      expect(scoped_client).to receive(:delete_message)
      adapter.with_credentials(scoped_credentials) do
        adapter.delete_message(channel_id: "SCOPED", message_id: "MSG1")
        expect(resolved_channels).to be_empty
      end

      expect(resolver_client).to receive(:delete_message)
      adapter.delete_message(channel_id: "RESOLVED", message_id: "MSG2")
      expect(resolved_channels).to eq(["RESOLVED"])
    end

    it "uses scoped credentials when opening a direct message" do
      scoped_client = double("Google Chat client")
      space = double("space", name: "spaces/DM1")
      allow(scoped_client).to receive(:setup_space).and_return(space)
      stub_clients(default_client, scoped_client)
      adapter = build_adapter

      expect(adapter.with_credentials(Object.new) { adapter.open_dm("user-1") }).to eq("DM1")
      expect(scoped_client).to have_received(:setup_space)
    end

    it "restores the previous credentials when the block raises" do
      scoped_client = instance_double(client_class)
      stub_clients(default_client, scoped_client)
      adapter = build_adapter

      expect {
        adapter.with_credentials(Object.new) do
          expect(adapter.client).to equal(scoped_client)
          raise "failure"
        end
      }.to raise_error("failure")

      expect(adapter.client).to equal(default_client)
    end

    it "restores the outer scope after a nested scope" do
      outer_client = instance_double(client_class)
      inner_client = instance_double(client_class)
      stub_clients(default_client, outer_client, inner_client)
      adapter = build_adapter

      adapter.with_credentials(Object.new) do
        expect(adapter.client).to equal(outer_client)
        adapter.with_credentials(Object.new) do
          expect(adapter.client).to equal(inner_client)
        end
        expect(adapter.client).to equal(outer_client)
      end

      expect(adapter.client).to equal(default_client)
    end

    it "does not carry its thread-local scope to another thread" do
      scoped_client = instance_double(client_class)
      stub_clients(default_client, scoped_client)
      adapter = build_adapter

      adapter.with_credentials(Object.new) do
        expect(adapter.client).to equal(scoped_client)
        expect(::Thread.new { adapter.client }.value).to equal(default_client)
      end
    end
  end

  describe "#client" do
    it "returns the default client outside a scope and the scoped client inside" do
      resolver = double("credentials resolver")
      scoped_client = instance_double(client_class)
      stub_clients(default_client, scoped_client)
      adapter = build_adapter(credentials_resolver: resolver)
      expect(resolver).not_to receive(:call)

      expect(adapter.client).to equal(default_client)
      adapter.with_credentials(Object.new) do
        expect(adapter.client).to equal(scoped_client)
      end
      expect(adapter.client).to equal(default_client)
    end
  end

  describe "credential client cache" do
    it "reuses clients for matching hashes" do
      credentials = {
        "client_email" => "tenant@example.com",
        "private_key_id" => "key-1",
        "private_key" => "not-used-by-this-spec"
      }
      matching_credentials = credentials.dup
      resolved_credentials = Object.new
      resolved_client = instance_double(client_class)
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds)
        .and_return(resolved_credentials)
      stub_clients(default_client, resolved_client)
      adapter = build_adapter

      first_client = adapter.with_credentials(credentials) { adapter.client }
      second_client = adapter.with_credentials(matching_credentials) { adapter.client }

      expect(second_client).to equal(first_client)
      expect(Google::Auth::ServiceAccountCredentials).to have_received(:make_creds).once
      expect(client_class).to have_received(:new).twice
    end

    it "does not reuse clients for hashes missing a private_key_id" do
      first_credentials = {
        "client_email" => "tenant@example.com",
        "private_key" => "first-key"
      }
      second_credentials = first_credentials.merge("private_key" => "second-key")
      first_resolved_credentials = Object.new
      second_resolved_credentials = Object.new
      first_client = instance_double(client_class)
      second_client = instance_double(client_class)
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds)
        .and_return(first_resolved_credentials, second_resolved_credentials)
      stub_clients(default_client, first_client, second_client)
      adapter = build_adapter

      first = adapter.with_credentials(first_credentials) { adapter.client }
      second = adapter.with_credentials(second_credentials) { adapter.client }

      expect(second).not_to equal(first)
      expect(Google::Auth::ServiceAccountCredentials).to have_received(:make_creds).twice
      expect(client_class).to have_received(:new).exactly(3).times
    end

    it "reuses clients for a path without reading the file for the cache key" do
      path = "service-account.json"
      file_open_count = 0
      resolved_credentials = Object.new
      resolved_client = instance_double(client_class)
      allow(File).to receive(:open).with(path) do
        file_open_count += 1
        double("credential file")
      end
      expect(File).not_to receive(:read)
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds)
        .and_return(resolved_credentials)
      stub_clients(default_client, resolved_client)
      adapter = build_adapter

      first = adapter.with_credentials(path) { adapter.client }
      second = adapter.with_credentials(path) { adapter.client }

      expect(second).to equal(first)
      expect(file_open_count).to eq(1)
      expect(Google::Auth::ServiceAccountCredentials).to have_received(:make_creds).once
      expect(client_class).to have_received(:new).twice
    end

    it "evicts the least recently used client after reaching the cache limit" do
      credentials = Array.new(101) { Object.new }
      clients = Array.new(103) { Object.new }
      stub_clients(*clients)
      adapter = build_adapter

      cached_clients = credentials.first(100).map do |credential|
        adapter.with_credentials(credential) { adapter.client }
      end
      adapter.with_credentials(credentials.first) { adapter.client }
      adapter.with_credentials(credentials.last) { adapter.client }

      expect(adapter.with_credentials(credentials.first) { adapter.client })
        .to equal(cached_clients.first)
      expect(adapter.with_credentials(credentials[1]) { adapter.client })
        .not_to equal(cached_clients[1])
    end
  end
end
