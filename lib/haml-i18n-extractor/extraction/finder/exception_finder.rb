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
        # get quoted strings that are not preceded by t( - not translated
        # based on https://www.metaltoad.com/blog/regex-quoted-string-escapable-quotes
        QUOTED_STRINGS = /((?<![\\]|t\(|class:[\s*])['"])((?:.(?!(?<![\\])\1))*.?)\1/
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
          elsif @text.match(SIMPLE_FORM_FOR)
            ret = nil
          elsif @text.match(QUOTED_STRINGS) || @text.match(RENDER_PARTIAL_MATCH) || @text.match(COMPONENT_MATCH)
            ret = @text.scan(QUOTED_STRINGS).flatten
            ret = filter_out_invalid_quoted_strings(ret)
            ret = filter_out_non_words(ret)
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
          ret
        end

        # Remove any matches that are just quote marks
        # e.g. "Blah" would get kept but "'" and "t(blah)" would be discarded
        def filter_out_invalid_quoted_strings(arr)
          arr.select { |str| str != "'" && str != '"' && !str.start_with?(',') }
        end

        # Remove any matches that are not words for translating, but are instead UI elements
        def filter_out_non_words(arr)
          arr.select do |str|
            str != "•" &&
              str != 'x' &&
              str != '×' &&
              str != '*' &&
              str != '-' &&
              str != "&times;"
          end
        end

        def filter_out_partial_renders(arr, full_text)
          return arr unless full_text.include?('= render')

          # match a render call with optional layout: parameter allowed to figure out
          # the string equaling the partial being rendered in the full_text
          full_text.match(RENDER_PARTIAL_MATCH)
          partial_name = $2

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

          return arr unless component_name.present?

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
