module ChatSDK
  module Testing
    module AdapterContract
      RSpec.shared_examples "a chat_sdk platform adapter" do
        it "responds to #name with a symbol" do
          expect(subject.name).to be_a(Symbol)
        end

        it "responds to #client" do
          expect(subject).to respond_to(:client)
        end

        it "responds to #verify_request!" do
          expect(subject).to respond_to(:verify_request!)
        end

        it "responds to #parse_events" do
          expect(subject).to respond_to(:parse_events)
        end

        it "responds to #post_message" do
          expect(subject).to respond_to(:post_message)
        end

        it "responds to #mention" do
          expect(subject).to respond_to(:mention)
        end

        it "responds to #render" do
          expect(subject).to respond_to(:render)
        end

        it "responds to #supports?" do
          expect(subject).to respond_to(:supports?)
        end

        it "raises NotSupportedError for undeclared capabilities" do
          undeclared = Adapter::Capabilities::KNOWN - subject.class.declared_capabilities
          undeclared.each do |cap|
            method_for_cap = capability_method(cap)
            next unless method_for_cap && subject.respond_to?(method_for_cap)
            expect { subject.send(method_for_cap, **capability_args(cap)) }.to raise_error(NotSupportedError)
          end
        end

        private

        def capability_method(cap)
          {
            edit_messages: :edit_message,
            delete_messages: :delete_message,
            ephemeral_messages: :post_ephemeral,
            file_uploads: :upload_file,
            reactions: :add_reaction,
            modals: :open_modal,
            typing_indicator: :start_typing,
            direct_messages: :open_dm,
            message_history: :fetch_messages
          }[cap]
        end

        def capability_args(cap)
          case cap
          when :edit_messages then { channel_id: "C1", message_id: "M1", message: PostableMessage.new(text: "t") }
          when :delete_messages then { channel_id: "C1", message_id: "M1" }
          when :ephemeral_messages then { channel_id: "C1", user_id: "U1", message: PostableMessage.new(text: "t") }
          when :file_uploads then { channel_id: "C1", io: StringIO.new(""), filename: "f.txt" }
          when :reactions then { channel_id: "C1", message_id: "M1", emoji: "thumbsup" }
          when :modals then { trigger_id: "T1", modal: Cards::Node.new(:modal) }
          when :typing_indicator then { channel_id: "C1" }
          when :direct_messages then { user_id: "U1" }
          when :message_history then { channel_id: "C1" }
          else {}
          end
        end
      end
    end
  end
end
