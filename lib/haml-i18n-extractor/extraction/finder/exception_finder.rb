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
        # based on https://www.metaltoad.com/blog/regex-quoted-string-escapable-quotes
        QUOTED_STRINGS = /((?<![\\])['"])((?:.(?!(?<![\\])\1))*.?)\1/
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
          ret = @text
          if @text.match(ARRAY_OF_STRINGS)
            ret = $1.gsub(/['"]/,'').split(', ')
          elsif @text.match(SIMPLE_FORM_FOR) || @text == 'data-bind'
            ret = nil
          elsif @text.match(QUOTED_STRINGS) || @text.match(RENDER_PARTIAL_MATCH) || @text.match(COMPONENT_MATCH)
            ret = @text.scan(QUOTED_STRINGS).flatten
            ret = filter_out_already_translated(ret, @text)
            ret = filter_out_invalid_quoted_strings(ret)
            ret = filter_out_partial_renders(ret, @text)
            ret = filter_out_component_methods(ret, @text)
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
              # looking for programmatic strings like 'class-name' or 'id_name' or 'partial/render'
              !str.match(/[a-z]*-[a-z]*/) &&
              !str.match(/[a-z]*_[a-z]*/) &&
              !str.match(/[a-z]*\/[a-z]*/) &&
              # these will match knockout.js bindings
              !str.match(/[a-z]: /) &&
              # exclude any time / date formats
              !str.include?("yy") &&
              !str.include?("-mm-") &&
              !str.include?("-dd-") &&
              !str.include?("h:mm")
          end
        end

        def filter_out_partial_renders(arr, full_text)
          # match a render call with optional layout: parameter allowed to figure out
          # the string equaling the partial being rendered in the full_text
          full_text.match(RENDER_PARTIAL_MATCH)
          partial_name = $2

          return arr unless partial_name != nil

          arr.select do |str|
            str != partial_name &&
              # Anything with these characters in them we assume is not a string
              # we want to translate, but rather a programmatic string
              !str.include?('-') &&
              !str.include?('_') &&
              !str.include?('/')
          end
        end

        def filter_out_component_methods(arr, full_text)
          # match a render call with optional layout: parameter allowed to figure out
          # the string equaling the partial being rendered in the full_text
          full_text.match(COMPONENT_MATCH)
          component_name = $2

          return arr unless component_name != nil

          arr.select do |str|
            str != component_name &&
              # Anything with these characters in them we assume is not a string
              # we want to translate, but rather a programmatic string
              !str.include?('-') &&
              !str.include?('_') &&
              !str.include?('/')
          end
        end
      end
    end
  end
end
