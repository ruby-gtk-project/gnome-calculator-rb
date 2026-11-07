# frozen_string_literal: true

require 'gtk4'

require_relative 'math_popover'
require_relative 'math_equation'
require_relative 'equation_parser'
require_relative 'function_manager'

# One row in MathVariablePopover's list: a stored register, or one of the
# two read-only pseudo-variables ("rand" and the last answer, "_").
#
# Ported from upstream's MathVariable class in src/math-variable-popover.vala.
MathVariable = Struct.new(:name, :value, :is_custom) do
  def initialize(name, value, is_custom = true)
    super
  end

  def self.compare(first, second)
    if first.is_custom != second.is_custom
      first.is_custom ? 1 : -1
    else
      first.name <=> second.name
    end
  end
end

# MathVariablePopover is the "x" button's popover: the user's stored
# variables, the read-only "rand" and "_" pseudo-variables, and a drill-in
# list of the built-in mathematical and physical constants, grouped by
# category exactly as Parser.constant_categories lists them.
#
# Ported from upstream's src/math-variable-popover.vala and
# src/ui/math-variable-popover.blp.
class MathVariablePopover < MathPopover
  include Gettext

  def initialize(equation)
    @items = []
    @category_names = []
    super(
      equation,
      stack,
      validator: method(:validate_name),
    )
    add_button.signal_connect('clicked') { store_variable }
    variable_list.signal_connect('row-activated') { |_box, row| insert_variable(row) }
    constant_list.signal_connect('row-activated') { |_box, row| open_category(row) }
    signal_connect('closed') { stack.visible_child_name = 'main' }
    equation.on_history { |_text, number, *_rest| item_edited(MathVariable.new('_', number, false)) }
    load_variables
    load_constants
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
          box.append(variable_list)
          box.append(constant_list)
        end
      end
    end

    def variable_list
      @variable_list ||= Gtk::ListBox.new.tap { |box| box.selection_mode = :none }
    end

    def constant_list
      @constant_list ||= Gtk::ListBox.new.tap { |box| box.selection_mode = :none }
    end

    def load_variables
      equation.variables.names.each do |name|
        item_added(MathVariable.new(name, equation.variables[name]))
      end
      item_added(MathVariable.new('rand', nil, false))
      item_added(MathVariable.new('_', equation.answer, false))
      equation.variables.on_variable_added { |name, value| item_added(MathVariable.new(name, value)) }
      equation.variables.on_variable_edited { |name, value| item_edited(MathVariable.new(name, value)) }
      equation.variables.on_variable_deleted { |name| item_deleted(MathVariable.new(name, nil)) }
    end

    def load_constants
      Parser.constant_categories.each_with_index do |category, index|
        page_name = "category_#{index}"
        @category_names << page_name
        category_row, submenu = make_category_row(category.name)
        constant_list.insert(category_row, -1)
        submenu.signal_connect('row-activated') { |_box, row| select_constant(row, category) }
        category.constants.each { |constant| submenu.insert(constant_row(constant), -1) }
        stack.add_named(submenu, page_name)
      end
    end

    def constant_row(constant)
      Gtk::Box.new(:horizontal, 0).tap do |box|
        box.append(Gtk::Label.new(constant.name))
        box.append(Gtk::Label.new(constant.symbol).tap do |label|
          label.halign = :end
          label.hexpand = true
          label.add_css_class('dimmed')
        end)
      end
    end

    def item_added(variable)
      @items << variable
      @items.sort! { |a, b| MathVariable.compare(a, b) }
      reload_rows
    end

    def item_edited(variable)
      @items.reject! { |item| item.name == variable.name }
      item_added(variable)
    end

    def item_deleted(variable)
      @items.reject! { |item| item.name == variable.name }
      reload_rows
    end

    def reload_rows
      clear_listbox(variable_list)
      @items.each do |variable|
        variable_list.insert(
          make_item_row(item_text(variable), deletable: deletable_proc(variable)),
          -1,
        )
      end
    end

    def deletable_proc(variable)
      unless RESERVED_VARIABLE_NAMES.include?(variable.name)
        proc { equation.variables.delete(variable.name) }
      end
    end

    def item_text(variable)
      if variable.value
        format('<b>%s</b> = %s', variable.name, equation.serializer.to_string(variable.value))
      else
        format('<b>%s</b>', variable.name)
      end
    end

    def insert_variable(row)
      variable = @items[row.index]
      equation.insert_alpha(variable.name)
      close_popover
    end

    def open_category(row)
      stack.visible_child_name = @category_names[row.index]
    end

    def select_constant(row, category)
      if row.index.zero?
        stack.visible_child_name = 'main'
      else
        equation.insert_alpha(category.constants[row.index - 1].symbol)
        close_popover
      end
    end

    def store_variable
      if add_button.sensitive?
        name = name_entry.text
        value = equation.number
        if value.nil? && equation.is_result
          value = equation.answer
        end
        if value.nil?
          equation.solve
          value = equation.answer
        end
        if value
          equation.variables[name] = value
        end
        name_entry.text = ''
      end
    end

    def validate_name(name)
      if FunctionManager.default.function_defined?(name) || OPERATORS.include?(name.downcase)
        _('Can not use defined function or operator names')
      elsif RESERVED_VARIABLE_NAMES.include?(name.downcase) || Parser.constants.key?(name)
        _('Can not use built-in variable or constant names')
      elsif name.match?(/\A\d/)
        _('Variable name can not start with a digit')
      elsif !name.match?(/\A\w*\z/)
        _('Variable name can only contain digits, letters and underscores')
      end
    end
end
