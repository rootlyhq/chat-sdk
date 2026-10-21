# frozen_string_literal: true

module ChatSDK
  module Events
    class Installed < Base
      attr_reader :installation_id, :team_id, :tenant_id, :conversation_id, :action, :user

      def initialize(conversation_id:, action:, installation_id: nil, team_id: nil, tenant_id: nil, user: nil, **kwargs)
        super(type: :installed, **kwargs)
        @installation_id = installation_id
        @team_id = team_id
        @tenant_id = tenant_id
        @conversation_id = conversation_id
        @action = action
        @user = user
      end
    end
  end
end
