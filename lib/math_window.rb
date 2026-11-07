# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'math_equation'
require_relative 'math_display'
require_relative 'basic_button_panel'
require_relative 'translations'

# MathWindow is the calculator's main window: a header bar over the equation
# display and the basic button panel, with keyboard accelerators for the
# digits, operators and Enter/Escape/Backspace that the buttons also drive.
#
# Ported from upstream's src/math-window.vala. Upstream's MathWindow also
# owns the mode-switching MathButtons stack (basic/advanced/financial/
# programming/keyboard), the converter pane and the history view; this round
# ports only the basic button panel (see the port's component-parity report
# for the rest), so the window shows that panel directly rather than a
# switchable stack.
class MathWindow
  attr_reader :equation

  def initialize(app)
    @app = app
    @equation = MathEquation.new
    @display = MathDisplay.new(@equation)
    @buttons = BasicButtonPanel.new(@equation, after_action: -> { @display.update_status })
  end

  def build
    window.tap do |win|
      win.content = toolbar_view
      win.add_controller(key_controller)
    end
  end

  def window
    @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
      win.title = 'gnome-calculator'
      win.set_default_size(360, 500)
    end
  end

  def toolbar_view
    @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
      view.add_top_bar(header_bar)
      view.content = body
    end
  end

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new
  end

  def body
    @body ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.append(@display.build)
      box.append(button_panel)
    end
  end

  def button_panel
    @button_panel ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.add_css_class('math-buttons')
      box.vexpand = true
      box.append(@buttons.build)
    end
  end

  private

    # Mirrors the subset of upstream's window-level accelerators
    # (src/math-window.vala's key handling) a basic-mode user meets: digits,
    # the four operators, Enter to solve, Escape to clear, Backspace to
    # delete, and the radix point.
    def key_controller
      @key_controller ||= Gtk::EventControllerKey.new.tap do |controller|
        controller.signal_connect('key-pressed') do |_c, keyval, _keycode, _state|
          handle_key(keyval)
        end
      end
    end

    def handle_key(keyval)
      char = Gdk::Keyval.to_unicode(keyval)&.chr(Encoding::UTF_8)
      handled = true
      case keyval
      when Gdk::Keyval::KEY_Return, Gdk::Keyval::KEY_KP_Enter, Gdk::Keyval::KEY_equal
        @equation.solve
      when Gdk::Keyval::KEY_Escape
        @equation.clear
      when Gdk::Keyval::KEY_BackSpace
        @equation.backspace
      when Gdk::Keyval::KEY_Delete
        @equation.delete_next
      when Gdk::Keyval::KEY_period, Gdk::Keyval::KEY_KP_Decimal
        @equation.insert_numeric_point
      else
        if char && char =~ /[0-9]/
          @equation.insert_digit(char.to_i)
        elsif char && '+-*/%()'.include?(char)
          @equation.insert({ '*' => '×', '/' => '÷', '-' => '−' }.fetch(char, char))
        else
          handled = false
        end
      end
      @display.update_status
      handled
    end
end
