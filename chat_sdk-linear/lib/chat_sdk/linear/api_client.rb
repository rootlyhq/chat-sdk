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

      def update_comment(comment_id:, body:)
        query = <<~GQL
          mutation CommentUpdate($id: String!, $input: CommentUpdateInput!) {
            commentUpdate(id: $id, input: $input) {
              success
              comment { id body }
            }
          }
        GQL
        graphql(query, {id: comment_id, input: {body: body}})
      end

      def delete_comment(comment_id:)
        query = <<~GQL
          mutation CommentDelete($id: String!) {
            commentDelete(id: $id) { success }
          }
        GQL
        graphql(query, {id: comment_id})
      end

      def create_reaction(comment_id:, emoji:)
        query = <<~GQL
          mutation ReactionCreate($input: ReactionCreateInput!) {
            reactionCreate(input: $input) { success }
          }
        GQL
        graphql(query, {input: {commentId: comment_id, emoji: emoji}})
      end

      def delete_reaction(comment_id:, emoji:)
        query = <<~GQL
          mutation ReactionDelete($input: ReactionCreateInput!) {
            reactionDelete(input: $input) { success }
          }
        GQL
        graphql(query, {input: {commentId: comment_id, emoji: emoji}})
      end

      def fetch_comments(issue_id:, parent_id: nil)
        if parent_id
          query = <<~GQL
            query CommentThread($id: String!) {
              comment(id: $id) {
                id body user { id name }
                children { nodes { id body user { id name } } }
              }
            }
          GQL
          graphql(query, {id: parent_id})
        else
          query = <<~GQL
            query IssueComments($id: String!) {
              issue(id: $id) {
                comments { nodes { id body user { id name } } }
              }
            }
          GQL
          result = graphql(query, {id: issue_id})
          {"data" => {"comments" => result.dig("data", "issue", "comments") || {"nodes" => []}}}
        end
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
