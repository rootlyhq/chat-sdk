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
    allow(mock_client).to receive(:update_message)
    allow(mock_client).to receive(:delete_message)
    allow(mock_client).to receive(:create_reaction)
    allow(mock_client).to receive(:delete_reaction)
  end

  it_behaves_like "a chat_sdk platform adapter"

  describe "#initialize" do
    it "raises ConfigurationError without a webhook verifier" do
      expect { described_class.new(project_number: "") }
        .to raise_error(ChatSDK::ConfigurationError, /webhook verification requires/)
    end
  end

  describe "#name" do
    it "returns :gchat" do
      expect(subject.name).to eq(:gchat)
    end
  end

  describe "#verify_request!" do
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

  describe "#parse_pubsub_event" do
    def build_request(body)
      env = Rack::MockRequest.env_for(
        "/gchat/pubsub",
        :method => "POST",
        :input => body,
        "CONTENT_TYPE" => "application/json"
      )
      Rack::Request.new(env)
    end

    def pubsub_envelope(chat_event)
      {
        "message" => {
          "data" => Base64.strict_encode64(JSON.generate(chat_event)),
          "messageId" => "1234567890",
          "publishTime" => "2024-01-01T00:00:00Z"
        },
        "subscription" => "projects/my-project/subscriptions/chat-sub"
      }
    end

    context "with a valid Pub/Sub push containing a MESSAGE event" do
      it "decodes the base64 payload and parses into a Mention event" do
        chat_event = {
          "type" => "MESSAGE",
          "message" => {
            "name" => "spaces/SPACE1/messages/MSG_PS1",
            "sender" => {"name" => "users/789", "displayName" => "Charlie"},
            "text" => "@Bot check status",
            "argumentText" => "check status",
            "thread" => {"name" => "spaces/SPACE1/threads/THREAD_PS1"},
            "space" => {"name" => "spaces/SPACE1"},
            "annotations" => [
              {
                "type" => "USER_MENTION",
                "userMention" => {"type" => "MENTION", "user" => {"name" => "users/bot"}}
              }
            ]
          }
        }
        request = build_request(JSON.generate(pubsub_envelope(chat_event)))
        events = subject.parse_pubsub_event(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Mention)
        expect(event.message.text).to eq("@Bot check status")
        expect(event.message.author.id).to eq("789")
        expect(event.message.author.name).to eq("Charlie")
        expect(event.channel_id).to eq("SPACE1")
        expect(event.thread_id).to eq("THREAD_PS1")
      end
    end

    context "with a valid Pub/Sub push containing a non-mention MESSAGE" do
      it "decodes and parses into a SubscribedMessage event" do
        chat_event = {
          "type" => "MESSAGE",
          "message" => {
            "name" => "spaces/SPACE2/messages/MSG_PS2",
            "sender" => {"name" => "users/456", "displayName" => "Dana"},
            "text" => "hello everyone",
            "thread" => {"name" => "spaces/SPACE2/threads/THREAD_PS2"},
            "space" => {"name" => "spaces/SPACE2"}
          }
        }
        request = build_request(JSON.generate(pubsub_envelope(chat_event)))
        events = subject.parse_pubsub_event(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::SubscribedMessage)
        expect(event.message.text).to eq("hello everyone")
        expect(event.message.author.id).to eq("456")
        expect(event.channel_id).to eq("SPACE2")
      end
    end

    context "with a Pub/Sub push containing a CARD_CLICKED event" do
      it "decodes and parses into an Action event" do
        chat_event = {
          "type" => "CARD_CLICKED",
          "action" => {
            "actionMethodName" => "btn:confirm",
            "parameters" => [{"key" => "value", "value" => "confirmed"}]
          },
          "user" => {"name" => "users/101", "displayName" => "Eve"},
          "message" => {
            "name" => "spaces/SPACE3/messages/MSG_PS3",
            "space" => {"name" => "spaces/SPACE3"},
            "thread" => {"name" => "spaces/SPACE3/threads/THREAD_PS3"}
          },
          "space" => {"name" => "spaces/SPACE3"}
        }
        request = build_request(JSON.generate(pubsub_envelope(chat_event)))
        events = subject.parse_pubsub_event(request)

        expect(events.size).to eq(1)
        event = events.first
        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("btn:confirm")
        expect(event.value).to eq("confirmed")
        expect(event.user.id).to eq("101")
      end
    end

    context "when message.data is missing" do
      it "returns an empty array" do
        envelope = {"message" => {"messageId" => "123"}, "subscription" => "projects/p/subscriptions/s"}
        request = build_request(JSON.generate(envelope))
        expect(subject.parse_pubsub_event(request)).to be_empty
      end
    end

    context "when message.data contains invalid base64" do
      it "returns an empty array" do
        envelope = {"message" => {"data" => "!!not-base64!!"}, "subscription" => "projects/p/subscriptions/s"}
        request = build_request(JSON.generate(envelope))
        expect(subject.parse_pubsub_event(request)).to be_empty
      end
    end

    context "when message.data decodes to invalid JSON" do
      it "returns an empty array" do
        envelope = {"message" => {"data" => Base64.strict_encode64("not json")}, "subscription" => "projects/p/subscriptions/s"}
        request = build_request(JSON.generate(envelope))
        expect(subject.parse_pubsub_event(request)).to be_empty
      end
    end

    context "when the outer envelope is invalid JSON" do
      it "returns an empty array" do
        request = build_request("not valid json at all")
        expect(subject.parse_pubsub_event(request)).to be_empty
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

    it "accepts a full resource name from the same space" do
      allow(mock_client).to receive(:update_message).and_return(double("result"))

      subject.edit_message(
        channel_id: "SPACE1",
        message_id: "spaces/SPACE1/messages/MSG1",
        message: "Updated text"
      )

      expect(mock_client).to have_received(:update_message).with(
        message: hash_including(name: "spaces/SPACE1/messages/MSG1"),
        update_mask: an_instance_of(Google::Protobuf::FieldMask)
      )
    end

    it "rejects a message from another space" do
      expect {
        subject.edit_message(
          channel_id: "SPACE1",
          message_id: "spaces/SPACE2/messages/MSG1",
          message: "Updated text"
        )
      }.to raise_error(ChatSDK::Error, /Invalid Google Chat message ID/)

      expect(mock_client).not_to have_received(:update_message)
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

    it "rejects a message from another space" do
      expect {
        subject.delete_message(
          channel_id: "SPACE1",
          message_id: "spaces/SPACE2/messages/MSG1"
        )
      }.to raise_error(ChatSDK::Error, /Invalid Google Chat message ID/)

      expect(mock_client).not_to have_received(:delete_message)
    end

    it "rejects traversal and encoded slashes" do
      ["..", "MSG/../OTHER", "MSG%2FOTHER"].each do |message_id|
        expect {
          subject.delete_message(channel_id: "SPACE1", message_id: message_id)
        }.to raise_error(ChatSDK::Error, /Invalid Google Chat message ID/)
      end

      expect(mock_client).not_to have_received(:delete_message)
    end
  end

  describe "reaction message names" do
    it "validates message IDs before creating or deleting reactions" do
      expect {
        subject.add_reaction(
          channel_id: "SPACE1",
          message_id: "spaces/SPACE2/messages/MSG1",
          emoji: "👍"
        )
      }.to raise_error(ChatSDK::Error, /Invalid Google Chat message ID/)

      expect {
        subject.remove_reaction(
          channel_id: "SPACE1",
          message_id: "MSG/../OTHER",
          emoji: "👍"
        )
      }.to raise_error(ChatSDK::Error, /Invalid Google Chat message ID/)

      expect(mock_client).not_to have_received(:create_reaction)
      expect(mock_client).not_to have_received(:delete_reaction)
    end

    it "accepts a full resource name from the same space" do
      allow(mock_client).to receive(:create_reaction).and_return(double("result"))

      subject.add_reaction(
        channel_id: "SPACE1",
        message_id: "spaces/SPACE1/messages/MSG1",
        emoji: "👍"
      )

      expect(mock_client).to have_received(:create_reaction).with(
        parent: "spaces/SPACE1/messages/MSG1",
        reaction: {emoji: {unicode: "👍"}}
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

      it "renders header images, text styles, links, disabled buttons, and initial selections" do
        card = ChatSDK.card(title: "Card", image_url: "https://example.com/header.png") do
          text "Strong", style: :bold
          text "Subtle", style: :muted
          link url: "https://example.com/docs", label: "Docs"
          actions do
            button "Disabled", id: "disabled", disabled: true
            link_button "Primary", url: "https://example.com", style: :primary
            select id: "scope", label: "Scope", initial_option: "team" do
              option "Team", value: "team"
              option "Personal", value: "personal"
            end
            radio_select id: "mode", label: "Mode", initial_option: "fast" do
              option "Fast", value: "fast"
              option "Careful", value: "careful"
            end
          end
        end
        card_data = renderer.render(card)[:cards_v2][0][:card]
        expect(card_data[:header]).to include(
          title: "Card", imageUrl: "https://example.com/header.png", imageType: "SQUARE"
        )
        widgets = card_data[:sections].flat_map { |section| section[:widgets] }
        expect(widgets[0]).to eq(textParagraph: {text: "*Strong*"})
        expect(widgets[1]).to eq(textParagraph: {text: "Subtle"})
        expect(widgets[2]).to eq(textParagraph: {text: %(<a href="https://example.com/docs">Docs</a>)})
        buttons = widgets.find { |widget| widget[:buttonList] }[:buttonList][:buttons]
        expect(buttons[0][:disabled]).to be(true)
        expect(buttons[1][:color]).to include(blue: 0.87)
        selections = widgets.select { |widget| widget[:selectionInput] }.map { |widget| widget[:selectionInput] }
        expect(selections[0]).to include(label: "Scope", type: "DROPDOWN")
        expect(selections[0][:items].find { |item| item[:selected] }[:value]).to eq("team")
        expect(selections[1]).to include(label: "Mode", type: "RADIO_BUTTON")
        expect(selections[1][:items].find { |item| item[:selected] }[:value]).to eq("fast")
      end

      it "escapes HTML in link labels and URLs" do
        card = ChatSDK.card do
          link url: 'https://example.com/<path>"quoted"', label: 'Docs <"guide">'
        end

        widgets = renderer.render(card)[:cards_v2][0][:card][:sections][0][:widgets]
        expect(widgets[0]).to eq(
          textParagraph: {
            text: %(<a href="https://example.com/&lt;path&gt;&quot;quoted&quot;">Docs &lt;&quot;guide&quot;&gt;</a>)
          }
        )
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
