# frozen_string_literal: true

require_relative "../../spec_helper"
require "rack"

RSpec.describe ChatSDK::GChat::Adapter do
  subject { described_class.new(project_number: project_number) }

  let(:project_number) { "123456789" }
  let(:mock_credentials) { instance_double(Google::Auth::ServiceAccountCredentials) }
  let(:mock_client) { instance_double(Google::Apps::Chat::V1::ChatService::Client) }

  before do
    allow(Google::Auth).to receive(:get_application_default).and_return(mock_credentials)
    allow(Google::Apps::Chat::V1::ChatService::Client).to receive(:new).and_return(mock_client)
  end

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without project_number" do
      expect { described_class.new(project_number: "") }
        .to raise_error(ChatSDK::ConfigurationError, /project_number required/)
    end
  end

  describe "#name" do
    it "returns :gchat" do
      expect(subject.name).to eq(:gchat)
    end
  end

  describe "#verify_request!" do
    let(:valid_token) { "valid.jwt.token" }
    let(:token_payload) { {"iss" => "chat@system.gserviceaccount.com", "aud" => project_number} }

    it "accepts a valid bearer token" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .with(valid_token, aud: project_number)
        .and_return(token_payload)

      env = Rack::MockRequest.env_for(
        "/gchat/events",
        :method => "POST",
        :input => "{}",
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer #{valid_token}"
      )
      request = Rack::Request.new(env)
      expect(subject.verify_request!(request)).to be(true)
    end

    it "rejects a missing bearer token" do
      env = Rack::MockRequest.env_for(
        "/gchat/events",
        :method => "POST",
        :input => "{}",
        "CONTENT_TYPE" => "application/json"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Missing bearer token/)
    end

    it "rejects an invalid token" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .and_raise(Google::Auth::IDTokens::VerificationError.new("bad token"))

      env = Rack::MockRequest.env_for(
        "/gchat/events",
        :method => "POST",
        :input => "{}",
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer invalid.token"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /verification failed/)
    end

    it "rejects a token with unexpected issuer" do
      bad_payload = {"iss" => "badactor@evil.com", "aud" => project_number}
      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .with("suspect.token", aud: project_number)
        .and_return(bad_payload)

      env = Rack::MockRequest.env_for(
        "/gchat/events",
        :method => "POST",
        :input => "{}",
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer suspect.token"
      )
      request = Rack::Request.new(env)
      expect { subject.verify_request!(request) }
        .to raise_error(ChatSDK::SignatureVerificationError, /Unexpected issuer/)
    end
  end

  describe "#parse_events" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/gchat/events",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    context "MESSAGE event with bot mention" do
      it "parses into a Mention event" do
        payload = {
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
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("@Bot hello")
        expect(event.message.author.id).to eq("123")
        expect(event.message.author.name).to eq("Alice")
        expect(event.channel_id).to eq("SPACE1")
        expect(event.thread_id).to eq("THREAD1")
        expect(event.platform).to eq(:gchat)
        expect(event.adapter_name).to eq(:gchat)
      end
    end

    context "MESSAGE event without bot mention" do
      it "parses into a SubscribedMessage event" do
        payload = {
          "type" => "MESSAGE",
          "message" => {
            "name" => "spaces/SPACE1/messages/MSG2",
            "sender" => {"name" => "users/456", "displayName" => "Bob"},
            "text" => "just a message",
            "thread" => {"name" => "spaces/SPACE1/threads/THREAD2"},
            "space" => {"name" => "spaces/SPACE1"}
          }
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        expect(events.first).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(events.first.message.text).to eq("just a message")
      end
    end

    context "CARD_CLICKED event" do
      it "parses into an Action event" do
        payload = {
          "type" => "CARD_CLICKED",
          "action" => {
            "actionMethodName" => "btn:approve",
            "parameters" => [{"key" => "value", "value" => "yes"}]
          },
          "user" => {"name" => "users/123", "displayName" => "Alice"},
          "message" => {
            "name" => "spaces/SPACE1/messages/MSG1",
            "space" => {"name" => "spaces/SPACE1"},
            "thread" => {"name" => "spaces/SPACE1/threads/THREAD1"}
          },
          "space" => {"name" => "spaces/SPACE1"}
        }
        request = build_request(JSON.generate(payload))
        events = subject.parse_events(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:approve")
        expect(event.value).to eq("yes")
        expect(event.user.id).to eq("123")
        expect(event.channel_id).to eq("SPACE1")
      end
    end

    context "ADDED_TO_SPACE event" do
      it "returns empty array" do
        payload = {"type" => "ADDED_TO_SPACE", "space" => {"name" => "spaces/SPACE1"}}
        request = build_request(JSON.generate(payload))
        expect(subject.parse_events(request)).to be_empty
      end
    end

    context "REMOVED_FROM_SPACE event" do
      it "returns empty array" do
        payload = {"type" => "REMOVED_FROM_SPACE", "space" => {"name" => "spaces/SPACE1"}}
        request = build_request(JSON.generate(payload))
        expect(subject.parse_events(request)).to be_empty
      end
    end

    context "invalid JSON" do
      it "returns empty array" do
        request = build_request("not valid json")
        expect(subject.parse_events(request)).to be_empty
      end
    end
  end

  describe "#post_message" do
    it "creates a message via the GAPIC client" do
      result = double("result",
        name: "spaces/SPACE1/messages/MSG99",
        thread: double(name: "spaces/SPACE1/threads/THREAD99"))
      allow(mock_client).to receive(:create_message).and_return(result)

      response = subject.post_message(
        channel_id: "SPACE1",
        message: "Hello Google Chat"
      )

      expect(mock_client).to have_received(:create_message).with(
        parent: "spaces/SPACE1",
        message: hash_including(text: "Hello Google Chat")
      )
      expect(response).to be_a(ChatSDK::Message)
      expect(response.id).to eq("MSG99")
      expect(response.platform).to eq(:gchat)
    end

    it "includes thread when thread_id is provided" do
      result = double("result",
        name: "spaces/SPACE1/messages/MSG100",
        thread: double(name: "spaces/SPACE1/threads/THREAD1"))
      allow(mock_client).to receive(:create_message).and_return(result)

      subject.post_message(
        channel_id: "SPACE1",
        message: "Threaded reply",
        thread_id: "THREAD1"
      )

      expect(mock_client).to have_received(:create_message).with(
        parent: "spaces/SPACE1",
        message: hash_including(
          text: "Threaded reply",
          thread: {name: "spaces/SPACE1/threads/THREAD1"}
        )
      )
    end

    it "renders card messages" do
      card = ChatSDK.card(title: "Alert") do
        text "Server is down"
      end
      result = double("result",
        name: "spaces/SPACE1/messages/MSG101",
        thread: double(name: "spaces/SPACE1/threads/T1"))
      allow(mock_client).to receive(:create_message).and_return(result)

      subject.post_message(channel_id: "SPACE1", message: card)

      expect(mock_client).to have_received(:create_message).with(
        parent: "spaces/SPACE1",
        message: hash_including(:cards_v2, :text)
      )
    end
  end

  describe "#edit_message" do
    it "updates a message via the GAPIC client" do
      allow(mock_client).to receive(:update_message).and_return(double("result"))

      subject.edit_message(
        channel_id: "SPACE1",
        message_id: "MSG1",
        message: "Updated text"
      )

      expect(mock_client).to have_received(:update_message).with(
        message: hash_including(
          text: "Updated text",
          name: "spaces/SPACE1/messages/MSG1"
        ),
        update_mask: an_instance_of(Google::Protobuf::FieldMask)
      )
    end
  end

  describe "#delete_message" do
    it "deletes a message via the GAPIC client" do
      allow(mock_client).to receive(:delete_message).and_return(nil)

      subject.delete_message(channel_id: "SPACE1", message_id: "MSG1")

      expect(mock_client).to have_received(:delete_message).with(
        name: "spaces/SPACE1/messages/MSG1"
      )
    end
  end

  describe "#post_ephemeral" do
    it "creates a message with private_message_viewer" do
      result = double("result",
        name: "spaces/SPACE1/messages/MSG_EPH",
        thread: double(name: "spaces/SPACE1/threads/T1"))
      allow(mock_client).to receive(:create_message).and_return(result)

      subject.post_ephemeral(
        channel_id: "SPACE1",
        user_id: "USER1",
        message: "Only you can see this"
      )

      expect(mock_client).to have_received(:create_message).with(
        parent: "spaces/SPACE1",
        message: hash_including(
          text: "Only you can see this",
          private_message_viewer: {name: "users/USER1"}
        )
      )
    end
  end

  describe "#mention" do
    it "formats a Google Chat user mention" do
      expect(subject.mention("123")).to eq("<users/123>")
    end
  end

  describe "capability gaps" do
    it "raises NotSupportedError for modals" do
      expect { subject.open_modal(trigger_id: "T1", modal: ChatSDK::Cards::Node.new(:modal)) }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for file_uploads" do
      expect { subject.upload_file(channel_id: "C1", io: StringIO.new(""), filename: "f.txt") }
        .to raise_error(ChatSDK::NotSupportedError)
    end

    it "raises NotSupportedError for typing_indicator" do
      expect { subject.start_typing(channel_id: "C1") }
        .to raise_error(ChatSDK::NotSupportedError)
    end
  end

  describe ChatSDK::GChat::CardV2Renderer do
    let(:renderer) { described_class.new }

    describe "#render" do
      it "renders a text node" do
        node = ChatSDK::Cards::Node.new(:text, attributes: {content: "Hello"})
        result = renderer.render(node)
        expect(result[:cards_v2]).to be_an(Array)
        card = result[:cards_v2][0][:card]
        widget = card[:sections][0][:widgets][0]
        expect(widget).to eq({textParagraph: {text: "Hello"}})
      end

      it "renders a card with title and children" do
        card = ChatSDK.card(title: "Incident", subtitle: "SEV1") do
          text "Server down"
          divider
          text "Investigating"
        end
        result = renderer.render(card)

        card_data = result[:cards_v2][0][:card]
        expect(card_data[:header]).to eq({title: "Incident", subtitle: "SEV1"})
        expect(card_data[:sections].size).to be >= 2
      end

      it "renders fields as decorated text" do
        card = ChatSDK.card do
          fields do
            field "Status", "Active"
            field "Severity", "SEV1"
          end
        end
        result = renderer.render(card)

        card_data = result[:cards_v2][0][:card]
        widgets = card_data[:sections].flat_map { |s| s[:widgets] }
        decorated = widgets.find { |w| w[:decoratedText] }
        expect(decorated).not_to be_nil
        expect(decorated[:decoratedText][:topLabel]).to include("Status")
        expect(decorated[:decoratedText][:text]).to include("Active")
      end

      it "renders an image" do
        card = ChatSDK.card do
          image url: "https://example.com/img.png", alt: "Screenshot"
        end
        result = renderer.render(card)

        card_data = result[:cards_v2][0][:card]
        widgets = card_data[:sections].flat_map { |s| s[:widgets] }
        img_widget = widgets.find { |w| w[:image] }
        expect(img_widget[:image][:imageUrl]).to eq("https://example.com/img.png")
        expect(img_widget[:image][:altText]).to eq("Screenshot")
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

        card_data = result[:cards_v2][0][:card]
        widgets = card_data[:sections].flat_map { |s| s[:widgets] }
        btn_list = widgets.find { |w| w[:buttonList] }
        expect(btn_list).not_to be_nil

        buttons = btn_list[:buttonList][:buttons]
        expect(buttons.size).to eq(3)

        approve = buttons[0]
        expect(approve[:text]).to eq("Approve")
        expect(approve[:onClick][:action][:actionMethodName]).to eq("btn:approve")
        expect(approve[:onClick][:action][:parameters]).to eq([{key: "value", value: "yes"}])
        expect(approve[:color]).to include(green: 0.53)

        reject = buttons[1]
        expect(reject[:color]).to include(red: 0.87)

        link = buttons[2]
        expect(link[:onClick][:openLink][:url]).to eq("https://example.com")
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

        card_data = result[:cards_v2][0][:card]
        widgets = card_data[:sections].flat_map { |s| s[:widgets] }
        # Select is rendered separately from buttonList since GChat treats it as its own widget
        select_widget = widgets.find { |w| w[:selectionInput] }
        expect(select_widget).not_to be_nil
        expect(select_widget[:selectionInput][:name]).to eq("severity_select")
        expect(select_widget[:selectionInput][:type]).to eq("DROPDOWN")
        expect(select_widget[:selectionInput][:items].size).to eq(2)
      end

      it "renders a divider" do
        card = ChatSDK.card do
          text "Before"
          divider
          text "After"
        end
        result = renderer.render(card)

        card_data = result[:cards_v2][0][:card]
        all_widgets = card_data[:sections].flat_map { |s| s[:widgets] }
        dividers = all_widgets.select { |w| w[:divider] }
        expect(dividers).not_to be_empty
      end
    end
  end
end
