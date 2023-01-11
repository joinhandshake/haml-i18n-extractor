require 'test_helper'

module Haml
  class ExceptionFinderTest < Minitest::Test

    MATCHES =  {
      %{TEXT} => "TEXT",
      %{"TEXT"} => "TEXT",
      %{'TEXT'} => "TEXT",
      %{(TEX'T)} => "(TEX'T)",
      %{"TEX'T"} => "TEX'T",
      %{  TEXT} => "  TEXT",
      %{t('TEXT')} => "t('TEXT')",
      %{TEXT \#{with_code}} => "TEXT \#{with_code}",
      %{link_to 'TEXT', "http://bla"} => ["TEXT", "http://bla"],
      %{link_to('TEXT', "http://bla")} => ["TEXT", "http://bla"],
      %{link_to   "TEXT", "http://bla")} => ["TEXT", "http://bla"],
      %{link_to("TEXT"), role: 'button', data: {toggle: 'dropdown'} do} => ["TEXT", "button", "dropdown"],
      %{link_to   "TEXT", role: 'button', data: {toggle: 'dropdown'} do} => ["TEXT", "button", "dropdown"],
      %{link_to pending_account_invoices_path(account) do} => "",
      %{link_to(pending_account_invoices_path(account),"http://random")} => "http://random",
      %{f.submit "Close This Month (cannot be undone)", :class => 'btn btn-primary'} => ["Close This Month (cannot be undone)", "btn btn-primary"]
    }

    UI_ELEMENT_STRINGS = [%{"*"}, %{'x'}, %{"•"}]

    def test_it_finds_text_pretty_simply
      MATCHES.each do |input, expected_result|
        assert_equal expected_result, find(input)
      end
    end

    def test_it_does_not_find_ui_element_strings
      UI_ELEMENT_STRINGS.each do |input|
        assert_nil find(input)
      end
    end

    def test_it_actually_needs_to_do_something_intellegent_with_intperolated_values
      # @FIXME
      #raise "raw text matching needs to be responsible for knowing if needed to interpolate?"
    end

    def test_it_finds_parameters
      input = "= f.input :blah, label: 'BLAH', hint: 'BLABBLOO'"
      find_results = find(input)
      assert_equal(['BLAH', 'BLABBLOO'], find_results)
    end

    def test_it_does_not_find_render_partial_strings
      input = "    = render 'sidebar'"
      find_results = find(input)
      assert_nil find_results
    end

    def test_it_does_not_find_render_partial_strings_two
      input = '= render layout: "partial_name"'
      find_results = find(input)
      assert_nil find_results
    end

    def test_it_handles_complex_render_calls
      input = "= render 'empty_state', text: \"BLAH'S TEXT.\", description: 'FOO BAR', result_partial: 'contacts/results'"
      find_results = find(input)
      assert_equal(["BLAH'S TEXT.", "FOO BAR"], find_results)
    end

    def test_it_does_not_find_component_strings
      input = "= react_component 'MyReactComponent'"
      find_results = find(input)
      assert_nil find_results
    end

    def test_it_does_not_find_component_strings_two
      input = "= knockout_component('MyReactComponent') do"
      find_results = find(input)
      assert_nil find_results
    end

    def test_it_handles_complex_component_renders
      input = "= knockout_component 'ManageContactsView', text: \"BLAH'S TEXT.\", description: 'FOO BAR', result_partial: 'contacts/results'"
      find_results = find(input)
      assert_equal(["BLAH'S TEXT.", "FOO BAR"], find_results)
    end

    def test_it_handles_simple_form_for
      input = "= simple_nested_form_for @record, :html => { \"data-bind\" => \"disableOnSubmit: true\" }, :defaults => { input_html: { class: 'form-control' }}  do |f|"
      find_results = find(input)
      assert_nil find_results
    end

    private

    def find(txt)
      Haml::I18n::Extractor::ExceptionFinder.new(txt).find
    end
  end
end
