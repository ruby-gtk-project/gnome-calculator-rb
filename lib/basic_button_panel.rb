# frozen_string_literal: true

require 'gtk4'

require_relative 'math_equation'
require_relative 'translations'

# BasicButtonPanel is the calculator's basic-mode button grid: digits,
# the four arithmetic operators, percent, grouping, memory/function
# menu buttons and the result button.
#
# Ported from upstream's src/buttons-basic.vala and src/ui/buttons-basic.blp.
# Upstream wires each button to a `cal.*` GAction on the window; this port
# connects each button's `clicked` signal straight to the MathEquation
# method that action would have dispatched to, which is the plainer shape
# house style (see .claude/skills/ruby-gtk) uses throughout. The memory and
# function MenuButtons are left unpopulated — they belong to
# math_variable_popover.rb and math_function_popover.rb, not ported this
# round.
class BasicButtonPanel
  include Gettext

  attr_reader :equation

  def initialize(equation, after_action: nil)
    @equation = equation
    @after_action = after_action || proc {}
  end

  def build = root

  def root
    @root ||= Gtk::Grid.new.tap do |grid|
      grid.add_css_class('buttons')
      grid.hexpand = true
      grid.row_homogeneous = true
      grid.column_homogeneous = true

      grid.attach(
        clear_button,
        0,
        0,
        1,
        1,
      )
      grid.attach(
        superscript_button,
        1,
        0,
        1,
        1,
      )
      grid.attach(
        subscript_button,
        2,
        0,
        1,
        1,
      )
      grid.attach(
        divide_button,
        3,
        0,
        1,
        1,
      )
      grid.attach(
        modulus_divide_button,
        4,
        0,
        1,
        1,
      )

      grid.attach(
        digit_button(7),
        0,
        1,
        1,
        1,
      )
      grid.attach(
        digit_button(8),
        1,
        1,
        1,
        1,
      )
      grid.attach(
        digit_button(9),
        2,
        1,
        1,
        1,
      )
      grid.attach(
        multiply_button,
        3,
        1,
        1,
        1,
      )
      grid.attach(
        percentage_button,
        4,
        1,
        1,
        1,
      )

      grid.attach(
        digit_button(4),
        0,
        2,
        1,
        1,
      )
      grid.attach(
        digit_button(5),
        1,
        2,
        1,
        1,
      )
      grid.attach(
        digit_button(6),
        2,
        2,
        1,
        1,
      )
      grid.attach(
        subtract_button,
        3,
        2,
        1,
        1,
      )
      grid.attach(
        group_button,
        4,
        2,
        1,
        1,
      )

      grid.attach(
        digit_button(1),
        0,
        3,
        1,
        1,
      )
      grid.attach(
        digit_button(2),
        1,
        3,
        1,
        1,
      )
      grid.attach(
        digit_button(3),
        2,
        3,
        1,
        1,
      )
      grid.attach(
        add_button,
        3,
        3,
        1,
        1,
      )
      grid.attach(
        result_button,
        4,
        3,
        1,
        2,
      )

      grid.attach(
        digit_button(0),
        0,
        4,
        1,
        1,
      )
      grid.attach(
        numeric_point_button,
        1,
        4,
        1,
        1,
      )
      grid.attach(
        memory_button,
        2,
        4,
        1,
        1,
      )
      grid.attach(
        function_button,
        3,
        4,
        1,
        1,
      )
    end
  end

  def clear_button
    @clear_button ||= Gtk::Button.new.tap do |button|
      button.label = 'C'
      button.focus_on_click = false
      button.tooltip_text = _('Clear Display [Escape]')
      button.add_css_class('clear-button')
      button.signal_connect('clicked') { after_action { equation.clear } }
    end
  end

  def superscript_button
    @superscript_button ||= Gtk::ToggleButton.new.tap do |button|
      button.label = '↑n'
      button.focus_on_click = false
      button.tooltip_text = _('Superscript Mode [Ctrl]')
      button.add_css_class('function-button')
      button.signal_connect('toggled') do
        after_action do
          if button.active?
            equation.number_mode = NumberMode::SUPERSCRIPT
          else
            equation.number_mode = NumberMode::NORMAL
          end
        end
      end
    end
  end

  def subscript_button
    @subscript_button ||= Gtk::ToggleButton.new.tap do |button|
      button.label = '↓n'
      button.focus_on_click = false
      button.tooltip_text = _('Subscript Mode [Alt]')
      button.add_css_class('function-button')
      button.signal_connect('toggled') do
        after_action do
          if button.active?
            equation.number_mode = NumberMode::SUBSCRIPT
          else
            equation.number_mode = NumberMode::NORMAL
          end
        end
      end
    end
  end

  def digit_button(digit)
    @digit_buttons ||= {}
    @digit_buttons[digit] ||= Gtk::Button.new.tap do |button|
      button.label = digit.to_s
      button.focus_on_click = false
      button.add_css_class('number-button')
      button.signal_connect('clicked') { after_action { equation.insert_digit(digit) } }
    end
  end

  def numeric_point_button
    @numeric_point_button ||= Gtk::Button.new.tap do |button|
      button.label = equation.serializer.radix
      button.focus_on_click = false
      button.add_css_class('numeric-point-button')
      button.signal_connect('clicked') { after_action { equation.insert_numeric_point } }
    end
  end

  def memory_button
    @memory_button ||= Gtk::MenuButton.new.tap do |button|
      button.label = _('x')
      button.focus_on_click = false
      button.tooltip_text = _('Variables and Constants')
      button.direction = :up
      button.add_css_class('function-button')
    end
  end

  def function_button
    @function_button ||= Gtk::MenuButton.new.tap do |button|
      button.label = 'f(x)'
      button.focus_on_click = false
      button.tooltip_text = _('Additional Functions')
      button.direction = :up
      button.add_css_class('function-button')
    end
  end

  def divide_button
    @divide_button ||= operator_button('÷', _('Divide [/]')) { equation.insert('÷') }
  end

  def multiply_button
    @multiply_button ||= operator_button('×', _('Multiply [*]')) { equation.insert('×') }
  end

  def subtract_button
    @subtract_button ||= operator_button('−', _('Subtract [-]')) { equation.insert('−') }
  end

  def add_button
    @add_button ||= operator_button('+', _('Add [+]')) { equation.insert('+') }
  end

  def modulus_divide_button
    @modulus_divide_button ||= Gtk::Button.new.tap do |button|
      button.label = 'mod'
      button.focus_on_click = false
      button.tooltip_text = _('Modulus Divide')
      button.add_css_class('function-button')
      button.signal_connect('clicked') { after_action { equation.insert('mod') } }
    end
  end

  def percentage_button
    @percentage_button ||= Gtk::Button.new.tap do |button|
      button.label = '%'
      button.focus_on_click = false
      button.tooltip_text = _('Percentage [%]')
      button.add_css_class('percent-button')
      button.signal_connect('clicked') { after_action { equation.insert('%') } }
    end
  end

  def group_button
    @group_button ||= Gtk::Button.new.tap do |button|
      button.label = '( )'
      button.focus_on_click = false
      button.tooltip_text = _('Group [()]')
      button.add_css_class('parenthesis-button')
      button.signal_connect('clicked') do
        after_action do
          equation.insert('(')
          equation.insert(')')
        end
      end
    end
  end

  def result_button
    @result_button ||= Gtk::Button.new.tap do |button|
      button.label = _('=')
      button.focus_on_click = false
      button.tooltip_text = _('Calculate Result')
      button.add_css_class('suggested-action')
      button.signal_connect('clicked') { after_action { equation.solve } }
    end
  end

  private

    def operator_button(label, tooltip, &block)
      Gtk::Button.new.tap do |button|
        button.label = label
        button.focus_on_click = false
        button.tooltip_text = tooltip
        button.add_css_class('operator-button')
        button.signal_connect('clicked') { after_action(&block) }
      end
    end

    def after_action
      yield
      @after_action.call
    end
end
