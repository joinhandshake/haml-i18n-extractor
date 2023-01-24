require 'haml'
require 'haml/parser'

module Haml
  module I18n
    class Extractor
      class TextFinder

        include Helpers::StringHelpers

        # if any of the private handler methods return nil the extractor just outputs orig_line and keeps on going.
        # if there's an empty string that should do the trick to ( ExceptionFinder can return no match that way )
        def initialize(orig_line, line_metadata)
          @orig_line = orig_line
          @metadata = line_metadata
        end

        def process_by_regex
          # [ line_type, text_found ]
          # output_debug if Haml::I18n::Extractor.debug?
          result = @metadata && send("#{@metadata[:type]}", @metadata)
          result = FinderResult.new(nil, nil) if result.nil?
          result
        end

        class FinderResult
          attr_accessor :type, :match, :options

          def initialize(type, match, options = {})
            @type = type
            @match = match
            @options = options
          end
        end

        private

        def extract_attribute(line, attribute_name)
          value = line[:value][:attributes][attribute_name.to_s]

          # HAML parser also has a concept of dynamic_attributes, fall back
          # to that if not found in :attributes. These are stored on the `old` or `new`
          # attributes on the dynamic attributes struct in String format. We are doing a ruby eval so
          # rescue an error in case the attribute is not found
          if !value && line[:value][:dynamic_attributes] && line[:value][:dynamic_attributes].old
            begin
              value = eval(line[:value][:dynamic_attributes].old)[attribute_name]
            rescue
            end
          end

          if !value && line[:value][:dynamic_attributes] && line[:value][:dynamic_attributes].new
            begin
              value = eval(line[:value][:dynamic_attributes].new)[attribute_name]
            rescue
            end
          end

          if value
            "\"#{value}\""
          else
            (line[:value][:attributes_hashes] || []).map { |hash|
              $1 if hash =~ /(?:\b#{attribute_name}\s*:|:#{attribute_name}\s*=>)\s*([^,]+)/
            }.compact.first
          end
        end

        def string_value?(value)
          value && (value.start_with?(?') || value.start_with?(?"))
        end

        def output_debug
          puts @metadata && @metadata[:type]
          puts @metadata.inspect
          puts @orig_line
        end

        def plain(line)
          txt = line[:value][:text]

          return nil if html_comment?(txt)

          # Skip single character strings which are often UI elements rather than
          # strings to be translated. Such as '|' or '+' or '*'.
          return nil if txt.length == 1

          FinderResult.new(:plain, txt)
        end

        def tag(line)
          tag_finder_results = []

          if string_value?(value = extract_attribute(line, :title))
            tag_finder_results << FinderResult.new(:tag, value[1...-1], :place => :attribute, :attribute_name => :title)
          end

          if string_value?(value = extract_attribute(line, :alt))
            tag_finder_results << FinderResult.new(:tag, value[1...-1], :place => :attribute, :attribute_name => :alt)
          end

          if string_value?(value = extract_attribute(line, :placeholder))
            tag_finder_results << FinderResult.new(:tag, value[1...-1], :place => :attribute, :attribute_name => :placeholder)
          end

          if string_value?(value = extract_attribute(line, 'aria-label'))
            tag_finder_results << FinderResult.new(:tag, value[1...-1], :place => :attribute, :attribute_name => 'aria-label')
          end

          txt = line[:value][:value]
          if txt
            has_script_in_tag = line[:value][:parse] # %element= foo
            if has_script_in_tag && !ExceptionFinder.could_match?(txt)
              tag_finder_results << FinderResult.new(:tag, '')
            elsif has_script_in_tag
              tag_finder_results << FinderResult.new(:tag, ExceptionFinder.new(txt).find, :place => :content)
            else
              # This is a plain old string in a HTML tag which is a special case that can be directly forwarded. Avoid
              # running regex which risks breaking such as if quotes are inside the plain string.
              # Skip single character strings which are often UI elements rather than
              # strings to be translated. Such as '|' or '+' or '*'. Also skip HTML comments
              if txt.length > 1 && !html_comment?(txt) && !ExceptionFinder.new(txt).filter_out_non_words(txt).empty?
                tag_finder_results << FinderResult.new(:tag, txt, :place => :content)
              end
            end
          else
            tag_finder_results << FinderResult.new(:tag, '')
          end

          tag_finder_results
        end

        def script(line)
          txt = line[:value][:text]
          if ExceptionFinder.could_match?(txt)
            match = ExceptionFinder.new(txt).find
            if (match.is_a?(Array))
              FinderResult.new(:script_array, match)
            else
              FinderResult.new(:script, match)
            end
          else
            FinderResult.new(:script, "")
          end
        end

        # returns nil, so extractor just keeps the orig_line and keeps on going.
        #
        # move to method missing and LINE_TYPES_IGNORE?
        # LINE_TYPES_IGNORE = [:silent_script, :haml_comment, :comment, :doctype, :root]
        def filter(line)
          ;
        end

        def silent_script(line)
          ;
        end

        def haml_comment(line)
          ;
        end

        def comment(line)
          ;
        end

        def doctype(line)
          ;
        end

        def root(line)
          ;
        end

      end
    end
  end
end
