# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"
require "ed25519"

RSpec.describe ChatSDK::Discord::Adapter do
  subject do
    described_class.new(
      bot_token: bot_token,
      public_key: public_key_hex,
      application_id: application_id
    )
  end

  let(:bot_token) { "test-discord-bot-token" }
  let(:signing_key) { Ed25519::SigningKey.generate }
  let(:verify_key) { signing_key.verify_key }
  let(:public_key_hex) { verify_key.to_bytes.unpack1("H*") }
  let(:application_id) { "app-id-123" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without bot_token" do
      expect { described_class.new(bot_token: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /bot_token required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("DISCORD_PUBLIC_KEY").and_return(public_key_hex)
      allow(ENV).to receive(:[]).with("DISCORD_APPLICATION_ID").and_return("env-app-id")

      adapter = described_class.new
      expect(adapter.name).to eq(:discord)
    end
  end

  describe "#name" do
    it "returns :discord" do
      expect(subject.name).to eq(:discord)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Discord::ApiClient)
    end
  end

  describe "#mention" do
    it "formats a Discord mention" do
      expect(subject.mention("123456")).to eq("<@123456>")
    end
  end

  describe "#verify_request!" do
    def build_signed_request(body)
      timestamp = Time.now.to_i.to_s
      message = "#{timestamp}#{body}"
      signature = signing_key.sign(message)
      signature_hex = signature.unpack1("H*")

      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SIGNATURE_ED25519" => signature_hex,
        "HTTP_X_SIGNATURE_TIMESTAMP" => timestamp
      )
      Rack::Request.new(env)
    end

    def build_request(body, signature: "bad", timestamp: "12345")
      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SIGNATURE_ED25519" => signature,
        "HTTP_X_SIGNATURE_TIMESTAMP" => timestamp
      )
      Rack::Request.new(env)
    end

    it "accepts a valid Ed25519 signature" do
      body = '{"type":1}'
      request = build_signed_request(body)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"type":1}'
      request = build_request(body, signature: "ab" * 64, timestamp: "12345")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Discord signature/)
    end

    it "rejects missing signature headers" do
      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => '{"type":1}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Discord signature/)
    end

    it "raises ConfigurationError when public_key is not configured" do
      adapter = described_class.new(bot_token: bot_token, public_key: nil)
      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => '{"type":1}',
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SIGNATURE_ED25519" => "ab" * 64,
        "HTTP_X_SIGNATURE_TIMESTAMP" => "12345"
      )
      request = Rack::Request.new(env)
      expect { adapter.verify_request!(request) }
        .to raise_error(ChatSDK::ConfigurationError, /public_key required/)
    end
  end

  describe "#ack_response" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    it "returns PONG for PING interactions" do
      request = build_request('{"type":1}')
      result = subject.ack_response(request)

      expect(result).to eq([200, {"content-type" => "application/json"}, ['{"type":1}']])
    end

    it "returns nil for non-PING interactions" do
      request = build_request('{"type":2,"data":{"name":"test"}}')
      result = subject.ack_response(request)

      expect(result).to be_nil
    end

    it "returns nil for invalid JSON" do
      request = build_request("not json")
      result = subject.ack_response(request)

      expect(result).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/discord",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "APPLICATION_COMMAND (type 2)" do
      it "parses into SlashCommand event" do
        payload = {
          "type" => 2,
          "id" => "interaction-1",
          "channel_id" => "ch123",
          "member" => {
            "user" => {"id" => "uid123", "username" => "alice"}
          },
          "data" => {
            "name" => "incident",
            "options" => [
              {"name" => "title", "value" => "API down"},
              {"name" => "severity", "value" => "sev1"}
            ]
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SlashCommand)
        expect(event.command).to eq("/incident")
        expect(event.text).to eq("API down sev1")
        expect(event.user_id).to eq("uid123")
        expect(event.channel_id).to eq("ch123")
        expect(event.platform).to eq(:discord)
        expect(event.adapter_name).to eq(:discord)
      end

      it "handles commands without options" do
        payload = {
          "type" => 2,
          "id" => "interaction-2",
          "channel_id" => "ch456",
          "user" => {"id" => "uid456", "username" => "bob"},
          "data" => {"name" => "help"}
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event.command).to eq("/help")
        expect(event.text).to eq("")
        expect(event.user_id).to eq("uid456")
      end
    end

    context "MESSAGE_COMPONENT (type 3)" do
      it "parses button click into Action event" do
        payload = {
          "type" => 3,
          "id" => "interaction-3",
          "channel_id" => "ch123",
          "message" => {"id" => "msg123"},
          "member" => {
            "user" => {"id" => "uid123", "username" => "alice"}
          },
          "data" => {
            "custom_id" => "btn:approve",
            "component_type" => 2
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("btn:approve")
        expect(event.user.id).to eq("uid123")
        expect(event.channel_id).to eq("ch123")
        expect(event.platform).to eq(:discord)
      end

      it "parses select menu into Action event with selected value" do
        payload = {
          "type" => 3,
          "id" => "interaction-4",
          "channel_id" => "ch123",
          "message" => {"id" => "msg456"},
          "member" => {
            "user" => {"id" => "uid123", "username" => "alice"}
          },
          "data" => {
            "custom_id" => "severity_select",
            "component_type" => 3,
            "values" => ["sev1"]
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("severity_select")
        expect(event.value).to eq("sev1")
      end
    end

    context "PING (type 1)" do
      it "returns empty array" do
        request = build_request('{"type":1}')
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "invalid JSON" do
      it "returns empty array" do
        request = build_request("not json")
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end
  end

  describe "#post_message" do
    it "sends a text message" do
      stub_request(:post, "https://discord.com/api/v10/channels/ch123/messages")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-1", "channel_id" => "ch123", "content" => "Hello!"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "ch123", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("msg-1")
      expect(result.platform).to eq(:discord)
    end

    it "sends a card message with embeds" do
      stub_request(:post, "https://discord.com/api/v10/channels/ch123/messages")
        .with { |req|
          body = JSON.parse(req.body)
          body["embeds"].is_a?(Array)
        }
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-card-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card do
        text "Incident Update"
        fields do
          field "Status", "Active"
        end
      end

      result = subject.post_message(
        channel_id: "ch123",
        message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update")
      )
      expect(result.id).to eq("msg-card-1")
    end
  end

  describe "#edit_message" do
    it "updates a message" do
      stub_request(:patch, "https://discord.com/api/v10/channels/ch123/messages/msg-1")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "msg-1", "content" => "Updated"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.edit_message(channel_id: "ch123", message_id: "msg-1", message: "Updated")
      expect(result["id"]).to eq("msg-1")
    end
  end

  describe "#delete_message" do
    it "deletes a message" do
      stub_request(:delete, "https://discord.com/api/v10/channels/ch123/messages/msg-1")
        .to_return(status: 204, body: "", headers: {})

      expect { subject.delete_message(channel_id: "ch123", message_id: "msg-1") }.not_to raise_error
    end
  end

  describe "#add_reaction" do
    it "adds a reaction" do
      stub_request(:put, "https://discord.com/api/v10/channels/ch123/messages/msg-1/reactions/%F0%9F%91%8D/@me")
        .to_return(status: 204, body: "", headers: {})

      expect { subject.add_reaction(channel_id: "ch123", message_id: "msg-1", emoji: "\u{1F44D}") }
        .not_to raise_error
    end
  end

  describe "#remove_reaction" do
    it "removes a reaction" do
      stub_request(:delete, "https://discord.com/api/v10/channels/ch123/messages/msg-1/reactions/%F0%9F%91%8D/@me")
        .to_return(status: 204, body: "", headers: {})

      expect { subject.remove_reaction(channel_id: "ch123", message_id: "msg-1", emoji: "\u{1F44D}") }
        .not_to raise_error
    end
  end

  describe "#get_user" do
    it "returns an Author for a valid user" do
      stub_request(:get, "https://discord.com/api/v10/users/user-123")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "user-123", "username" => "alice", "bot" => false}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.get_user("user-123")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.id).to eq("user-123")
      expect(result.name).to eq("alice")
      expect(result.platform).to eq(:discord)
      expect(result.bot?).to be false
    end

    it "returns an Author with bot: true for bot users" do
      stub_request(:get, "https://discord.com/api/v10/users/bot-456")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "bot-456", "username" => "helperbot", "bot" => true}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.get_user("bot-456")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.bot?).to be true
    end
  end

  describe "#open_dm" do
    it "creates a DM channel and returns channel_id" do
      stub_request(:post, "https://discord.com/api/v10/users/@me/channels")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "dm-channel-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.open_dm("user-456")
      expect(result).to eq("dm-channel-1")
    end
  end

  describe "#fetch_messages" do
    it "fetches channel messages" do
      stub_request(:get, "https://discord.com/api/v10/channels/ch123/messages?limit=50")
        .to_return(
          status: 200,
          body: JSON.generate([
            {"id" => "msg-2", "content" => "Second", "author" => {"id" => "u2", "username" => "bob"}},
            {"id" => "msg-1", "content" => "First", "author" => {"id" => "u1", "username" => "alice"}}
          ]),
          headers: {"Content-Type" => "application/json"}
        )

      messages, cursor = subject.fetch_messages(channel_id: "ch123")
      expect(messages.size).to eq(2)
      expect(messages.first.text).to eq("Second")
      expect(cursor).to eq("msg-1")
    end
  end

  describe "#start_typing" do
    it "triggers a typing indicator" do
      stub_request(:post, "https://discord.com/api/v10/channels/ch123/typing")
        .to_return(status: 204, body: "", headers: {})

      expect { subject.start_typing(channel_id: "ch123") }.not_to raise_error
    end

    it "supports typing_indicator capability" do
      expect(subject.supports?(:typing_indicator)).to be true
    end
  end

  describe "#fetch_thread" do
    it "returns channel info" do
      stub_request(:get, "https://discord.com/api/v10/channels/ch123")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "ch123", "name" => "general", "type" => 0}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.fetch_thread(channel_id: "ch123")
      expect(result).to be_a(Hash)
      expect(result["id"]).to eq("ch123")
      expect(result["name"]).to eq("general")
      expect(result["type"]).to eq(0)
    end

    it "accepts an optional thread_id parameter" do
      stub_request(:get, "https://discord.com/api/v10/channels/thread-456")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "thread-456", "name" => "incident-thread", "type" => 11}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.fetch_thread(channel_id: "thread-456", thread_id: "ignored")
      expect(result["id"]).to eq("thread-456")
      expect(result["type"]).to eq(11)
    end
  end

  describe "#set_thread_title" do
    it "renames a channel or thread" do
      stub_request(:patch, "https://discord.com/api/v10/channels/ch123")
        .with(body: {"name" => "new-title"})
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "ch123", "name" => "new-title"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.set_thread_title(channel_id: "ch123", title: "new-title")
      expect(result["name"]).to eq("new-title")
    end
  end

  describe "#create_thread" do
    it "starts a thread from a message" do
      stub_request(:post, "https://discord.com/api/v10/channels/ch123/messages/msg-1/threads")
        .with(body: {"name" => "incident-thread"})
        .to_return(
          status: 201,
          body: JSON.generate({"id" => "thread-789", "name" => "incident-thread", "type" => 11}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.create_thread(channel_id: "ch123", message_id: "msg-1", name: "incident-thread")
      expect(result["id"]).to eq("thread-789")
      expect(result["name"]).to eq("incident-thread")
      expect(result["type"]).to eq(11)
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for ephemeral messages" do
      expect { subject.post_ephemeral(channel_id: "C1", user_id: "U1", message: "test") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for modals" do
      expect { subject.open_modal(trigger_id: "T1", modal: ChatSDK::Cards::Node.new(:modal)) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "does not support ephemeral_messages capability" do
      expect(subject.supports?(:ephemeral_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end
  end

  describe "#render" do
    it "renders a card as embeds hash" do
      card = ChatSDK.card do
        text "Hello"
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Hello")

      result = subject.render(msg)
      expect(result).to be_a(Hash)
      expect(result).to have_key("embeds")
      expect(result["embeds"].first["description"]).to eq("Hello")
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe ChatSDK::Discord::EmbedRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node as embed" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result).to be_a(Hash)
        expect(result["embeds"].first["description"]).to eq("Hello world")
      end

      it "renders a card with text and fields" do
        card = ChatSDK.card do
          text "Incident #123"
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        expect(result["embeds"].size).to eq(1)
        embed = result["embeds"].first
        expect(embed["description"]).to include("Incident #123")
        expect(embed["fields"].size).to eq(2)
        expect(embed["fields"][0]).to eq({"name" => "Status", "value" => "Active", "inline" => true})
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)
        expect(result["embeds"].first["image"]).to eq({"url" => "https://example.com/img.png"})
      end

      it "renders actions with buttons as components" do
        card = ChatSDK.card do
          actions do
            button "Approve", id: "btn:approve", style: :primary, value: "yes"
            button "Reject", id: "btn:reject", style: :danger
          end
        end
        result = renderer.render(card)

        expect(result["components"].size).to eq(1)
        action_row = result["components"].first
        expect(action_row["type"]).to eq(1)
        expect(action_row["components"].size).to eq(2)

        approve = action_row["components"][0]
        expect(approve["type"]).to eq(2)
        expect(approve["style"]).to eq(1) # primary
        expect(approve["label"]).to eq("Approve")
        expect(approve["custom_id"]).to eq("btn:approve")

        reject = action_row["components"][1]
        expect(reject["style"]).to eq(4) # danger
      end

      it "renders a select menu" do
        card = ChatSDK.card do
          actions do
            select id: "severity_select", placeholder: "Choose severity" do
              option "SEV1", value: "sev1"
              option "SEV2", value: "sev2"
            end
          end
        end
        result = renderer.render(card)

        action_row = result["components"].first
        sel = action_row["components"][0]
        expect(sel["type"]).to eq(3)
        expect(sel["custom_id"]).to eq("severity_select")
        expect(sel["placeholder"]).to eq("Choose severity")
        expect(sel["options"].size).to eq(2)
        expect(sel["options"][0]).to eq({"label" => "SEV1", "value" => "sev1"})
      end

      it "renders link buttons" do
        card = ChatSDK.card do
          actions do
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        action_row = result["components"].first
        link = action_row["components"][0]
        expect(link["type"]).to eq(2)
        expect(link["style"]).to eq(5) # link style
        expect(link["label"]).to eq("View")
        expect(link["url"]).to eq("https://example.com")
      end

      it "renders a section" do
        card = ChatSDK.card do
          section "Details" do
            text "Some info"
          end
        end
        result = renderer.render(card)

        embed = result["embeds"].first
        expect(embed["description"]).to include("**Details**")
        expect(embed["description"]).to include("Some info")
      end

      it "renders dividers as separators" do
        card = ChatSDK.card do
          text "Before"
          divider
          text "After"
        end
        result = renderer.render(card)

        embed = result["embeds"].first
        expect(embed["description"]).to include("───")
      end

      it "renders card title" do
        card = ChatSDK.card(title: "Incident #4821") do
          text "Details here"
        end
        result = renderer.render(card)

        embed = result["embeds"].first
        expect(embed["title"]).to eq("Incident #4821")
      end
    end
  end

  describe "#start_gateway" do
    it "raises ConfigurationError when discordrb is not installed" do
      # discordrb is not in our test bundle, so LoadError is the real behavior
      expect { subject.start_gateway { |_event| } }
        .to raise_error(ChatSDK::ConfigurationError, /discordrb/)
    end

    it "raises ArgumentError when called without a block" do
      expect { subject.start_gateway }
        .to raise_error(ArgumentError, /requires a block/)
    end
  end
end
