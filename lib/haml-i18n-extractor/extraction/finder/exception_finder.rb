module Haml
  module I18n
    class Extractor
      class ExceptionFinder

        LINK_TO_REGEX_DOUBLE_Q = /link_to\s*\(?\s*["](.*?)["]\s*,\s*(.*)\)?/
        LINK_TO_REGEX_SINGLE_Q = /link_to\s*\(?\s*['](.*?)[']\s*,\s*(.*)\)?/
        LINK_TO_BLOCK_FORM_SINGLE_Q = /link_to\s*\(?['](.*?)[']\)?.*\sdo\s*$/
        LINK_TO_BLOCK_FORM_DOUBLE_Q = /link_to\s*\(?["](.*?)["]\)?.*\sdo\s*$/
        LINK_TO_NO_QUOTES = /link_to\s*\(?([^'"]*?)\)?.*/

        FORM_SUBMIT_BUTTON_SINGLE_Q = /[a-z]\.submit\s?['](.*?)['].*$/
        FORM_SUBMIT_BUTTON_DOUBLE_Q = /[a-z]\.submit\s?["](.*?)["].*$/
        # get quoted strings that are not comments
        # based on https://davidwells.io/snippets/regex-match-outer-double-quotes. This
        # has a capture case for both single quotes and double quotes. It will properly ignore
        # escaped quotes inside the quoted string such as "this \"escaped\" quote". Do note though that
        # this regex will leave the quotes on the string, unlike the other EXCEPTION_MATCHES, so they need to
        # be removed from the results.
        QUOTED_STRINGS = /('[^\\']*(\\'[^\\']*)*'|"[^\\"]*(\\"[^\\"]*)*")/
        ARRAY_OF_STRINGS = /^[\s]?\[(.*)\]/

        RENDER_PARTIAL_MATCH = /render[\s*](layout:[\s*])?['"](.*?)['"].*$/
        COMPONENT_MATCH = /(knockout_component|react_component)\s*\(?['"](.*?)['"]\)?.*$/
        SIMPLE_FORM_FOR = /simple_nested_form_for(.*)/

        # this class simply returns text except for anything that matches these regexes.
        # returns first match.
        EXCEPTION_MATCHES = [ LINK_TO_BLOCK_FORM_DOUBLE_Q, LINK_TO_BLOCK_FORM_SINGLE_Q,
                              LINK_TO_REGEX_DOUBLE_Q, LINK_TO_REGEX_SINGLE_Q , LINK_TO_NO_QUOTES,
                              FORM_SUBMIT_BUTTON_SINGLE_Q, FORM_SUBMIT_BUTTON_DOUBLE_Q, ARRAY_OF_STRINGS, QUOTED_STRINGS]


        def initialize(text)
          @text = text
        end

        def self.could_match?(txt)
          # want to match:
          # = 'foo'
          # = "foo"
          # = link_to 'bla'
          #
          # but not match:
          # = ruby_var = 2
          scanner = StringScanner.new(txt)
          scanner.scan(/\s+/)
          scanner.scan(/['"]/) || EXCEPTION_MATCHES.any? {|regex| txt.match(regex) }
        end

        def find
          # Note that it's possible for plain strings which do not match any of the below criteria
          # to get all the way to the end with original `@text` value.
          ret = @text

          if @text.match(ARRAY_OF_STRINGS)
            ret = $1.gsub(/['"]/,'').split(', ')
          elsif @text.match(SIMPLE_FORM_FOR)
            ret = nil
          elsif @text.match(QUOTED_STRINGS)
            ret = @text.scan(QUOTED_STRINGS).flatten
            ret = remove_nils_and_quotes_from_quoted_strings(ret)
            ret = filter_out_already_translated(ret, @text)
            ret = filter_out_invalid_quoted_strings(ret)
            ret = filter_out_partial_renders(ret, @text)
            ret = filter_out_component_methods(ret, @text)
            ret = filter_out_data_bind_values(ret, @text)
            ret = filter_out_programmatic_strings(ret, @text)
            ret = ret.length > 1 ? ret : ret[0]
          else
            EXCEPTION_MATCHES.each do |regex|
              if @text.match(regex)
                ret = $1
                break # return whatever it finds on first try, order of above regexes matters
              end
            end
          end

          ret = filter_out_non_words(ret)

          ret
        end

        def remove_nils_and_quotes_from_quoted_strings(arr)
          arr.select { |str| !str.nil? }.map { |str| str[1..-2] }
        end

        # If the regex-found string is wrapped by a `t()` call already, then we should
        # not translate it - it already is.
        def filter_out_already_translated(arr, full_text)
          arr.select do |str|
            # look for `t(str`. No closing `)` in case of variable interpolation happening.
            !full_text.include?("t(#{str}") && !full_text.include?("t('#{str}'")  && !full_text.include?("t(\"#{str}\"")
          end
        end

        # Remove any matches that are just quote marks
        # e.g. "Blah" would get kept but "'" and "t(blah)" would be discarded
        def filter_out_invalid_quoted_strings(arr)
          arr.select { |str| str != "'" && str != '"' && !str.start_with?(',') }
        end

        # Remove any matches that are not words for translating, but are instead UI elements
        def filter_out_non_words(arr)
          return nil if arr.nil?

          arr = arr.is_a?(Array) ? arr : [arr]
          arr.compact.select do |str|
            str != "•" &&
              str != 'x' &&
              str != '×' &&
              str != '+' &&
              str != '|' &&
              str != '‧' &&
              str != '*' &&
              str != '-' &&
              str != '(' &&
              str != ')' &&
              str != '{' &&
              str != '}' &&
              str != '[' &&
              str != ']' &&
              str != '&times;' &&
              str != '&nbsp;x'
          end
        end

        def filter_out_partial_renders(arr, full_text)
          # match a render call with optional layout: parameter allowed to figure out
          # the string equaling the partial being rendered in the full_text
          full_text.match(RENDER_PARTIAL_MATCH)
          partial_name = $2

          return arr if partial_name.nil?

          arr.select do |str|
            str != partial_name
          end
        end

        def filter_out_component_methods(arr, full_text)
          # match a render call with optional layout: parameter allowed to figure out
          # the string equaling the partial being rendered in the full_text
          full_text.match(COMPONENT_MATCH)
          component_name = $2

          return arr if component_name.nil?

          arr.select do |str|
            str != component_name
          end
        end

        def filter_out_data_bind_values(arr, full_text)
          return nil if arr.nil?

          arr = arr.is_a?(Array) ? arr : [arr]

          # match a data-bind key/value assignment figure out
          # the string equaling the partial being rendered in the full_text
          # TODO: This handles either `'` or `"` wrapped values, but does not handle
          # escaped quotes yet
          data_bind_regex = %r{
            ['"]data-bind['"]\s*:\s*'(.*?)'| # Ruby HAML format
            ['"]data-bind['"]\s*:\s*"(.*?)"| # Ruby HAML format
            ['"]data-bind['"]\s*=>\s*'(.*?)'| # Old Ruby HAML format
            ['"]data-bind['"]\s*=>\s*"(.*?)"| # Old Ruby HAML format
            data-bind\s*=\s*'(.*?)'| # HTML format
            data-bind\s*=\s*"(.*?)"| # HTML format
            bind\s*:\s*'(.*?)'| # HAML format where the data-bind is nested
            bind\s*:\s*"(.*?)" # HAML format where the data-bind is nested
          }x
          matches = full_text.match(data_bind_regex)
          return arr unless matches&.captures

          # There are numerous possible captures depending on format, find the first one that matched
          data_bind_value = matches.captures.compact.first
          return arr if data_bind_value.nil?

          puts "[data-bind] Found data-bind value, skipping '#{data_bind_value}'" if Haml::I18n::Extractor.debug?

          arr.select do |str|
            str != data_bind_value
          end
        end

        # For quoted strings only - filter out strings that are programmatic, rather than
        # human-read sentences or words.
        def filter_out_programmatic_strings(arr, full_text)
          return nil if arr.nil?

          arr = arr.is_a?(Array) ? arr : [arr]
          arr.compact.select do |str|
              # Skip any strings which are time / date formatting strings such as %Y or %B.
              # Match '%' followed by 1 alpha-numeric character
              !str.match(/\%\w/) &&
              # This is a js function call - should be ignored
              !str.include?('()') &&
              # If a string is entirely downcase/upcase, it probably is not a string that should be
              # translated and is instead a programmatic type string. Some downcased strings are valid parts
              # of sentences, so only select if no whitespace
              str.downcase.gsub(' ', '') != str &&
              str.upcase != str &&
              # Try and exclude data-bind values as well as possible
              !str.include?("$data") &&
              !str.include?("$parent") &&
              # looking for programmatic strings like 'class-name' or 'partial/render'. we do not rule out
              # strings with 'under_score' since those are common in interpolation in ruby code variable refs.
              !str.match(/\b[a-z]+-[a-z]+\b/) &&
              !str.match(/\b[a-z]+\/[a-z]+\b/) &&
              # these will match knockout.js bindings FIXME: too broad, is this needed
              # anymore with filter_out_data_bind_values?
              # !str.match(/\b[a-z]:\s?/) &&
              # exclude any time / date formats
              !str.include?("yy") &&
              !str.include?("-mm-") &&
              !str.include?("-dd-") &&
              !str.include?("h:mm")
          end
        end
      end
    end
  end
end
