# frozen_string_literal: true

require 'gtk4'

require_relative 'basic_button_panel'
require_relative 'math_variable_popover'
require_relative 'math_function_popover'
require_relative 'translations'

# AdvancedButtonPanel adds the scientific function grid — trig, logs,
# exponents, complex-number components, factorial/factorize, the angle-unit
# cycle button, π/e/i — above the basic digit/operator grid.
#
# Ported from upstream's src/buttons-advanced.vala and
# src/ui/buttons-advanced.blp. Upstream switches between a side-by-side
# `box` layout and a swipeable `Adw.Carousel` layout depending on the
# window's width, via an `Adw.BreakpointBin`/`Adw.MultiLayoutView`; this
# port always stacks the two grids vertically in a `Gtk::Box` (the `box`
# layout) rather than reproducing the carousel breakpoint, which is a
# narrow-width convenience rather than a behavioural difference. Each
# button dispatches through the `cal.*` action group `MathButtons` installs
# (see math_buttons.rb), exactly as upstream's blueprint-defined buttons do
# with their `action-name`/`action-target` pairs — the one exception is
# `cal.insert-brackets`, whose parameter is a plain two-character string
# here instead of upstream's `(ss)` tuple (see FINDINGS.md).
class AdvancedButtonPanel
  include Gettext

  attr_reader :equation

  def initialize(equation, buttons:)
    @equation = equation
    @buttons = buttons
  end

  def build = root

  def root
    @root ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.append(advanced_grid)
      box.append(basic_panel.build)
    end
  end

  def basic_panel = @basic_panel ||= BasicButtonPanel.new(equation)

  def advanced_grid
    @advanced_grid ||= Gtk::Grid.new.tap do |grid|
      grid.add_css_class('buttons')
      grid.hexpand = true
      grid.row_homogeneous = true
      grid.column_homogeneous = true

      attach_all(grid, [
        [inverse_modifier_button, 0, 0],
        [sine_button, 0, 1],
        [hyperbolic_sine_button, 1, 1],
        [cosine_button, 0, 2],
        [hyperbolic_cosine_button, 1, 2],
        [tangent_button, 0, 3],
        [hyperbolic_tangent_button, 1, 3],
        [x_squared_button, 1, 0],
        [x_pow_y_button, 2, 0],
        [logarithm_button, 2, 1],
        [common_logarithm_button, 2, 2],
        [natural_logarithm_button, 2, 3],
        [conjugate_button, 3, 0],
        [arg_button, 3, 1],
        [real_portion_button, 3, 2],
        [imaginary_portion_button, 3, 3],
        [inverse_button, 4, 0],
        [round_button, 4, 1],
        [abs_button, 4, 2],
        [factorial_button, 4, 3],
        [angle_units_button, 0, 4],
        [pi_button, 1, 4],
        [eulers_number_button, 2, 4],
        [imaginary_button, 3, 4],
        [factor_button, 4, 4],
      ])
    end
  end

  def inverse_modifier_button
    @inverse_modifier_button ||= Gtk::ToggleButton.new.tap do |button|
      button.label = '⇧⁻¹'
      button.focus_on_click = false
      button.tooltip_text = _('Inverse Modifier [Shift]')
      button.add_css_class('accent')
      button.active = @buttons.inverse
      button.signal_connect('toggled') { @buttons.inverse = button.active? }
    end
  end

  def inverse? = inverse_modifier_button.active?

  # Function-grid button that has an inverse counterpart: `name` is the
  # upstream function token, `label`/`inverse_label` and
  # `tooltip`/`inverse_tooltip` swap with `inverse_modifier_button`.
  def function_pair_button(name, label, tooltip, inverse_name, inverse_label, inverse_tooltip)
    Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      refresh = lambda do
        if inverse?
          button.label = inverse_label
          button.tooltip_text = inverse_tooltip
          button.action_target = string_target(inverse_name)
          button.add_css_class('accent')
        else
          button.label = label
          button.tooltip_text = tooltip
          button.action_target = string_target(name)
          button.remove_css_class('accent')
        end
      end
      button.action_name = 'cal.insert-function'
      button.add_css_class('function-button')
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
    end
  end

  def sine_button
    @sine_button ||= function_pair_button(
      'sin',
      'sin',
      _('Sine'),
      'sin⁻¹',
      'sin⁻¹',
      _('Inverse Sine'),
    )
  end

  def hyperbolic_sine_button
    @hyperbolic_sine_button ||= function_pair_button(
      'sinh',
      'sinh',
      _('Hyperbolic Sine'),
      'sinh⁻¹',
      'sinh⁻¹',
      _('Inverse Hyperbolic Sine'),
    )
  end

  def cosine_button
    @cosine_button ||= function_pair_button(
      'cos',
      'cos',
      _('Cosine'),
      'cos⁻¹',
      'cos⁻¹',
      _('Inverse Cosine'),
    )
  end

  def hyperbolic_cosine_button
    @hyperbolic_cosine_button ||= function_pair_button(
      'cosh',
      'cosh',
      _('Hyperbolic Cosine'),
      'cosh⁻¹',
      'cosh⁻¹',
      _('Inverse Hyperbolic Cosine'),
    )
  end

  def tangent_button
    @tangent_button ||= function_pair_button(
      'tan',
      'tan',
      _('Tangent'),
      'tan⁻¹',
      'tan⁻¹',
      _('Inverse Tangent'),
    )
  end

  def hyperbolic_tangent_button
    @hyperbolic_tangent_button ||= function_pair_button(
      'tanh',
      'tanh',
      _('Hyperbolic Tangent'),
      'tanh⁻¹',
      'tanh⁻¹',
      _('Inverse Hyperbolic Tangent'),
    )
  end

  def common_logarithm_button
    @common_logarithm_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      label = markup_label(button)
      refresh = lambda do
        if inverse?
          label.label = '10<sup><i>x</i></sup>'
          button.tooltip_text = _('Base-10 Exponential')
          button.action_name = 'cal.insert-exponent'
          button.action_target = string_target('10')
          button.add_css_class('accent')
        else
          label.label = 'log'
          button.tooltip_text = _('Common Logarithm')
          button.action_name = 'cal.insert-function'
          button.action_target = string_target('log')
          button.remove_css_class('accent')
        end
      end
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
      button.add_css_class('function-button')
    end
  end

  def natural_logarithm_button
    @natural_logarithm_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      label = markup_label(button)
      refresh = lambda do
        if inverse?
          label.label = 'e<sup><i>x</i></sup>'
          button.tooltip_text = _('Natural Exponential')
          button.action_name = 'cal.insert-exponent'
          button.action_target = string_target('e')
          button.add_css_class('accent')
        else
          label.label = 'ln'
          button.tooltip_text = _('Natural Logarithm')
          button.action_name = 'cal.insert-function'
          button.action_target = string_target('ln')
          button.remove_css_class('accent')
        end
      end
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
      button.add_css_class('function-button')
    end
  end

  def conjugate_button
    @conjugate_button ||= Gtk::Button.new.tap do |button|
      button.label = 'conj'
      button.focus_on_click = false
      button.tooltip_text = _('Complex Conjugate')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-function'
      button.action_target = string_target('conj')
    end
  end

  def arg_button
    @arg_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Arg'
      button.focus_on_click = false
      button.tooltip_text = _('Complex Argument')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-function'
      button.action_target = string_target('Arg')
    end
  end

  def real_portion_button
    @real_portion_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Re'
      button.focus_on_click = false
      button.tooltip_text = _('Real Component')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-function'
      button.action_target = string_target('Re')
    end
  end

  def imaginary_portion_button
    @imaginary_portion_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Im'
      button.focus_on_click = false
      button.tooltip_text = _('Imaginary Component')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-function'
      button.action_target = string_target('Im')
    end
  end

  # x², with an inverse of √ (insert-symbol-before) rather than
  # insert-function, so this pair is wired by hand instead of through
  # `function_pair_button`.
  def x_squared_button
    @x_squared_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      label = markup_label(button)
      refresh = lambda do
        if inverse?
          label.label = '√'
          button.tooltip_text = _('Square Root [Ctrl+R]')
          button.action_name = 'cal.insert-symbol-before'
          button.action_target = string_target('√')
          button.add_css_class('accent')
        else
          label.label = '<i>x</i>²'
          button.tooltip_text = _('Square [Ctrl+2]')
          button.set_action_target_value(nil)
          button.action_name = 'cal.square'
          button.remove_css_class('accent')
        end
      end
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
      button.add_css_class('function-button')
    end
  end

  def x_pow_y_button
    @x_pow_y_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      label = markup_label(button)
      refresh = lambda do
        if inverse?
          label.label = '<sup>y</sup>√'
          button.tooltip_text = _('Nth Root')
          button.set_action_target_value(nil)
          button.action_name = 'cal.nth-root'
          button.add_css_class('accent')
        else
          label.label = '<i>x</i><sup><i>y</i></sup>'
          button.tooltip_text = _('Exponent [^ or **]')
          button.action_name = 'cal.insert-symbol-after'
          button.action_target = string_target('^')
          button.remove_css_class('accent')
        end
      end
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
      button.add_css_class('function-button')
    end
  end

  def logarithm_button
    @logarithm_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      label = markup_label(button)
      refresh = lambda do
        if inverse?
          label.label = '10<sup><i>x</i></sup>'
          button.tooltip_text = _('Base-10 Exponential')
          button.action_name = 'cal.insert-exponent'
          button.action_target = string_target('10')
          button.add_css_class('accent')
        else
          label.label = 'log<sub><i>y</i></sub>'
          button.tooltip_text = _('Logarithm')
          button.set_action_target_value(nil)
          button.action_name = 'cal.logarithm'
          button.remove_css_class('accent')
        end
      end
      inverse_modifier_button.signal_connect('toggled') { refresh.call }
      refresh.call
      button.add_css_class('function-button')
    end
  end

  def inverse_button
    @inverse_button ||= Gtk::Button.new.tap do |button|
      markup_label(button).label = '<i>x</i>⁻¹'
      button.focus_on_click = false
      button.tooltip_text = _('Inverse [Ctrl+I]')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-symbol-after'
      button.action_target = string_target('⁻¹')
    end
  end

  def round_button
    @round_button ||= Gtk::Button.new.tap do |button|
      markup_label(button).label = '[<i>x</i>]'
      button.focus_on_click = false
      button.tooltip_text = _('Round [[]]')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-brackets'
      button.action_target = string_target('[]')
    end
  end

  def abs_button
    @abs_button ||= Gtk::Button.new.tap do |button|
      markup_label(button).label = '|<i>x</i>|'
      button.focus_on_click = false
      button.tooltip_text = _('Absolute Value [||]')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-brackets'
      button.action_target = string_target('||')
    end
  end

  def factorial_button
    @factorial_button ||= Gtk::Button.new.tap do |button|
      markup_label(button).label = '<i>x</i>!'
      button.focus_on_click = false
      button.tooltip_text = _('Factorial [!]')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-symbol-after'
      button.action_target = string_target('!')
    end
  end

  def angle_units_button
    @angle_units_button ||= Gtk::Button.new.tap do |button|
      button.focus_on_click = false
      button.use_underline = true
      button.add_css_class('function-button')
      button.signal_connect('clicked') { cycle_angle_units }
      refresh_angle_units_button(button)
    end
  end

  def pi_button
    @pi_button ||= Gtk::Button.new.tap do |button|
      button.label = 'π'
      button.focus_on_click = false
      button.tooltip_text = _('Pi [Ctrl+P]')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-alpha'
      button.action_target = string_target('π')
    end
  end

  def eulers_number_button
    @eulers_number_button ||= Gtk::Button.new.tap do |button|
      button.label = 'e'
      button.focus_on_click = false
      button.tooltip_text = _("Euler’s Number")
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-alpha'
      button.action_target = string_target('e')
    end
  end

  def imaginary_button
    @imaginary_button ||= Gtk::Button.new.tap do |button|
      button.label = 'i'
      button.focus_on_click = false
      button.tooltip_text = _('Imaginary Unit')
      button.add_css_class('function-button')
      button.action_name = 'cal.insert-alpha'
      button.action_target = string_target('i')
    end
  end

  def factor_button
    @factor_button ||= Gtk::Button.new.tap do |button|
      button.label = 'a×b'
      button.focus_on_click = false
      button.tooltip_text = _('Factorize [Ctrl+F]')
      button.add_css_class('function-button')
      button.action_name = 'cal.factorize'
    end
  end

  def variable_popover = @variable_popover ||= MathVariablePopover.new(equation)

  def function_popover = @function_popover ||= MathFunctionPopover.new(equation)

  private

    # Every cell in `advanced_grid` spans exactly one column and one row;
    # `cell` is `[widget, column, row]`, so there is exactly one multi-line
    # `grid.attach` call to maintain instead of one per widget.
    def attach_all(grid, cells)
      cells.each { |cell| attach(grid, cell) }
    end

    def attach(grid, cell)
      widget, column, row = cell
      grid.attach(
        widget,
        column,
        row,
        1,
        1,
      )
    end

    # Gtk::Button has no `use-markup` of its own (that belongs to the
    # label it builds internally from a plain string); the handful of
    # buttons here whose label needs Pango markup — "<i>x</i>²" and the
    # like — get an explicit Gtk::Label child instead, the same shape
    # upstream's blueprint uses with a nested `Label { use-markup: true; }`.
    def markup_label(button)
      Gtk::Label.new.tap do |label|
        label.use_markup = true
        button.child = label
      end
    end

    def string_target(text) = GLib::Variant.new(text, GLib::VariantType.new('s'))

    # Mirrors upstream's AdvancedButtonPanel.on_set_angle_units: cycles
    # Radians -> Gradians -> Degrees -> Radians, same order upstream's
    # `(angle_units + 2) % 3` produces over its RAD/DEG/GRAD enum.
    def cycle_angle_units
      index = AngleUnit::ALL.index(equation.angle_units)
      equation.angle_units = AngleUnit::ALL[(index + 2) % 3]
      refresh_angle_units_button(angle_units_button)
    end

    def refresh_angle_units_button(button)
      symbols = { AngleUnit::RADIANS => 'Rad', AngleUnit::DEGREES => 'Deg', AngleUnit::GRADIANS => 'Grad' }
      names = { AngleUnit::RADIANS => _('Radians'), AngleUnit::DEGREES => _('Degrees'), AngleUnit::GRADIANS => _('Gradians') }
      button.label = symbols.fetch(equation.angle_units)
      button.tooltip_text = _('Angle Unit: %s') % names.fetch(equation.angle_units)
    end
end
