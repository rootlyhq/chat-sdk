# frozen_string_literal: true

module ChatSDK
  module Format
    module Mentions
      class << self
        def mask_code_spans(text)
          characters = text.to_s.chars
          masked = characters.dup
          opening = nil
          opening_length = nil
          fence = false
          index = 0

          while index < characters.length
            if characters[index] == "`"
              finish = index + 1
              finish += 1 while finish < characters.length && characters[finish] == "`"
              length = finish - index

              if opening
                closes = fence ? length >= 3 : length == opening_length
                if closes
                  blank_span(masked, opening, finish)
                  opening = nil
                  opening_length = nil
                  fence = false
                else
                  blank_span(masked, index, finish)
                end
              else
                opening = index
                opening_length = length
                fence = length >= 3
                blank_span(masked, index, finish)
              end

              index = finish
            else
              if opening
                masked[index] = " " unless characters[index] == "\n" || characters[index] == "\r"
              end
              index += 1
            end
          end

          masked.join
        end

        private

        def blank_span(characters, first, finish)
          (first...finish).each do |index|
            characters[index] = " " unless characters[index] == "\n" || characters[index] == "\r"
          end
        end
      end
    end
  end
end
