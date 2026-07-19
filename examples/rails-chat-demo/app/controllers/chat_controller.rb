# frozen_string_literal: true

class ChatController < ApplicationController
  def index
    @channel_id = params[:channel_id] || "default"
  end
end
