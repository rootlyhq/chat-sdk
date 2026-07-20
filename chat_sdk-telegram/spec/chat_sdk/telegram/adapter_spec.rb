# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::Telegram::Adapter do
  subject do
    described_class.new(
      bot_token: bot_token,
      secret_token: secret_token,
      bot_username: bot_username
    )
  end

  let(:bot_token) { "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" }
  let(:secret_token) { "my-secret-token" }
  let(:bot_username) { "testbot" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without bot_token" do
      expect { described_class.new(bot_token: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /bot_token required/)
    end

    it "falls back to environment variables" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return("env-token")
      allow(ENV).to receive(:[]).with("TELEGRAM_WEBHOOK_SECRET_TOKEN").and_return("env-secret")
      allow(ENV).to receive(:[]).with("TELEGRAM_BOT_USERNAME").and_return("envbot")

      adapter = described_class.new
      expect(adapter.name).to eq(:telegram)
    end
  end

  describe "#name" do
    it "returns :telegram" do
      expect(subject.name).to eq(:telegram)
    end
  end

  describe "#client" do
    it "returns an ApiClient" do
      expect(subject.client).to be_a(ChatSDK::Telegram::ApiClient)
    end
  end

  describe "#mention" do
    it "formats a Telegram mention link" do
      expect(subject.mention("123456")).to eq("[user](tg://user?id=123456)")
    end
  end

  describe "#verify_request!" do
    def build_request(body, headers = {})
      env = Rack::MockRequest.env_for(
        "/webhooks/telegram",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        **headers
      )
      Rack::Request.new(env)
    end

    it "accepts a valid secret token" do
      request = build_request('{"update_id":1}', "HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN" => secret_token)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid secret token" do
      request = build_request('{"update_id":1}', "HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN" => "wrong-token")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Telegram secret token/)
    end

    it "rejects missing secret token header" do
      request = build_request('{"update_id":1}')
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Telegram secret token/)
    end

    it "skips verification when no secret_token is configured" do
      adapter = described_class.new(bot_token: bot_token, secret_token: nil)
      request = build_request('{"update_id":1}')
      expect(adapter.verify_request!(request)).to be(true)
    end
  end

  describe "#ack_response" do
    it "always returns nil" do
      env = Rack::MockRequest.env_for("/webhooks/telegram", method: "POST", input: "{}")
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/webhooks/telegram",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "message with bot_command entity" do
      it "parses into SlashCommand event" do
        payload = {
          "update_id" => 1,
          "message" => {
            "message_id" => 100,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "/start hello world",
            "entities" => [{"type" => "bot_command", "offset" => 0, "length" => 6}]
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SlashCommand)
        expect(event.command).to eq("/start")
        expect(event.text).to eq("hello world")
        expect(event.user_id).to eq("42")
        expect(event.channel_id).to eq("-1001")
        expect(event.platform).to eq(:telegram)
        expect(event.adapter_name).to eq(:telegram)
      end

      it "handles commands with @bot suffix" do
        payload = {
          "update_id" => 2,
          "message" => {
            "message_id" => 101,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "/help@testbot",
            "entities" => [{"type" => "bot_command", "offset" => 0, "length" => 13}]
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event.command).to eq("/help")
        expect(event.text).to eq("")
      end
    end

    context "message with @bot mention" do
      it "parses into Mention event" do
        payload = {
          "update_id" => 3,
          "message" => {
            "message_id" => 102,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "Hey @testbot what's up?"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("Hey @testbot what's up?")
        expect(event.channel_id).to eq("-1001")
        expect(event.platform).to eq(:telegram)
      end
    end

    context "private message (DM)" do
      it "parses into DirectMessage event" do
        payload = {
          "update_id" => 4,
          "message" => {
            "message_id" => 103,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => 42, "type" => "private"},
            "text" => "Hello bot"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::DirectMessage)
        expect(event.message.text).to eq("Hello bot")
        expect(event.channel_id).to eq("42")
      end
    end

    context "group message without mention" do
      it "parses into SubscribedMessage event" do
        payload = {
          "update_id" => 5,
          "message" => {
            "message_id" => 104,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "Just a regular message"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SubscribedMessage)
      end
    end

    context "callback_query" do
      it "parses into Action event" do
        payload = {
          "update_id" => 6,
          "callback_query" => {
            "id" => "cb123",
            "from" => {"id" => 42, "username" => "alice"},
            "message" => {
              "message_id" => 200,
              "chat" => {"id" => -1001, "type" => "group"}
            },
            "data" => "incident:ack"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("incident")
        expect(event.value).to eq("ack")
        expect(event.user.id).to eq("42")
        expect(event.channel_id).to eq("-1001")
        expect(event.thread_id).to eq("200")
        expect(event.platform).to eq(:telegram)
      end

      it "handles callback data without colon" do
        payload = {
          "update_id" => 7,
          "callback_query" => {
            "id" => "cb456",
            "from" => {"id" => 42, "username" => "alice"},
            "message" => {
              "message_id" => 201,
              "chat" => {"id" => -1001, "type" => "group"}
            },
            "data" => "approve"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        event = events.first
        expect(event.action_id).to eq("approve")
        expect(event.value).to eq("approve")
      end
    end

    context "message_reaction (added)" do
      it "parses into Reaction event with added: true" do
        payload = {
          "update_id" => 9,
          "message_reaction" => {
            "chat" => {"id" => -1001, "type" => "group"},
            "message_id" => 300,
            "user" => {"id" => 42, "username" => "alice"},
            "new_reaction" => [{"type" => "emoji", "emoji" => "\u{1F44D}"}],
            "old_reaction" => []
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("\u{1F44D}")
        expect(event.user_id).to eq("42")
        expect(event.message_id).to eq("300")
        expect(event.channel_id).to eq("-1001")
        expect(event.added?).to be true
        expect(event.platform).to eq(:telegram)
        expect(event.adapter_name).to eq(:telegram)
      end
    end

    context "message_reaction (removed)" do
      it "parses into Reaction event with added: false" do
        payload = {
          "update_id" => 10,
          "message_reaction" => {
            "chat" => {"id" => -1001, "type" => "group"},
            "message_id" => 301,
            "user" => {"id" => 42, "username" => "alice"},
            "new_reaction" => [],
            "old_reaction" => [{"type" => "emoji", "emoji" => "\u{2764}"}]
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("\u{2764}")
        expect(event.user_id).to eq("42")
        expect(event.message_id).to eq("301")
        expect(event.removed?).to be true
      end
    end

    context "reply thread_id resolution" do
      it "uses reply_to_message.message_id for thread_id when replying" do
        payload = {
          "update_id" => 8,
          "message" => {
            "message_id" => 110,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "a reply",
            "reply_to_message" => {"message_id" => 105}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        event = events.first
        expect(event.thread_id).to eq("105")
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
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"message_id" => 500, "text" => "Hello!", "from" => {"id" => 99, "username" => "testbot"}, "chat" => {"id" => -1001}}}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.post_message(channel_id: "-1001", message: "Hello!")
      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("500")
      expect(result.platform).to eq(:telegram)
    end

    it "sends a card message with inline keyboard" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
        .with { |req|
          body = JSON.parse(req.body)
          body["reply_markup"].is_a?(Hash)
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"message_id" => 501, "from" => {"id" => 99, "username" => "testbot"}}}),
          headers: {"Content-Type" => "application/json"}
        )

      card = ChatSDK.card do
        text "Incident Update"
        actions do
          button "Ack", id: "incident:ack", style: :primary, value: "4821"
        end
      end

      result = subject.post_message(
        channel_id: "-1001",
        message: ChatSDK::PostableMessage.new(card: card, text: "Incident Update")
      )
      expect(result.id).to eq("501")
    end

    it "sends a message with thread_id as reply_to_message_id" do
      stub = stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
        .with { |req|
          body = JSON.parse(req.body)
          body["reply_to_message_id"] == "100"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"message_id" => 502, "from" => {"id" => 99, "username" => "testbot"}}}),
          headers: {"Content-Type" => "application/json"}
        )

      subject.post_message(channel_id: "-1001", message: "Reply!", thread_id: "100")
      expect(stub).to have_been_requested
    end
  end

  describe "#edit_message" do
    it "updates a message" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/editMessageText")
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"message_id" => 500, "text" => "Updated"}}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.edit_message(channel_id: "-1001", message_id: 500, message: "Updated")
      expect(result["message_id"]).to eq(500)
    end
  end

  describe "#delete_message" do
    it "deletes a message" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/deleteMessage")
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => true}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.delete_message(channel_id: "-1001", message_id: 500) }.not_to raise_error
    end
  end

  describe "#add_reaction" do
    it "sets a reaction on a message" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/setMessageReaction")
        .with { |req|
          body = JSON.parse(req.body)
          body["reaction"].is_a?(Array) && body["reaction"].first["emoji"] == "\u{1F44D}"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => true}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.add_reaction(channel_id: "-1001", message_id: 500, emoji: "\u{1F44D}") }
        .not_to raise_error
    end
  end

  describe "#remove_reaction" do
    it "removes reactions from a message" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/setMessageReaction")
        .with { |req|
          body = JSON.parse(req.body)
          body["reaction"] == []
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => true}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.remove_reaction(channel_id: "-1001", message_id: 500, emoji: "\u{1F44D}") }
        .not_to raise_error
    end
  end

  describe "#get_user" do
    it "returns an Author for a valid user" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/getChat")
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"id" => 42, "type" => "private", "username" => "alice", "first_name" => "Alice"}}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.get_user("42")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.id).to eq("42")
      expect(result.name).to eq("alice")
      expect(result.platform).to eq(:telegram)
      expect(result.bot?).to be false
    end

    it "falls back to first_name when username is absent" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/getChat")
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => {"id" => 99, "type" => "private", "first_name" => "Bob"}}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.get_user("99")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.name).to eq("Bob")
    end
  end

  describe "#open_dm" do
    it "returns the user_id directly" do
      expect(subject.open_dm("42")).to eq("42")
    end
  end

  describe "#start_typing" do
    it "sends a typing chat action" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendChatAction")
        .with { |req|
          body = JSON.parse(req.body)
          body["action"] == "typing"
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => true}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.start_typing(channel_id: "-1001") }.not_to raise_error
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

    it "raises NotSupportedError for message_history" do
      expect { subject.fetch_messages(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "does not support ephemeral_messages capability" do
      expect(subject.supports?(:ephemeral_messages)).to be false
    end

    it "does not support modals capability" do
      expect(subject.supports?(:modals)).to be false
    end

    it "does not support threads capability" do
      expect(subject.supports?(:threads)).to be false
    end

    it "does not support message_history capability" do
      expect(subject.supports?(:message_history)).to be false
    end
  end

  describe "#render" do
    it "renders a card as text with inline keyboard" do
      card = ChatSDK.card do
        text "Hello"
      end
      msg = ChatSDK::PostableMessage.new(card: card, text: "Hello")

      result = subject.render(msg)
      expect(result).to be_a(Hash)
      expect(result[:text]).to eq("Hello")
    end

    it "renders plain text as-is" do
      msg = ChatSDK::PostableMessage.new(text: "Plain text")
      result = subject.render(msg)
      expect(result).to eq("Plain text")
    end
  end

  describe ChatSDK::Telegram::KeyboardRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)

        expect(result).to be_a(Hash)
        expect(result[:text]).to eq("Hello world")
      end

      it "renders a card with title and text" do
        card = ChatSDK.card(title: "Incident #4821") do
          text "Details here"
        end
        result = renderer.render(card)

        expect(result[:text]).to include("*Incident #4821*")
        expect(result[:text]).to include("Details here")
      end

      it "renders a card with subtitle" do
        card = ChatSDK.card(title: "Title", subtitle: "Subtitle") do
          text "Body"
        end
        result = renderer.render(card)

        expect(result[:text]).to include("_Subtitle_")
      end

      it "renders fields as bold label: value pairs" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        expect(result[:text]).to include("*Status*: Active")
        expect(result[:text]).to include("*Severity*: SEV1")
      end

      it "renders dividers" do
        card = ChatSDK.card do
          text "Before"
          divider
          text "After"
        end
        result = renderer.render(card)

        expect(result[:text]).to include("───")
      end

      it "renders images as markdown links" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)

        expect(result[:text]).to include("[Image](https://example.com/img.png)")
      end

      it "renders buttons as inline keyboard" do
        card = ChatSDK.card do
          actions do
            button "Approve", id: "btn_approve", style: :primary, value: "yes"
            button "Reject", id: "btn_reject", style: :danger
          end
        end
        result = renderer.render(card)

        expect(result[:reply_markup]).to be_a(Hash)
        keyboard = result[:reply_markup]["inline_keyboard"]
        expect(keyboard.size).to eq(1)
        row = keyboard.first
        expect(row.size).to eq(2)

        approve = row[0]
        expect(approve["text"]).to eq("Approve")
        expect(approve["callback_data"]).to eq("btn_approve:yes")

        reject = row[1]
        expect(reject["text"]).to eq("Reject")
        expect(reject["callback_data"]).to eq("btn_reject")
      end

      it "renders link buttons with URL" do
        card = ChatSDK.card do
          actions do
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        keyboard = result[:reply_markup]["inline_keyboard"]
        link = keyboard.first.first
        expect(link["text"]).to eq("View")
        expect(link["url"]).to eq("https://example.com")
      end

      it "renders select as one button per option" do
        card = ChatSDK.card do
          actions do
            select id: "severity", placeholder: "Choose" do
              option "SEV1", value: "sev1"
              option "SEV2", value: "sev2"
            end
          end
        end
        result = renderer.render(card)

        keyboard = result[:reply_markup]["inline_keyboard"]
        # select creates separate rows for each option
        expect(keyboard.size).to eq(2)
        expect(keyboard[0].first["text"]).to eq("SEV1")
        expect(keyboard[0].first["callback_data"]).to eq("severity:sev1")
        expect(keyboard[1].first["text"]).to eq("SEV2")
        expect(keyboard[1].first["callback_data"]).to eq("severity:sev2")
      end

      it "renders a section" do
        card = ChatSDK.card do
          section "Details" do
            text "Some info"
          end
        end
        result = renderer.render(card)

        expect(result[:text]).to include("*Details*")
        expect(result[:text]).to include("Some info")
      end

      it "returns no reply_markup when there are no actions" do
        card = ChatSDK.card do
          text "Just text"
        end
        result = renderer.render(card)

        expect(result).not_to have_key(:reply_markup)
      end
    end
  end

  describe "#get_updates (ApiClient)" do
    it "calls getUpdates with timeout" do
      stub = stub_request(:post, "https://api.telegram.org/bot#{bot_token}/getUpdates")
        .with { |req|
          body = JSON.parse(req.body)
          body["timeout"] == 30 && !body.key?("offset")
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => []}),
          headers: {"Content-Type" => "application/json"}
        )

      result = subject.client.get_updates(timeout: 30)
      expect(stub).to have_been_requested
      expect(result).to eq([])
    end

    it "passes offset when provided" do
      stub = stub_request(:post, "https://api.telegram.org/bot#{bot_token}/getUpdates")
        .with { |req|
          body = JSON.parse(req.body)
          body["offset"] == 42 && body["timeout"] == 10
        }
        .to_return(
          status: 200,
          body: JSON.generate({"ok" => true, "result" => []}),
          headers: {"Content-Type" => "application/json"}
        )

      subject.client.get_updates(offset: 42, timeout: 10)
      expect(stub).to have_been_requested
    end
  end

  describe "#poll" do
    it "yields parsed events from updates and advances offset" do
      updates = [
        {
          "update_id" => 100,
          "message" => {
            "message_id" => 1,
            "from" => {"id" => 42, "username" => "alice"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "Hello"
          }
        },
        {
          "update_id" => 101,
          "message" => {
            "message_id" => 2,
            "from" => {"id" => 43, "username" => "bob"},
            "chat" => {"id" => -1001, "type" => "group"},
            "text" => "World"
          }
        }
      ]

      call_count = 0
      allow(subject.client).to receive(:get_updates) do |**kwargs|
        call_count += 1
        if call_count == 1
          expect(kwargs[:offset]).to be_nil
          updates
        else
          # Second call should have offset = 102 (last update_id + 1)
          expect(kwargs[:offset]).to eq(102)
          raise StopIteration
        end
      end

      collected_events = []
      begin
        subject.poll(timeout: 0) { |event| collected_events << event }
      rescue StopIteration
        # expected — breaks the loop
      end

      expect(collected_events.size).to eq(2)
      expect(collected_events[0]).to be_a(ChatSDK::Events::SubscribedMessage)
      expect(collected_events[0].message.text).to eq("Hello")
      expect(collected_events[1]).to be_a(ChatSDK::Events::SubscribedMessage)
      expect(collected_events[1].message.text).to eq("World")
    end

    it "handles non-array responses gracefully" do
      call_count = 0
      allow(subject.client).to receive(:get_updates) do
        call_count += 1
        raise StopIteration if call_count > 1

        {} # non-array response
      end

      collected_events = []
      begin
        subject.poll(timeout: 0) { |event| collected_events << event }
      rescue StopIteration
        # expected
      end

      expect(collected_events).to be_empty
    end
  end

  describe "API error handling" do
    it "raises RateLimitedError on 429" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
        .to_return(
          status: 429,
          body: JSON.generate({"ok" => false, "description" => "Too Many Requests", "parameters" => {"retry_after" => 30}}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "-1001", message: "Hello!") }
        .to raise_error(ChatSDK::RateLimitedError)
    end

    it "raises PlatformError on other errors" do
      stub_request(:post, "https://api.telegram.org/bot#{bot_token}/sendMessage")
        .to_return(
          status: 400,
          body: JSON.generate({"ok" => false, "description" => "Bad Request: chat not found"}),
          headers: {"Content-Type" => "application/json"}
        )

      expect { subject.post_message(channel_id: "-1001", message: "Hello!") }
        .to raise_error(ChatSDK::PlatformError, /Bad Request/)
    end
  end
end
