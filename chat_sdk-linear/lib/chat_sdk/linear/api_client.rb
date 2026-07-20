# frozen_string_literal: true

module ChatSDK
  module Linear
    class ApiClient < ChatSDK::ApiClient::Base
      BASE_URL = "https://api.linear.app"

      def initialize(api_key)
        @api_key = api_key
      end

      def create_comment(issue_id:, body:, parent_id: nil)
        query = <<~GQL
          mutation CommentCreate($input: CommentCreateInput!) {
            commentCreate(input: $input) {
              success
              comment {
                id
                body
                user { id name }
              }
            }
          }
        GQL
        input = {issueId: issue_id, body: body}
        input[:parentId] = parent_id if parent_id
        graphql(query, {input: input})
      end

      def create_reaction(comment_id:, emoji:)
        query = <<~GQL
          mutation($input: ReactionCreateInput!) {
            reactionCreate(input: $input) {
              success
            }
          }
        GQL
        graphql(query, {input: {commentId: comment_id, emoji: emoji}})
      end

      def delete_reaction(comment_id:, emoji:)
        query = <<~GQL
          mutation($input: ReactionCreateInput!) {
            reactionDelete(input: $input) {
              success
            }
          }
        GQL
        graphql(query, {input: {commentId: comment_id, emoji: emoji}})
      end

      private

      def base_url
        BASE_URL
      end

      def adapter_name
        :linear
      end

      def configure_auth(faraday)
        faraday.headers["Authorization"] = @api_key.to_s
      end

      def extract_error_message(response)
        body = response.body
        return response.status.to_s unless body.is_a?(Hash)

        body.dig("errors", 0, "message") || body.dig("error") || response.status.to_s
      end

      def extract_success_body(response)
        response.body
      end

      def graphql(query, variables = {})
        request(:post, "/graphql", {query: query, variables: variables})
      end
    end
  end
end
