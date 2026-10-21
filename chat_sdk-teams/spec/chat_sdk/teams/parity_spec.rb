# frozen_string_literal: true

require_relative "../../spec_helper"
require "base64"
require "rack"

RSpec.describe "Teams parity behavior" do
  let(:app_id) { "test-app-id" }
  let(:adapter) { ChatSDK::Teams::Adapter.new(app_id: app_id, app_password: "secret") }

  def graph_adapter
    ChatSDK::Teams::Adapter.new(
      app_id: app_id,
      app_password: "secret",
      graph_client_id: "graph-client",
      graph_client_secret: "graph-secret",
      graph_tenant_id: "tenant"
    )
  end

  def stub_graph_token
    stub_request(:post, "https://login.microsoftonline.com/tenant/oauth2/v2.0/token")
      .to_return(
        status: 200,
        body: JSON.generate("access_token" => "graph-token", "expires_in" => 3600),
        headers: {"Content-Type" => "application/json"}
      )
  end

  describe "activity parsing" do
    def parse(activity)
      ChatSDK::Teams::ActivityParser.parse(activity, bot_app_id: app_id)
    end

    it "filters prefixed and bare bot ids and matching recipient ids" do
      [app_id, "28:#{app_id}"].each do |sender_id|
        expect(parse(
          "type" => "message",
          "from" => {"id" => sender_id},
          "conversation" => {"id" => "conversation"}
        )).to be_empty
      end

      expect(parse(
        "type" => "message",
        "from" => {"id" => "bot-sender"},
        "recipient" => {"id" => "bot-sender"},
        "conversation" => {"id" => "conversation"}
      )).to be_empty
    end

    it "marks other bot authors without marking them as this bot" do
      event = parse(
        "type" => "message",
        "from" => {"id" => "28:another-bot", "name" => "Other bot"},
        "conversation" => {"id" => "conversation"}
      ).first

      expect(event.message.author.bot?).to be(true)
      expect(event.message.author.me?).to be(false)
    end

    it "parses install and uninstall lifecycle actions" do
      base = {
        "type" => "installationUpdate",
        "recipient" => {"id" => "28:#{app_id}"},
        "from" => {"id" => "installer-1", "name" => "Installer"},
        "conversation" => {"id" => "conversation-1", "tenantId" => "tenant-1"},
        "channelData" => {"team" => {"id" => "team-1"}}
      }

      installed = parse(base.merge("action" => "add-upgrade")).first
      uninstalled = parse(base.merge("action" => "remove-upgrade")).first

      expect(installed).to be_a(ChatSDK::Events::Installed)
      expect(installed.installation_id).to eq("team-1")
      expect(installed.team_id).to eq("team-1")
      expect(installed.tenant_id).to eq("tenant-1")
      expect(installed.conversation_id).to eq("conversation-1")
      expect(installed.user.id).to eq("installer-1")
      expect(uninstalled).to be_a(ChatSDK::Events::Uninstalled)
      expect(uninstalled.action).to eq("remove-upgrade")
    end

    it "includes the user in personal installation ids" do
      event = parse(
        "type" => "installationUpdate",
        "action" => "add",
        "recipient" => {"id" => app_id},
        "from" => {"id" => "user-1", "aadObjectId" => "aad-user-1"},
        "conversation" => {"id" => "conversation-1", "tenantId" => "tenant-1"}
      ).first

      expect(event.installation_id).to eq("tenant-1:aad-user-1")
    end

    it "parses submitted card input values from invoke and message activities" do
      ["invoke", "message"].each do |type|
        event = parse(
          "type" => type,
          "name" => "adaptiveCard/action",
          "from" => {"id" => "user-1", "name" => "Alice"},
          "conversation" => {"id" => "conversation-1"},
          "value" => {
            "data" => {
              "actionId" => "submit",
              "value" => "button-value",
              "msteams" => {"width" => "full"},
              "firstName" => "Alice"
            }
          }
        ).first

        expect(event).to be_a(ChatSDK::Events::Action)
        expect(event.action_id).to eq("submit")
        expect(event.values).to eq("firstName" => "Alice")
      end
    end

    it "uses the Adaptive Card action identifier while preserving submitted inputs" do
      [
        [{"actionId" => "action-id"}, "action-id"],
        [{"action" => "action-name"}, "action-name"],
        [{}, "action-verb"]
      ].each do |action_data, expected_action_id|
        event = parse(
          "type" => "invoke",
          "name" => "adaptiveCard/action",
          "from" => {"id" => "user-1"},
          "conversation" => {"id" => "conversation-1"},
          "value" => {
            "action" => {"verb" => "action-verb", "data" => action_data},
            "data" => {"firstName" => "Ada"}
          }
        ).first

        expect(event.action_id).to eq(expected_action_id)
        expect(event.values).to eq("firstName" => "Ada")
      end
    end
  end

  describe "invoke acknowledgement" do
    it "returns the adapter response through the webhook endpoint" do
      chat = ChatSDK::Chat.new(user_name: "bot", adapters: {teams: adapter}, state: ChatSDK::State::Memory.new)
      endpoint = ChatSDK::Webhook::Endpoint.new(chat: chat, adapter: adapter, adapter_name: :teams)
      allow(adapter).to receive(:verify_request!).and_return(true)
      request = Rack::MockRequest.env_for(
        "/webhooks/teams",
        method: "POST",
        input: JSON.generate(
          "type" => "invoke",
          "name" => "adaptiveCard/action",
          "from" => {"id" => "user-1"},
          "conversation" => {"id" => "conversation-1"},
          "value" => {"data" => {"actionId" => "submit", "name" => "Ada"}}
        ),
        content_type: "application/json"
      )

      status, headers, body = endpoint.call(request)

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(JSON.parse(body.first)["value"]).to eq("OK")
    end

    it "returns the Bot Framework message response" do
      event = ChatSDK::Events::Action.new(
        action_id: "submit",
        thread_id: "conversation-1",
        channel_id: "conversation-1",
        platform: :teams,
        adapter_name: :teams,
        raw: {"type" => "invoke"}
      )

      status, headers, body = adapter.webhook_response([event])

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(JSON.parse(body.first)).to eq(
        "statusCode" => 200,
        "type" => "application/vnd.microsoft.activity.message",
        "value" => "OK"
      )
    end
  end

  describe "service URL persistence" do
    it "persists conversation URLs and restores them from shared state" do
      state = ChatSDK::State::Memory.new
      chat = ChatSDK::Chat.new(user_name: "bot", adapters: {teams: adapter}, state: state)
      service_url = "https://smba.trafficmanager.net/emea/"

      adapter.register_service_url("conversation-1", service_url)
      restored = ChatSDK::Teams::Adapter.new(app_id: app_id, app_password: "secret")
      restored.set_state(state)

      expect(state.get("chat_sdk:teams:service_url:conversation-1")).to eq(service_url)
      expect(restored.send(:service_url_for, "conversation-1")).to eq(service_url)
      expect(restored.send(:service_url_for, "unknown")).to eq(ChatSDK::Teams::Adapter::DEFAULT_SERVICE_URL)
      expect(chat).to be_a(ChatSDK::Chat)
    end

    it "uses the configured fallback service URL" do
      configured = ChatSDK::Teams::Adapter.new(
        app_id: app_id,
        app_password: "secret",
        service_url: "https://custom.example/teams/"
      )

      expect(configured.send(:service_url_for, "unknown")).to eq("https://custom.example/teams/")
    end
  end

  describe "channel thread receipts" do
    it "encodes a root post into a replyable thread id" do
      allow(adapter.client).to receive(:send_activity).and_return({"id" => "activity-1"})
      channel_id = "19:channel@thread.tacv2"

      posted = adapter.post_message(channel_id: channel_id, message: "root")
      adapter.post_message(channel_id: channel_id, thread_id: posted.thread_id, message: "reply")

      expect(posted.thread_id).to eq("#{channel_id};messageid=activity-1")
      expect(adapter.client).to have_received(:send_activity).with(
        hash_including(activity: hash_including("replyToId" => "activity-1"))
      )
    end
  end

  describe "Adaptive Cards" do
    it "renders text inputs and native tables with the Teams options" do
      card = ChatSDK.card do
        text_input(id: "name", label: "Name", placeholder: "Your name", multiline: true, optional: true, value: "Ada")
        table(
          headers: ["Name", "Role"],
          rows: [["Ada"]],
          widths: [2, 0],
          align: [:left, :right],
          grid_lines: false,
          grid_style: :accent,
          vertical_align: :center
        )
      end

      body = adapter.render(card)["body"]

      expect(body.first).to eq(
        "type" => "Input.Text",
        "id" => "name",
        "label" => "Name",
        "placeholder" => "Your name",
        "isMultiline" => true,
        "isRequired" => false,
        "value" => "Ada"
      )
      table = body.last
      expect(table["type"]).to eq("Table")
      expect(table["firstRowAsHeaders"]).to be(true)
      expect(table["showGridLines"]).to be(false)
      expect(table["gridStyle"]).to eq(:accent)
      expect(table["verticalCellContentAlignment"]).to eq("Center")
      expect(table["columns"]).to eq([
        {"width" => 2, "horizontalCellContentAlignment" => "Left"},
        {"width" => 1, "horizontalCellContentAlignment" => "Right"}
      ])
      expect(table["rows"].last["cells"].last["items"].first["text"]).to eq("")
    end

    it "rejects reserved text input ids" do
      %w[actionId value msteams].each do |id|
        expect { ChatSDK.card { text_input(id: id, label: "Reserved") } }
          .to raise_error(ArgumentError, /reserved/)
      end
    end
  end

  describe "AI-generated label" do
    it "adds the schema entity to generated messages" do
      allow(adapter.client).to receive(:send_activity).and_return({"id" => "activity-1"})

      adapter.post_message(
        channel_id: "conversation-1",
        message: ChatSDK::PostableMessage.new(text: "Generated", ai_generated: true)
      )

      expect(adapter.client).to have_received(:send_activity).with(
        hash_including(activity: hash_including(
          "entities" => [{
            "type" => "https://schema.org/Message",
            "@type" => "Message",
            "@context" => "https://schema.org",
            "additionalType" => ["AIGeneratedContent"]
          }]
        ))
      )
    end
  end

  describe "Graph pagination and attachments" do
    let(:messages_url) { "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$top=50&$orderby=createdDateTime%20desc" }
    let(:attachment_url) { "https://sharepoint.example/files/report.pdf" }
    let(:share_id) { "u!#{Base64.urlsafe_encode64(attachment_url, padding: false)}" }
    let(:share_url) { "https://graph.microsoft.com/v1.0/shares/#{share_id}/driveItem" }

    it "uses a Graph nextLink cursor and rejects other origins" do
      client = graph_adapter
      cursor = "https://graph.microsoft.com/v1.0/chats/chat-1/messages?$skiptoken=next"
      stub_graph_token
      stub_request(:get, cursor)
        .to_return(status: 200, body: JSON.generate("value" => []), headers: {"Content-Type" => "application/json"})

      expect(client.fetch_messages(channel_id: "chat-1", cursor: cursor)).to eq([[], nil])
      expect(a_request(:get, cursor)).to have_been_made.once
      expect { client.fetch_messages(channel_id: "chat-1", cursor: "https://example.com/evil") }
        .to raise_error(ArgumentError, /https:\/\/graph\.microsoft\.com/)
    end

    it "accepts raw and percent-encoded cursor paths for the same chat id" do
      client = graph_adapter
      chat_id = "19:x@thread.v2"
      raw_cursor = "https://graph.microsoft.com/v1.0/chats/19:x@thread.v2/messages?$skiptoken=raw"
      encoded_cursor = "https://graph.microsoft.com/v1.0/chats/19%3Ax%40thread.v2/messages?$skiptoken=encoded"
      stub_graph_token
      [raw_cursor, encoded_cursor].each do |cursor|
        stub_request(:get, cursor)
          .to_return(status: 200, body: JSON.generate("value" => []), headers: {"Content-Type" => "application/json"})
      end

      expect(client.fetch_messages(channel_id: chat_id, cursor: raw_cursor)).to eq([[], nil])
      expect(client.fetch_messages(channel_id: chat_id, cursor: encoded_cursor)).to eq([[], nil])
      expect {
        client.fetch_messages(
          channel_id: chat_id,
          cursor: "https://graph.microsoft.com/v1.0/chats/19:y@thread.v2/messages?$skiptoken=other"
        )
      }.to raise_error(ArgumentError, /requested chat path/)
      expect {
        client.fetch_messages(
          channel_id: chat_id,
          cursor: "https://graph.microsoft.com/v1.0/users/user-1/messages?$skiptoken=next"
        )
      }.to raise_error(ArgumentError, /requested chat path/)
    end

    it "skips reference attachments that fail to resolve" do
      client = graph_adapter
      graph_client = client.instance_variable_get(:@graph_client)
      errors = {
        "https://files.example/platform" => ChatSDK::PlatformError.new("not found"),
        "https://files.example/argument" => ArgumentError.new("invalid attachment"),
        "https://files.example/faraday" => Faraday::ConnectionFailed.new("connection failed")
      }
      attachments = errors.keys.map do |url|
        {"contentType" => "reference", "contentUrl" => url, "name" => "failed"}
      end
      attachments << {
        "contentType" => "reference",
        "contentUrl" => "https://files.example/good",
        "name" => "good.pdf"
      }
      allow(graph_client).to receive(:fetch_messages).and_return(
        "value" => [{
          "id" => "message-1",
          "body" => {"content" => "report"},
          "from" => {"user" => {"id" => "user-1", "displayName" => "Alice"}},
          "attachments" => attachments
        }]
      )
      allow(graph_client).to receive(:resolve_reference_attachment) do |content_url:|
        raise errors.fetch(content_url) if errors.key?(content_url)

        {"url" => "https://download.example/good.pdf", "filename" => "good.pdf"}
      end

      messages, = client.fetch_messages(channel_id: "chat-1")

      expect(messages.first.attachments.size).to eq(1)
    end

    it "maps Graph reference files and downloads them without forwarding Graph credentials" do
      client = graph_adapter
      download_url = "https://download.example/report.pdf?token=short-lived"
      stub_graph_token
      stub_request(:get, messages_url)
        .to_return(
          status: 200,
          body: JSON.generate("value" => [{
            "id" => "message-1",
            "body" => {"content" => "report"},
            "from" => {"user" => {"id" => "user-1", "displayName" => "Alice"}},
            "attachments" => [{
              "contentType" => "reference",
              "contentUrl" => attachment_url,
              "name" => "report.pdf"
            }]
          }]),
          headers: {"Content-Type" => "application/json"}
        )
      stub_request(:get, share_url)
        .to_return(
          status: 200,
          body: JSON.generate(
            "name" => "report.pdf",
            "file" => {"mimeType" => "application/pdf"},
            "@microsoft.graph.downloadUrl" => download_url
          ),
          headers: {"Content-Type" => "application/json"}
        )

      messages, = client.fetch_messages(channel_id: "chat-1")

      expect(messages.first.attachments).to eq([{
        "url" => download_url,
        "mime_type" => "application/pdf",
        "filename" => "report.pdf"
      }])

      stub_request(:get, download_url)
        .with { |request| request.headers["Authorization"].nil? }
        .to_return(status: 200, body: "file bytes")
      response = client.instance_variable_get(:@graph_client)
        .download_reference_attachment(content_url: attachment_url)

      expect(response.body).to eq("file bytes")
    end
  end
end
