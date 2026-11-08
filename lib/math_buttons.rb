# frozen_string_literal: true

require 'gtk4'

require_relative 'basic_button_panel'
require_relative 'advanced_button_panel'
require_relative 'translations'

# The mode a MathButtons panel is showing — upstream's ButtonMode enum at
# the top of src/math-buttons.vala.
module ButtonMode
  BASIC = :basic
  ADVANCED = :advanced
  FINANCIAL = :financial
  PROGRAMMING = :programming
  KEYBOARD = :keyboard
  CONVERSION = :conversion
end

# MathButtons hosts the mode-switchable button panel: a Gtk::Stack holding
# one child per mode, built lazily the first time its mode is selected, and
# the `cal` action group every button-panel grid dispatches into (insert,
# clear, solve, undo, the number-mode toggle, and the handful of
# equation-editing helpers only a button needs — brackets, symbols, square,
# nth root, logarithm, exponent, factorize).
#
# Ported from upstream's src/math-buttons.vala. This round ports the Basic
# and Advanced panels (see component-parity report for the rest); `mode=`
# only accepts those two, and Financial/Programming/Conversion stay
# unreachable until their panels exist.
class MathButtons
  include Gettext

  attr_reader :equation
  attr_accessor :inverse

  def initialize(equation, after_action: nil)
    @equation = equation
    @after_action = after_action || proc {}
    @mode = nil
    @inverse = false
    @panels = {}
    root.insert_action_group('cal', action_group)
    equation.on_number_mode_changed { update_number_mode_state }
  end

  def build = root

  def mode = @mode

  def mode=(value)
    if @mode == value
      nil
    else
      @mode = value
      if value == ButtonMode::PROGRAMMING
        equation.number_base = programming_base
      else
        equation.number_base = 10
      end
      root.visible_child = panel_for(value)
    end
  end

  def root
    @root ||= Gtk::Stack.new.tap do |stack|
      stack.hhomogeneous = false
      stack.vhomogeneous = false
    end
  end

  # The panel object (BasicButtonPanel, AdvancedButtonPanel, ...) built for
  # a mode, building it lazily on first access exactly like `mode=` does.
  # Public so tests and drive scripts can reach the real button objects
  # instead of poking at Gtk::Stack children.
  def panel(mode)
    panel_for(mode)
    @panels[mode].first
  end

  private

    def programming_base = 10

    def dispatch
      yield
      @after_action.call
    end

    def panel_for(mode)
      object, widget = @panels[mode]
      unless object
        object = case mode
                 when ButtonMode::BASIC then BasicButtonPanel.new(equation, after_action: @after_action)
                 when ButtonMode::ADVANCED then AdvancedButtonPanel.new(equation, buttons: self)
                 else raise ArgumentError, "MathButtons has no panel for #{mode.inspect} yet"
                 end
        widget = object.build.tap { |w| root.add_child(w) }
        @panels[mode] = [object, widget]
      end
      widget
    end

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(insert_general_action)
        group.add_action(insert_digit_action)
        group.add_action(insert_brackets_action)
        group.add_action(insert_alpha_action)
        group.add_action(insert_function_action)
        group.add_action(insert_symbol_before_action)
        group.add_action(insert_symbol_after_action)
        group.add_action(insert_exponent_action)
        group.add_action(insert_numeric_point_action)
        group.add_action(subtract_action)
        group.add_action(square_action)
        group.add_action(nth_root_action)
        group.add_action(logarithm_action)
        group.add_action(factorize_action)
        group.add_action(undo_action)
        group.add_action(clear_action)
        group.add_action(solve_action)
        group.add_action(set_number_mode_action)
      end
    end

    def insert_general_action
      Gio::SimpleAction.new('insert-general', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert(parameter.to_s) } }
      end
    end

    def insert_digit_action
      Gio::SimpleAction.new('insert-digit', GLib::VariantType.new('i')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_digit(parameter.to_i) } }
      end
    end

    # Upstream's action takes a `(ss)` tuple of opening/closing brackets;
    # the Ruby GVariant bindings cannot construct a tuple variant (see
    # FINDINGS.md), so this takes the pair as a two-character string
    # instead — "()", "[]" or "||" — and splits it back apart.
    def insert_brackets_action
      Gio::SimpleAction.new('insert-brackets', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') do |_, parameter|
          opening, closing = parameter.to_s.chars
          dispatch { equation.insert_brackets(opening, closing) }
        end
      end
    end

    def insert_alpha_action
      Gio::SimpleAction.new('insert-alpha', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_alpha(parameter.to_s) } }
      end
    end

    def insert_function_action
      Gio::SimpleAction.new('insert-function', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_function(parameter.to_s) } }
      end
    end

    def insert_symbol_before_action
      Gio::SimpleAction.new('insert-symbol-before', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_symbol(parameter.to_s, false) } }
      end
    end

    def insert_symbol_after_action
      Gio::SimpleAction.new('insert-symbol-after', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_symbol(parameter.to_s, true) } }
      end
    end

    def insert_exponent_action
      Gio::SimpleAction.new('insert-exponent', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| dispatch { equation.insert_exponent(parameter.to_s) } }
      end
    end

    def insert_numeric_point_action
      Gio::SimpleAction.new('insert-numeric-point', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.insert_numeric_point } }
      end
    end

    def subtract_action
      Gio::SimpleAction.new('subtract', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.insert_subtract } }
      end
    end

    def square_action
      Gio::SimpleAction.new('square', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.insert_square } }
      end
    end

    def nth_root_action
      Gio::SimpleAction.new('nth-root', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.insert_nth_root } }
      end
    end

    def logarithm_action
      Gio::SimpleAction.new('logarithm', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.insert_logarithm } }
      end
    end

    def factorize_action
      Gio::SimpleAction.new('factorize', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.factorize } }
      end
    end

    def undo_action
      Gio::SimpleAction.new('undo', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.undo } }
      end
    end

    def clear_action
      Gio::SimpleAction.new('clear', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.clear } }
      end
    end

    def solve_action
      Gio::SimpleAction.new('solve', nil).tap do |action|
        action.signal_connect('activate') { dispatch { equation.solve } }
      end
    end

    # Stateful: the active string is "normal", "superscript" or
    # "subscript", kept in sync with `equation.number_mode` both ways —
    # activating it with the already-active target toggles back to normal,
    # same as upstream's on_set_number_mode.
    def set_number_mode_action
      @set_number_mode_action ||= Gio::SimpleAction.new(
        'set-number-mode',
        GLib::VariantType.new('s'),
        GLib::Variant.new('normal'),
      ).tap do |action|
        @number_mode_target = 'normal'
        action.signal_connect('activate') do |_, parameter|
          target = parameter.to_s
          dispatch do
            if target == @number_mode_target
              equation.number_mode = NumberMode::NORMAL
            elsif target == 'superscript'
              equation.number_mode = NumberMode::SUPERSCRIPT
              unless equation.has_selection
                equation.remove_trailing_spaces
              end
            elsif target == 'subscript'
              equation.number_mode = NumberMode::SUBSCRIPT
              unless equation.has_selection
                equation.remove_trailing_spaces
              end
            end
          end
        end
      end
    end

    def update_number_mode_state
      state = case equation.number_mode
              when NumberMode::SUPERSCRIPT then 'superscript'
              when NumberMode::SUBSCRIPT then 'subscript'
              else 'normal'
              end
      @number_mode_target = state
      set_number_mode_action.change_state(GLib::Variant.new(state))
    end
end
