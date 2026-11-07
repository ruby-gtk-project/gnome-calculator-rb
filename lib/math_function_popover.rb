# frozen_string_literal: true

require 'gtk4'

require_relative 'math_popover'
require_relative 'math_equation'
require_relative 'math_function'
require_relative 'function_manager'
require_relative 'equation_parser'

# MathFunctionPopover is the "f(x)" button's popover: a drill-in list of the
# built-in functions grouped by category (FunctionManager.function_categories),
# the user's custom functions below a separator that only shows when there
# are any, and a name/argument-count row that inserts a new
# "name(x; y)=" definition for the user to complete.
#
# Ported from upstream's src/math-function-popover.vala and
# src/ui/math-function-popover.blp.
class MathFunctionPopover < MathPopover
  include Gettext

  FUNCTION_ARGS = %w[x y z u v w a b c d].freeze

  def initialize(equation)
    @items = []
    @category_names = []
    super(
      equation,
      stack,
      validator: method(:validate_name),
      extra: add_arguments_button,
    )
    add_button.signal_connect('clicked') { add_function }
    built_in_list.signal_connect('row-activated') { |_box, row| open_category(row) }
    custom_list.signal_connect('row-activated') { |_box, row| insert_custom_function(row) }
    signal_connect('closed') do
      stack.visible_child_name = 'main'
      add_arguments_button.value = 1
    end
    load_built_in_functions
    load_custom_functions
  end

  private

    def stack
      @stack ||= Gtk::Stack.new.tap { |s| s.add_named(main_page, 'main') }
    end

    def main_page
      @main_page ||= Gtk::ScrolledWindow.new.tap do |scrolled|
        scrolled.propagate_natural_height = true
        scrolled.max_content_height = 336
        scrolled.hscrollbar_policy = :never
        scrolled.child = Gtk::Box.new(:vertical, 0).tap do |box|
          box.append(built_in_list)
          box.append(separator)
          box.append(custom_list)
        end
      end
    end

    def built_in_list
      @built_in_list ||= Gtk::ListBox.new.tap { |box| box.selection_mode = :none }
    end

    def separator
      @separator ||= Gtk::Separator.new(:horizontal).tap { |s| s.visible = false }
    end

    def custom_list
      @custom_list ||= Gtk::ListBox.new.tap do |box|
        box.selection_mode = :none
        box.visible = false
      end
    end

    def add_arguments_button
      @add_arguments_button ||= Gtk::SpinButton.new(1, 10, 1).tap do |spin|
        spin.value = 1
        spin.tooltip_text = _('Number of Arguments')
      end
    end

    def load_built_in_functions
      FunctionManager.function_categories.each_with_index do |category, index|
        page_name = "category_#{index}"
        @category_names << page_name
        category_row, submenu = make_category_row(category.name)
        built_in_list.insert(category_row, -1)
        submenu.signal_connect('row-activated') { |_box, row| select_built_in(row, category) }
        category.functions.each { |function| submenu.insert(built_in_row(function), -1) }
        stack.add_named(submenu, page_name)
      end
    end

    def built_in_row(function)
      make_item_row(item_text(function))
    end

    def load_custom_functions
      FunctionManager.default.names.each do |name|
        function = FunctionManager.default[name]
        if function.custom_function?
          item_added(function)
        end
      end
      FunctionManager.default.on_function_added { |function| item_added(function) }
      FunctionManager.default.on_function_edited { |function| item_edited(function) }
      FunctionManager.default.on_function_deleted { |function| item_deleted(function) }
    end

    def item_added(function)
      @items << function
      @items.sort! { |a, b| MathFunction.name_compare(a, b) }
      reload_rows
    end

    # Mirrors upstream's item_edited_cb: the function manager already holds
    # the new definition, so this only reorders the popover's own list.
    def item_edited(function)
      @items.reject! { |item| item.name == function.name }
      item_added(function)
    end

    def item_deleted(function)
      @items.reject! { |item| item.name == function.name }
      reload_rows
    end

    def reload_rows
      clear_listbox(custom_list)
      @items.each do |function|
        custom_list.insert(
          make_item_row(
            item_text(function),
            editable: proc { edit_function(function) },
            deletable: proc { FunctionManager.default.delete(function.name) },
          ),
          -1,
        )
      end
      visible = !@items.empty?
      separator.visible = visible
      custom_list.visible = visible
    end

    def item_text(function)
      format('<b>%s</b>(%s)', function.name, function.arguments.join(';'))
    end

    def edit_function(function)
      definition = format(
        '%s(%s)=%s@%s',
        function.name,
        function.arguments.join(';'),
        function.expression,
        function.description,
      )
      equation.clear
      equation.insert(definition)
      close_popover
    end

    def open_category(row)
      name_entry.text = ''
      stack.visible_child_name = @category_names[row.index]
    end

    def select_built_in(row, category)
      if row.index.zero?
        stack.visible_child_name = 'main'
      else
        equation.insert_function(category.functions[row.index - 1].name, force_brackets: true)
        close_popover
      end
    end

    def insert_custom_function(row)
      function = @items[row.index]
      equation.insert_function(function.name, force_brackets: true)
      close_popover
    end

    def add_function
      if add_button.sensitive?
        name = name_entry.text
        count = add_arguments_button.value.to_i
        args = ''
        if count.positive?
          args = FUNCTION_ARGS.first(count).join('; ')
        end
        equation.clear
        equation.insert("#{name}(#{args})=")
        close_popover
      end
    end

    def validate_name(name)
      if RESERVED_VARIABLE_NAMES.include?(name.downcase) || Parser.constants.key?(name) || equation.variables[name]
        _('Can not use defined variable or constant names')
      elsif built_in_conflict?(name) || OPERATORS.include?(name.downcase)
        _('Can not use built-in function or operator names')
      elsif name.match?(/\A\d/)
        _('Function name can not start with a digit')
      elsif !name.match?(/\A\w*\z/)
        _('Function name can only contain digits, letters and underscores')
      end
    end

    def built_in_conflict?(name)
      function = FunctionManager.default[name]
      !function.nil? && !function.custom_function?
    end
end
