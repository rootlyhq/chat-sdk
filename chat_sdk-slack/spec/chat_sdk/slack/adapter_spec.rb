# frozen_string_literal: true

require_relative "../../spec_helper"
require "openssl"
require "rack"

RSpec.describe ChatSDK::Slack::Adapter do
  subject { described_class.new(bot_token: bot_token, signing_secret: signing_secret) }

  let(:bot_token) { "xoxb-test-token-12345" }
  let(:signing_secret) { "test_signing_secret_abc123" }

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without bot_token" do
      expect { described_class.new(bot_token: nil, signing_secret: signing_secret) }
        .to raise_error(ChatSDK::ConfigurationError, /bot_token required/)
    end

    it "raises ConfigurationError without signing_secret" do
      expect { described_class.new(bot_token: bot_token, signing_secret: nil) }
        .to raise_error(ChatSDK::ConfigurationError, /signing_secret required/)
    end
  end

  describe "#name" do
    it "returns :slack" do
      expect(subject.name).to eq(:slack)
    end
  end

  describe "#client" do
    it "returns a Slack::Web::Client" do
      expect(subject.client).to be_a(::Slack::Web::Client)
    end
  end

  describe "#verify_request!" do
    def build_signed_request(body, secret: signing_secret, timestamp: Time.now.to_i.to_s)
      sig_basestring = "v0:#{timestamp}:#{body}"
      hex_digest = OpenSSL::HMAC.hexdigest("SHA256", secret, sig_basestring)
      signature = "v0=#{hex_digest}"

      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SLACK_REQUEST_TIMESTAMP" => timestamp,
        "HTTP_X_SLACK_SIGNATURE" => signature
      )
      Rack::Request.new(env)
    end

    it "accepts a valid signature" do
      body = '{"type":"event_callback"}'
      request = build_signed_request(body)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects an invalid signature" do
      body = '{"type":"event_callback"}'
      request = build_signed_request(body, secret: "wrong_secret")
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Invalid Slack signature/)
    end

    it "rejects missing signature headers" do
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => '{"type":"event_callback"}',
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing Slack signature headers/)
    end

    it "rejects requests that are too old" do
      body = '{"type":"event_callback"}'
      old_timestamp = (Time.now.to_i - 600).to_s
      request = build_signed_request(body, timestamp: old_timestamp)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /too old/)
    end
  end

  describe "#ack_response" do
    it "returns challenge response for url_verification" do
      body = '{"type":"url_verification","challenge":"test_challenge_xyz"}'
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      result = subject.ack_response(request)
      expect(result).to eq([200, {"content-type" => "text/plain"}, ["test_challenge_xyz"]])
    end

    it "returns nil for non-verification events" do
      body = '{"type":"event_callback","event":{}}'
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect(subject.ack_response(request)).to be_nil
    end
  end

  describe "#parse_events" do
    def build_request(body, content_type: "application/json")
      env = Rack::MockRequest.env_for(
        "/slack/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => content_type
      )
      Rack::Request.new(env)
    end

    context "app_mention event" do
      it "parses into a Mention event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "app_mention",
            "user" => "U123",
            "text" => "<@B456> hello bot",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("<@B456> hello bot")
        expect(event.message.author.id).to eq("U123")
        expect(event.channel_id).to eq("C789")
        expect(event.platform).to eq(:slack)
        expect(event.adapter_name).to eq(:slack)
      end
    end

    context "message event (channel)" do
      it "parses into a SubscribedMessage event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "hello channel",
            "ts" => "1234567890.123456",
            "channel" => "C789",
            "channel_type" => "channel"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(events.first.message.text).to eq("hello channel")
      end
    end

    context "message event (DM)" do
      it "parses into a DirectMessage event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "user" => "U123",
            "text" => "hello dm",
            "ts" => "1234567890.123456",
            "channel" => "D789",
            "channel_type" => "im"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::DirectMessage)
        expect(events.first.message.text).to eq("hello dm")
      end
    end

    context "message event from bot" do
      it "ignores bot messages" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "bot_id" => "B123",
            "text" => "bot message",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "message event with subtype" do
      it "ignores messages with subtypes other than file_share" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "message",
            "subtype" => "message_changed",
            "user" => "U123",
            "text" => "edited",
            "ts" => "1234567890.123456",
            "channel" => "C789"
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)
        expect(events).to be_empty
      end
    end

    context "reaction_added event" do
      it "parses into a Reaction event" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "reaction_added",
            "user" => "U123",
            "reaction" => "thumbsup",
            "item" => {"ts" => "1234567890.123456", "channel" => "C789"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Reaction)
        expect(event.emoji).to eq("thumbsup")
        expect(event.user_id).to eq("U123")
        expect(event.added?).to be true
      end
    end

    context "reaction_removed event" do
      it "parses into a Reaction event with added=false" do
        payload = {
          "type" => "event_callback",
          "event" => {
            "type" => "reaction_removed",
            "user" => "U123",
            "reaction" => "thumbsup",
            "item" => {"ts" => "1234567890.123456", "channel" => "C789"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first.added?).to be false
        expect(events.first.removed?).to be true
      end
    end

    context "block_actions" do
      it "parses into Action events" do
        payload = {
          "type" => "block_actions",
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:approve", "value" => "yes"}
          ]
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("yes")
        expect(event.user.id).to eq("U123")
        expect(event.trigger_id).to eq("T999")
      end
    end

    context "block_actions via form-encoded payload" do
      it "parses the payload parameter" do
        inner = {
          "type" => "block_actions",
          "user" => {"id" => "U123", "name" => "testuser"},
          "channel" => {"id" => "C789"},
          "message" => {"ts" => "1234567890.123456"},
          "trigger_id" => "T999",
          "actions" => [
            {"action_id" => "btn:ok", "value" => "clicked"}
          ]
        }
        body = "payload=#{Rack::Utils.escape(JSON.generate(inner))}"
        request = build_request(body, content_type: "application/x-www-form-urlencoded")
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first.action_id).to eq("btn:ok")
      end
    end

    context "slash command" do
      it "parses form-encoded slash command" do
        body = Rack::Utils.build_query(
          "command" => "/incident",
          "text" => "create server down",
          "user_id" => "U123",
          "channel_id" => "C789",
          "trigger_id" => "T999"
        )
        request = build_request(body, content_type: "application/x-www-form-urlencoded")
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SlashCommand)
        expect(event.command).to eq("/incident")
        expect(event.text).to eq("create server down")
        expect(event.user_id).to eq("U123")
        expect(event.channel_id).to eq("C789")
      end
    end
  end

  describe "#get_user" do
    it "returns an Author for a valid user" do
      allow(subject.client).to receive(:users_info)
        .with(user: "U123")
        .and_return({
          "ok" => true,
          "user" => {"id" => "U123", "name" => "alice", "is_bot" => false}
        })

      result = subject.get_user("U123")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.id).to eq("U123")
      expect(result.name).to eq("alice")
      expect(result.platform).to eq(:slack)
      expect(result.bot?).to be false
    end

    it "returns an Author with bot: true for bot users" do
      allow(subject.client).to receive(:users_info)
        .with(user: "B456")
        .and_return({
          "ok" => true,
          "user" => {"id" => "B456", "name" => "helperbot", "is_bot" => true}
        })

      result = subject.get_user("B456")
      expect(result).to be_a(ChatSDK::Author)
      expect(result.bot?).to be true
    end
  end

  describe "#schedule_message" do
    it "schedules a message and returns a Message" do
      post_at = Time.now.to_i + 3600

      allow(subject.client).to receive(:chat_scheduleMessage)
        .with(channel: "C789", text: "Reminder!", post_at: post_at)
        .and_return({
          "ok" => true,
          "channel" => "C789",
          "scheduled_message_id" => "Q1234ABCD",
          "post_at" => post_at
        })

      result = subject.schedule_message(channel_id: "C789", message: "Reminder!", post_at: post_at)

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("Q1234ABCD")
      expect(result.text).to eq("Reminder!")
      expect(result.channel_id).to eq("C789")
      expect(result.platform).to eq(:slack)
      expect(result.thread_id).to eq("Q1234ABCD")
    end

    it "schedules a threaded message" do
      post_at = Time.now.to_i + 3600

      allow(subject.client).to receive(:chat_scheduleMessage)
        .with(channel: "C789", text: "Follow-up", post_at: post_at, thread_ts: "1234567890.123456")
        .and_return({
          "ok" => true,
          "channel" => "C789",
          "scheduled_message_id" => "Q5678EFGH",
          "post_at" => post_at
        })

      result = subject.schedule_message(
        channel_id: "C789",
        message: "Follow-up",
        post_at: post_at,
        thread_id: "1234567890.123456"
      )

      expect(result).to be_a(ChatSDK::Message)
      expect(result.id).to eq("Q5678EFGH")
      expect(result.thread_id).to eq("1234567890.123456")
    end
  end

  describe "#publish_home_view" do
    it "publishes a home tab view" do
      view = {type: "home", blocks: [{type: "section", text: {type: "mrkdwn", text: "Hello"}}]}

      allow(subject.client).to receive(:views_publish)
        .with(user_id: "U123", view: view)
        .and_return({"ok" => true})

      expect { subject.publish_home_view(user_id: "U123", view: view) }
        .not_to raise_error
    end
  end

  describe "#set_suggested_prompts" do
    it "sets suggested prompts on a thread" do
      prompts = [{title: "Summarize", message: "Summarize this thread"}]

      allow(subject.client).to receive(:assistant_threads_setSuggestedPrompts)
        .with(channel_id: "C123", thread_ts: "1234.5678", prompts: prompts)
        .and_return({"ok" => true})

      expect { subject.set_suggested_prompts(channel_id: "C123", thread_id: "1234.5678", prompts: prompts) }
        .not_to raise_error
    end
  end

  describe "#set_assistant_status" do
    it "sets assistant status on a thread" do
      allow(subject.client).to receive(:assistant_threads_setStatus)
        .with(channel_id: "C123", thread_ts: "1234.5678", status: "Thinking...")
        .and_return({"ok" => true})

      expect { subject.set_assistant_status(channel_id: "C123", thread_id: "1234.5678", status: "Thinking...") }
        .not_to raise_error
    end
  end

  describe "#set_assistant_title" do
    it "sets assistant title on a thread" do
      allow(subject.client).to receive(:assistant_threads_setTitle)
        .with(channel_id: "C123", thread_ts: "1234.5678", title: "Incident Summary")
        .and_return({"ok" => true})

      expect { subject.set_assistant_title(channel_id: "C123", thread_id: "1234.5678", title: "Incident Summary") }
        .not_to raise_error
    end
  end

  describe "#mention" do
    it "formats a Slack user mention" do
      expect(subject.mention("U123")).to eq("<@U123>")
    end
  end

  describe ChatSDK::Slack::BlockKitRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node as a section block" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello world"})
        result = renderer.render(node)
        expect(result).to eq([{type: "section", text: {type: "mrkdwn", text: "Hello world"}}])
      end

      it "renders a card with multiple children" do
        card = ChatSDK.card do
          text "Line 1"
          divider
          text "Line 2"
        end
        result = renderer.render(card)

        expect(result.size).to eq(3)
        expect(result[0][:type]).to eq("section")
        expect(result[0][:text][:text]).to eq("Line 1")
        expect(result[1][:type]).to eq("divider")
        expect(result[2][:type]).to eq("section")
        expect(result[2][:text][:text]).to eq("Line 2")
      end

      it "renders fields" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        expect(result[0][:type]).to eq("section")
        expect(result[0][:fields].size).to eq(2)
        expect(result[0][:fields][0]).to eq({type: "mrkdwn", text: "*Status*\nActive"})
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        expect(result[0][:type]).to eq("image")
        expect(result[0][:image_url]).to eq("https://example.com/img.png")
        expect(result[0][:alt_text]).to eq("Screenshot")
      end

      it "renders actions with buttons" do
        card = ChatSDK.card do
          actions do
            button "Approve", id: "btn:approve", style: :primary, value: "yes"
            button "Reject", id: "btn:reject", style: :danger
            link_button "View", url: "https://example.com"
          end
        end
        result = renderer.render(card)

        expect(result.size).to eq(1)
        actions_block = result[0]
        expect(actions_block[:type]).to eq("actions")
        expect(actions_block[:elements].size).to eq(3)

        approve_btn = actions_block[:elements][0]
        expect(approve_btn[:type]).to eq("button")
        expect(approve_btn[:text]).to eq({type: "plain_text", text: "Approve"})
        expect(approve_btn[:action_id]).to eq("btn:approve")
        expect(approve_btn[:style]).to eq("primary")
        expect(approve_btn[:value]).to eq("yes")

        reject_btn = actions_block[:elements][1]
        expect(reject_btn[:style]).to eq("danger")

        link_btn = actions_block[:elements][2]
        expect(link_btn[:url]).to eq("https://example.com")
      end

      it "renders a select menu" do
        card = ChatSDK.card do
          actions do
            select id: "severity_select", placeholder: "Choose severity" do
              option "SEV1", value: "sev1"
              option "SEV2", value: "sev2", description: "Less critical"
            end
          end
        end
        result = renderer.render(card)

        select_el = result[0][:elements][0]
        expect(select_el[:type]).to eq("static_select")
        expect(select_el[:action_id]).to eq("severity_select")
        expect(select_el[:placeholder]).to eq({type: "plain_text", text: "Choose severity"})
        expect(select_el[:options].size).to eq(2)
        expect(select_el[:options][1][:description]).to eq({type: "plain_text", text: "Less critical"})
      end
    end
  end

  describe ChatSDK::Slack::ModalRenderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a modal with text input" do
        modal = ChatSDK::Modals::Builder.new(
          title: "Create Incident",
          submit_label: "Submit",
          callback_id: "incident_form"
        ) do
          text_input id: "title", label: "Title", placeholder: "Enter title"
          text_input id: "description", label: "Description", multiline: true, optional: true
        end.build

        result = renderer.render(modal)

        expect(result[:type]).to eq("modal")
        expect(result[:title]).to eq({type: "plain_text", text: "Create Incident"})
        expect(result[:submit]).to eq({type: "plain_text", text: "Submit"})
        expect(result[:callback_id]).to eq("incident_form")
        expect(result[:blocks].size).to eq(2)

        title_block = result[:blocks][0]
        expect(title_block[:type]).to eq("input")
        expect(title_block[:block_id]).to eq("title")
        expect(title_block[:element][:type]).to eq("plain_text_input")
        expect(title_block[:element][:multiline]).to be(false)
        expect(title_block[:element][:placeholder]).to eq({type: "plain_text", text: "Enter title"})

        desc_block = result[:blocks][1]
        expect(desc_block[:element][:multiline]).to be(true)
        expect(desc_block[:optional]).to be(true)
      end

      it "renders a modal with select input" do
        modal = ChatSDK::Modals::Builder.new(title: "Severity") do
          select_input id: "sev", label: "Severity", placeholder: "Pick one" do
            option "SEV1", value: "sev1"
            option "SEV2", value: "sev2"
          end
        end.build

        result = renderer.render(modal)

        select_block = result[:blocks][0]
        expect(select_block[:element][:type]).to eq("static_select")
        expect(select_block[:element][:options].size).to eq(2)
      end
    end
  end
end
