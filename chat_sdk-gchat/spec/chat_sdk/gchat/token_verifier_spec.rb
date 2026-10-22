# frozen_string_literal: true

require_relative "../../spec_helper"
require "base64"
require "json"
require "jwt"
require "openssl"
require "rack"

RSpec.describe ChatSDK::GChat::TokenVerifier do
  let(:chat_issuer) { "chat@system.gserviceaccount.com" }
  let(:chat_issuer_certs_url) { "https://www.googleapis.com/service_accounts/v1/metadata/x509/chat@system.gserviceaccount.com" }
  let(:oidc_certs_url) { "https://www.googleapis.com/oauth2/v3/certs" }
  let(:project_number) { "123456789" }
  let(:endpoint_url) { "https://example.com/webhooks/gchat" }
  let(:pubsub_audience) { "https://example.com/pubsub/gchat" }
  let(:pubsub_service_account_email) { "gchat-pubsub@example.iam.gserviceaccount.com" }
  let(:add_on_email) { "service-987654321@gcp-sa-gsuiteaddons.iam.gserviceaccount.com" }
  let(:key_id) { "local-chat-key" }
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{chat_issuer}")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end
  let(:jwk) do
    {
      kty: "RSA",
      kid: key_id,
      alg: "RS256",
      use: "sig",
      n: Base64.urlsafe_encode64(key.public_key.n.to_s(2), padding: false),
      e: Base64.urlsafe_encode64(key.public_key.e.to_s(2), padding: false)
    }
  end
  let(:credentials) { instance_double(Google::Auth::ServiceAccountCredentials) }
  let(:client) { instance_double(Google::Apps::Chat::V1::ChatService::Client) }

  around do |example|
    Google::Auth::IDTokens.forget_sources!
    WebMock.disable_net_connect!
    example.run
  ensure
    Google::Auth::IDTokens.forget_sources!
    WebMock.allow_net_connect!
  end

  before do
    stub_google_chat_environment(
      "GOOGLE_CHAT_PROJECT_NUMBER" => nil,
      "GOOGLE_CHAT_PUBSUB_AUDIENCE" => nil,
      "GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL" => nil,
      "GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL" => nil,
      "GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION" => "false"
    )
    stub_request(:get, oidc_certs_url).to_return(body: JSON.generate(keys: [jwk]))
    stub_request(:get, chat_issuer_certs_url).to_return(body: JSON.generate(key_id => certificate.to_pem))
    allow(Google::Auth).to receive(:get_application_default).and_return(credentials)
    allow(Google::Apps::Chat::V1::ChatService::Client).to receive(:new).and_return(client)
  end

  describe "#verify!" do
    it "verifies a project-number token against the Chat issuer certificate" do
      payload = described_class.new(project_number).verify!(project_token)

      expect(payload["iss"]).to eq(chat_issuer)
    end

    it "rejects project-number tokens with a different audience" do
      expect { described_class.new(project_number).verify!(project_token(audience: "another-project")) }
        .to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
    end

    it "rejects project-number tokens with a different issuer" do
      expect { described_class.new(project_number).verify!(project_token(issuer: "attacker@example.com")) }
        .to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
    end
  end

  describe "#verify_request!" do
    it "accepts an endpoint-URL token from the Google Chat service account" do
      adapter = new_adapter(endpoint_url: endpoint_url)

      expect(verify_request(adapter, token: oidc_token(audience: endpoint_url))).to be(true)
    end

    it "rejects endpoint tokens from other emails and unverified email identities" do
      adapter = new_adapter(endpoint_url: endpoint_url)

      expect do
        verify_request(adapter, token: oidc_token(audience: endpoint_url, email: "attacker@example.com"))
      end.to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
      expect do
        verify_request(adapter, token: oidc_token(audience: endpoint_url, email_verified: false))
      end.to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
    end

    it "accepts a Workspace Add-on identity only when it exactly matches configuration" do
      token = oidc_token(audience: endpoint_url, email: add_on_email)

      expect do
        verify_request(new_adapter(endpoint_url: endpoint_url), token: token)
      end.to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
      expect do
        verify_request(
          new_adapter(
            endpoint_url: endpoint_url,
            workspace_add_on_service_account_email: "service-123@gcp-sa-gsuiteaddons.iam.gserviceaccount.com"
          ),
          token: token
        )
      end.to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
      expect(
        verify_request(
          new_adapter(endpoint_url: endpoint_url, workspace_add_on_service_account_email: add_on_email),
          token: token
        )
      ).to be(true)
    end

    it "verifies Pub/Sub pushes against the configured audience and service account" do
      adapter = new_adapter(
        pubsub_audience: pubsub_audience,
        pubsub_service_account_email: pubsub_service_account_email
      )

      expect(
        verify_request(
          adapter,
          token: oidc_token(audience: pubsub_audience, email: pubsub_service_account_email),
          body: pubsub_body
        )
      ).to be(true)
    end

    it "rejects Pub/Sub pushes without a configured or matching service account" do
      token = oidc_token(audience: pubsub_audience, email: pubsub_service_account_email)

      expect do
        verify_request(new_adapter(pubsub_audience: pubsub_audience), token: token, body: pubsub_body)
      end.to raise_error(ChatSDK::SignatureVerificationError, /service account/)
      expect do
        verify_request(
          new_adapter(
            pubsub_audience: pubsub_audience,
            pubsub_service_account_email: "other@example.iam.gserviceaccount.com"
          ),
          token: token,
          body: pubsub_body
        )
      end.to raise_error(ChatSDK::SignatureVerificationError, /service account/)
    end

    it "rejects Pub/Sub tokens whose email is not verified" do
      adapter = new_adapter(
        pubsub_audience: pubsub_audience,
        pubsub_service_account_email: pubsub_service_account_email
      )

      expect do
        verify_request(
          adapter,
          token: oidc_token(
            audience: pubsub_audience,
            email: pubsub_service_account_email,
            email_verified: false
          ),
          body: pubsub_body
        )
      end.to raise_error(ChatSDK::SignatureVerificationError, /service account/)
    end

    it "rejects Pub/Sub pushes without an audience unless verification is disabled" do
      expect do
        verify_request(new_adapter(project_number: project_number), body: pubsub_body)
      end.to raise_error(ChatSDK::SignatureVerificationError, /Pub\/Sub verification is not configured/)

      disabled_adapter = new_adapter(disable_signature_verification: true)
      expect(ChatSDK::Log).to receive(:warn).once
      2.times { expect(verify_request(disabled_adapter, body: pubsub_body)).to be(true) }
    end

    it "does not decode an envelope missing subscription as a Pub/Sub push" do
      adapter = new_adapter(endpoint_url: endpoint_url)
      envelope = {
        "message" => {"data" => Base64.strict_encode64(direct_event_body)}
      }
      request = request_for(
        body: JSON.generate(envelope),
        token: oidc_token(audience: endpoint_url)
      )

      expect(adapter.verify_request!(request)).to be(true)
      expect(adapter.parse_events(request)).to be_empty
    end

    it "accepts unverified direct webhooks only when verification is disabled and warns once" do
      adapter = new_adapter(disable_signature_verification: true)

      expect(ChatSDK::Log).to receive(:warn).once
      2.times { expect(verify_request(adapter)).to be(true) }
    end

    it "rejects direct webhooks when only a Pub/Sub audience is configured" do
      adapter = new_adapter(pubsub_audience: pubsub_audience)

      expect { verify_request(adapter) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Direct Google Chat webhook verification/)
    end

    it "accepts either direct token mode when both verifiers are configured" do
      adapter = new_adapter(project_number: project_number, endpoint_url: endpoint_url)

      expect(verify_request(adapter, token: oidc_token(audience: endpoint_url))).to be(true)
      expect(verify_request(adapter, token: project_token)).to be(true)
    end

    it "keeps the request body available for event parsing after verification" do
      adapter = new_adapter(endpoint_url: endpoint_url)
      body = direct_event_body
      request = request_for(body: body, token: oidc_token(audience: endpoint_url))

      expect(adapter.verify_request!(request)).to be(true)
      expect(adapter.parse_events(request).length).to eq(1)
    end

    it "uses the documented environment variables as configuration fallbacks" do
      stub_google_chat_environment(
        "GOOGLE_CHAT_PROJECT_NUMBER" => project_number,
        "GOOGLE_CHAT_PUBSUB_AUDIENCE" => pubsub_audience,
        "GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL" => pubsub_service_account_email,
        "GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL" => add_on_email,
        "GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION" => "false"
      )
      adapter = new_adapter(endpoint_url: endpoint_url)

      expect(verify_request(adapter, token: oidc_token(audience: endpoint_url, email: add_on_email))).to be(true)
      expect(verify_request(adapter, token: project_token)).to be(true)
      expect(
        verify_request(
          adapter,
          token: oidc_token(audience: pubsub_audience, email: pubsub_service_account_email),
          body: pubsub_body
        )
      ).to be(true)
    end

    it "requires an explicit verifier configuration" do
      stub_google_chat_environment(
        "GOOGLE_CHAT_PROJECT_NUMBER" => nil,
        "GOOGLE_CHAT_PUBSUB_AUDIENCE" => nil,
        "GOOGLE_CHAT_PUBSUB_SERVICE_ACCOUNT_EMAIL" => nil,
        "GOOGLE_CHAT_WORKSPACE_ADDON_SERVICE_ACCOUNT_EMAIL" => nil,
        "GOOGLE_CHAT_DISABLE_SIGNATURE_VERIFICATION" => "false"
      )

      expect { new_adapter }.to raise_error(ChatSDK::ConfigurationError, /webhook verification requires/)
    end
  end

  describe "standard webhook endpoint" do
    it "verifies and dispatches Pub/Sub events decoded from the envelope" do
      adapter = new_adapter(
        pubsub_audience: pubsub_audience,
        pubsub_service_account_email: pubsub_service_account_email
      )
      chat = ChatSDK::Chat.new(
        user_name: "gchat-test",
        adapters: {gchat: adapter},
        state: ChatSDK::State::Memory.new
      )
      dispatched_message = nil
      chat.on_new_mention { |_thread, message| dispatched_message = message }
      endpoint = ChatSDK::Webhook::Endpoint.new(chat: chat, adapter: adapter, adapter_name: :gchat)
      request = request_for(
        body: pubsub_body(event: JSON.parse(direct_event_body)),
        token: oidc_token(audience: pubsub_audience, email: pubsub_service_account_email)
      )

      status, = endpoint.call(request.env)

      expect(status).to eq(200)
      expect(dispatched_message.id).to eq("MSG1")
    end
  end

  def project_token(audience: project_number, issuer: chat_issuer)
    signed_token("iss" => issuer, "aud" => audience)
  end

  def oidc_token(audience:, email: chat_issuer, email_verified: true)
    signed_token(
      "iss" => "https://accounts.google.com",
      "aud" => audience,
      "email" => email,
      "email_verified" => email_verified
    )
  end

  def signed_token(claims)
    now = Time.now.to_i
    JWT.encode({"iat" => now, "exp" => now + 300}.merge(claims), key, "RS256", {"kid" => key_id})
  end

  def new_adapter(**options)
    ChatSDK::GChat::Adapter.new(**options)
  end

  def verify_request(adapter, token: nil, body: "{}")
    adapter.verify_request!(request_for(body: body, token: token))
  end

  def request_for(body:, token: nil)
    env = Rack::MockRequest.env_for(
      "/webhooks/gchat",
      :method => "POST",
      :input => body,
      "CONTENT_TYPE" => "application/json"
    )
    env["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    Rack::Request.new(env)
  end

  def pubsub_body(event: {})
    JSON.generate(
      "message" => {"data" => Base64.strict_encode64(JSON.generate(event))},
      "subscription" => "projects/example/subscriptions/gchat"
    )
  end

  def direct_event_body
    JSON.generate(
      "type" => "MESSAGE",
      "message" => {
        "name" => "spaces/SPACE1/messages/MSG1",
        "sender" => {"name" => "users/123", "displayName" => "Alice"},
        "text" => "@Bot hello",
        "argumentText" => "hello",
        "thread" => {"name" => "spaces/SPACE1/threads/THREAD1"},
        "space" => {"name" => "spaces/SPACE1"},
        "annotations" => [
          {
            "type" => "USER_MENTION",
            "userMention" => {"type" => "MENTION", "user" => {"name" => "users/bot"}}
          }
        ]
      }
    )
  end

  def stub_google_chat_environment(values)
    allow(ENV).to receive(:[]).and_call_original
    values.each do |name, value|
      allow(ENV).to receive(:[]).with(name).and_return(value)
    end
  end
end
