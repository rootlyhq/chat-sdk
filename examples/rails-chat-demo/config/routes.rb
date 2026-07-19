# frozen_string_literal: true

Rails.application.routes.draw do
  root "chat#index"

  # Optional: Slack webhook (uncomment after adding chat_sdk-slack)
  # mount ChatBot.instance.webhooks[:slack] => "/webhooks/slack"
end
