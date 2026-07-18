# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::Mattermost::Adapter do
  subject do
    described_class.new(
      base_url: base_url,
      bot_token: bot_token,
      webhook_token: webhook_token,
      bot_user_id: bot_user_id
    )
  end

  let(:base_url) { "https://mattermost.example.com" }
  let(:bot_token) { "test-bot-token-secret" }
  let(:webhook_token) { "test-webhook-token" }
  let(:bot_user_id) { "bot-user-id-123" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without base_url" do
      expect { described_class.new(base_url: nil, bot_token: bot_token) }
        .to raise_error(ChatSDK::ConfigurationError, /base_url required/)
    end

    it "raises ConfigurationError without bot_token" do
      expect { described_class.new(base_url: base_url, bot_token: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /bot_token required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MATTERMOST_BASE_URL").and_return("https://mm.test.com")
      allow(ENV).to receive(:[]).with("MATTERMOST_BOT_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("MATTERMOST_WEBHOOK_TOKEN").and_return("env-wh-token")
      allow(ENV).to receive(:[]).with("MATTERMOST_BOT_USER_ID").and_return("env-bot-id")

      adapter = described_class.new
      expect(adapter.name).to eq(:mattermost)
    end
  end

  describe "#name" do
    it "returns :mattermost" do
      expect(subject.name).to eq(:mattermost)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Mattermost::ApiClient)
    end
  end

  describe "#mention" do
    it "formats a Mattermost mention" do
      expect(subject.mention("alice")).to eq("@alice")
    end
  end

  describe "#verify_request!" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/mattermost",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    it "accepts a valid webhook token" do
      payload = {"token" => webhook_token, "text" => "hello"}.to_json
      request = build_request(payload)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid webhook token" do
      payload = {"token" => "wrong-token", "text" => "hello"}.to_json
      request = build_request(payload)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid webhook token/)
    end

    it "rejects invalid JSON" do
      request = build_request("not json")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid JSON/)
    end

    it "passes when no webhook_token is configured" do
      adapter = described_class.new(
        base_url: base_url,
        bot_token: bot_token,
        webhook_token: nil,
        bot_user_id: bot_user_id
      )
      payload = {"text" => "hello"}.to_json
      request = build_request(payload)
      expect(adapter.verify_request!(request)).to be(true)
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/mattermost",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "outgoing webhook with trigger word mention" do
      it "parses into Mention event" do
        payload = {
          "token" => webhook_token,
          "channel_id" => "ch123",
          "channel_name" => "town-square",
          "user_id" => "uid123",
          "user_name" => "alice",
          "post_id" => "pid123",
          "text" => "@bot hello",
          "trigger_word" => "@bot",
          "root_id" => ""
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("@bot hello")
        expect(event.message.author.id).to eq("uid123")
        expect(event.message.author.name).to eq("alice")
        expect(event.channel_id).to eq("ch123")
        expect(event.platform).to eq(:mattermost)
        expect(event.adapter_name).to eq(:mattermost)
      end
    end

    context "outgoing webhook with non-mention trigger" do
      it "parses into SubscribedMessage event" do
        payload = {
          "token" => webhook_token,
          "channel_id" => "ch456",
          "user_id" => "uid456",
          "user_name" => "bob",
          "post_id" => "pid456",
          "text" => "incident update",
          "trigger_word" => "incident"
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(events.first.message.text).to eq("incident update")
      end
    end

    context "threaded outgoing webhook" do
      it "preserves thread_id from root_id" do
        payload = {
          "token" => webhook_token,
          "channel_id" => "ch123",
          "user_id" => "uid123",
          "user_name" => "alice",
          "post_id" => "pid789",
          "text" => "@bot reply",
          "trigger_word" => "@bot",
          "root_id" => "pid100"
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.first.thread_id).to eq("pid100")
      end
    end

    context "interactive button action" do
      it "parses into Action event" do
        payload = {
          "type" => "button",
          "context" => {"action" => "btn:approve", "value" => "yes"},
          "user_id" => "uid123",
          "channel_id" => "ch123",
          "post_id" => "pid123"
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("yes")
        expect(event.user.id).to eq("uid123")
        expect(event.channel_id).to eq("ch123")
      end
    end

    context "interactive select action" do
      it "parses into Action event with selected_option" do
        payload = {
          "type" => "select",
          "context" => {"action" => "severity_select"},
          "user_id" => "uid123",
          "channel_id" => "ch123",
          "post_id" => "pid123",
          "selected_option" => "sev1"
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

    context "message from the bot itself" do
      it "ignores messages from bot_user_id" do
        payload = {
          "token" => webhook_token,
          "channel_id" => "ch123",
          "user_id" => bot_user_id,
          "user_name" => "bot",
          "post_id" => "pid999",
          "text" => "my own message",
          "trigger_word" => "@bot"
        }
        request = build_request(JSON.generate(payload))
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
      stub_request(:post, "#{base_url}/api/v4/posts")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "new-post-1", "channel_id" => "ch123", "message" => "Hello!"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "ch123", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("new-post-1")
      expect(result.platform).to eq(:mattermost)
    end

    it "sends a card message with attachments" do
      stub_request(:post, "#{base_url}/api/v4/posts")
        .with { |req|
          body = JSON.parse(req.body)
          body.dig("props", "attachments").is_a?(Array)
        }
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "post-card-1"}),
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
      expect(result.id).to eq("post-card-1")
    end

    it "sends a threaded message" do
      stub_request(:post, "#{base_url}/api/v4/posts")
        .with { |req|
          body = JSON.parse(req.body)
          body["root_id"] == "thread-root-1"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "reply-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "ch123", message: "Reply!", thread_id: "thread-root-1")
      expect(result.id).to eq("reply-1")
      expect(result.thread_id).to eq("thread-root-1")
    end
  end

  describe "#edit_message" do
    it "updates a post" do
      stub_request(:put, "#{base_url}/api/v4/posts/post-1")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "post-1", "message" => "Updated"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.edit_message(channel_id: "ch123", message_id: "post-1", message: "Updated")
      expect(result["id"]).to eq("post-1")
    end
  end

  describe "#delete_message" do
    it "deletes a post" do
      stub_request(:delete, "#{base_url}/api/v4/posts/post-1")
        .to_return(status: 200, body: JSON.generate({"status" => "OK"}), headers: {"Content-Type" => "application/json"})

      expect { subject.delete_message(channel_id: "ch123", message_id: "post-1") }.not_to raise_error
    end
  end

  describe "#post_ephemeral" do
    it "creates an ephemeral post" do
      stub_request(:post, "#{base_url}/api/v4/posts/ephemeral")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "eph-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_ephemeral(channel_id: "ch123", user_id: "uid123", message: "Only you see this") }
        .not_to raise_error
    end
  end

  describe "#add_reaction" do
    it "adds a reaction" do
      stub_request(:post, "#{base_url}/api/v4/reactions")
        .to_return(
          status: 200,
          body: JSON.generate({"user_id" => bot_user_id, "post_id" => "post-1", "emoji_name" => "thumbsup"}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.add_reaction(channel_id: "ch123", message_id: "post-1", emoji: "thumbsup") }
        .not_to raise_error
    end
  end

  describe "#remove_reaction" do
    it "removes a reaction" do
      stub_request(:delete, "#{base_url}/api/v4/reactions/#{bot_user_id}/post-1/thumbsup")
        .to_return(status: 200, body: JSON.generate({"status" => "OK"}), headers: {"Content-Type" => "application/json"})

      expect { subject.remove_reaction(channel_id: "ch123", message_id: "post-1", emoji: "thumbsup") }
        .not_to raise_error
    end
  end

  describe "#open_dm" do
    it "creates a direct channel and returns channel_id" do
      stub_request(:post, "#{base_url}/api/v4/channels/direct")
        .to_return(
          status: 200,
          body: JSON.generate({"id" => "dm-channel-1"}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.open_dm("user-456")
      expect(result).to eq("dm-channel-1")
    end
  end

  describe "#start_typing" do
    it "sends a typing indicator" do
      stub_request(:post, "#{base_url}/api/v4/users/me/typing")
        .to_return(status: 200, body: JSON.generate({}), headers: {"Content-Type" => "application/json"})

      expect { subject.start_typing(channel_id: "ch123") }.not_to raise_error
    end
  end

  describe "#fetch_messages" do
    it "fetches channel posts" do
      stub_request(:get, "#{base_url}/api/v4/channels/ch123/posts?page=0&per_page=50")
        .to_return(
          status: 200,
          body: JSON.generate({
            "order" => ["post-2", "post-1"],
            "posts" => {
              "post-1" => {"id" => "post-1", "message" => "First", "user_id" => "u1", "channel_id" => "ch123", "root_id" => ""},
              "post-2" => {"id" => "post-2", "message" => "Second", "user_id" => "u2", "channel_id" => "ch123", "root_id" => ""}
            }
          }),
          headers: {"Content-Type" => "application/json"}
        )

      messages, cursor = subject.fetch_messages(channel_id: "ch123")
      expect(messages.size).to eq(2)
      expect(messages.first.text).to eq("Second")
      expect(cursor).to eq("1")
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for modals" do
      expect { subject.open_modal(trigger_id: "T1", modal: ChatSDK::Cards::Node.new(:modal)) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support scheduled_messages capability" do
      expect(subject.supports?(:scheduled_messages)).to be false
    end
  end

  describe "#render" do
    it "renders a card as attachment array" do
      card = ChatSDK.card do
        text "Hello"
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Hello")

      result = subject.render(msg)
      expect(result).to be_an(Array)
      expect(result.first).to have_key("text")
      expect(result.first["text"]).to eq("Hello")
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe ChatSDK::Mattermost::AttachmentRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node as attachment" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result).to be_an(Array)
        expect(result.first["text"]).to eq("Hello world")
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

        expect(result.size).to eq(1)
        attachment = result.first
        expect(attachment["text"]).to include("Incident #123")
        expect(attachment["fields"].size).to eq(2)
        expect(attachment["fields"][0]).to eq({"title" => "Status", "value" => "Active", "short" => true})
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)
        expect(result.first["image_url"]).to eq("https://example.com/img.png")
      end

      it "renders actions with buttons" do
        card = ChatSDK.card do
          actions do
            button "Approve", id: "btn:approve", style: :primary, value: "yes"
            button "Reject", id: "btn:reject", style: :danger
          end
        end
        result = renderer.render(card)

        attachment = result.first
        expect(attachment["actions"].size).to eq(2)

        approve = attachment["actions"][0]
        expect(approve["name"]).to eq("Approve")
        expect(approve["type"]).to eq("button")
        expect(approve["id"]).to eq("btn:approve")
        expect(approve["style"]).to eq("primary")

        reject = attachment["actions"][1]
        expect(reject["name"]).to eq("Reject")
        expect(reject["style"]).to eq("danger")
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

        attachment = result.first
        sel = attachment["actions"][0]
        expect(sel["type"]).to eq("select")
        expect(sel["name"]).to eq("Choose severity")
        expect(sel["options"].size).to eq(2)
        expect(sel["options"][0]).to eq({"text" => "SEV1", "value" => "sev1"})
      end

      it "renders link buttons" do
        card = ChatSDK.card do
          actions do
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        attachment = result.first
        link = attachment["actions"][0]
        expect(link["type"]).to eq("button")
        expect(link["name"]).to eq("View")
        expect(link.dig("integration", "url")).to eq("https://example.com")
      end

      it "renders a section" do
        card = ChatSDK.card do
          section "Details" do
            text "Some info"
          end
        end
        result = renderer.render(card)

        attachment = result.first
        expect(attachment["text"]).to include("**Details**")
        expect(attachment["text"]).to include("Some info")
      end

      it "renders dividers as markdown separators" do
        card = ChatSDK.card do
          text "Before"
          divider
          text "After"
        end
        result = renderer.render(card)

        attachment = result.first
        expect(attachment["text"]).to include("---")
      end

      context "with integration_url configured" do
        let(:renderer) { described_class.new(integration_url: "https://example.com/actions") }

        it "includes integration URL in button actions" do
          card = ChatSDK.card do
            actions do
              button "Click", id: "btn:click", value: "v1"
            end
          end
          result = renderer.render(card)

          button = result.first["actions"][0]
          expect(button.dig("integration", "url")).to eq("https://example.com/actions")
          expect(button.dig("integration", "context", "action")).to eq("btn:click")
          expect(button.dig("integration", "context", "value")).to eq("v1")
        end
      end
    end
  end
end
