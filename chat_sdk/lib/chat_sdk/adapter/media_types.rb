# frozen_string_literal: true

module ChatSDK
  module Adapter
    module MediaTypes
      CONTENT_TYPES = {
        ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
        ".gif" => "image/gif", ".webp" => "image/webp",
        ".mp4" => "video/mp4", ".3gp" => "video/3gpp",
        ".mp3" => "audio/mpeg", ".ogg" => "audio/ogg", ".amr" => "audio/amr",
        ".pdf" => "application/pdf", ".doc" => "application/msword",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls" => "application/vnd.ms-excel",
        ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      }.freeze

      private

      def detect_content_type(filename)
        CONTENT_TYPES.fetch(File.extname(filename).downcase, "application/octet-stream")
      end

      def media_type_for(content_type)
        case content_type
        when %r{^image/} then "image"
        when %r{^video/} then "video"
        when %r{^audio/} then "audio"
        else "document"
        end
      end
    end
  end
end
