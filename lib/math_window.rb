# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'math_equation'
require_relative 'math_display'
require_relative 'math_buttons'
require_relative 'history_view'
require_relative 'math_shortcuts'
require_relative 'translations'

# MathWindow is the calculator's main window: a header bar over the equation
# display and the mode-switchable button panel, with keyboard accelerators
# for the digits, operators and Enter/Escape/Backspace that the buttons
# also drive.
#
# Ported from upstream's src/math-window.vala. Upstream's MathWindow also
# owns the converter pane; this round ports the equation display, history
# and the Basic/Advanced button panels behind MathButtons (see the port's
# component-parity report for the rest), so the window's mode menu offers
# only those two.
class MathWindow
  include Gettext

  attr_reader :equation

  def initialize(app)
    @app = app
    @equation = MathEquation.new
    @display = MathDisplay.new(@equation)
    @buttons = MathButtons.new(@equation, after_action: -> { @display.update_status })
    @buttons.mode = ButtonMode::BASIC
    @history = HistoryView.new(
      @equation.serializer,
      on_equation_clicked: ->(text) { @equation.set(text) },
      on_answer_clicked: ->(text) { @equation.insert(text) },
    )
    @equation.on_history { |text, number, _number_base, _representation_base| @history.insert_entry(text, number, @equation.serializer) }
  end

  def build
    window.tap do |win|
      win.content = toolbar_view
      win.add_controller(key_controller)
      win.insert_action_group('win', window_action_group)
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
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.pack_start(mode_button)
      bar.pack_end(shortcuts_button)
    end
  end

  # Upstream's "Mode Selection" menu button on the header bar, driving the
  # window-level `win.mode` action from src/math-window.vala — narrowed to
  # Basic and Advanced, the two modes this round ports.
  def mode_button
    @mode_button ||= Gtk::MenuButton.new.tap do |button|
      button.label = _('Mode Selection')
      button.tooltip_text = _('Mode Selection')
      button.menu_model = mode_menu
    end
  end

  def mode_menu
    @mode_menu ||= Gio::Menu.new.tap do |menu|
      menu.append(_('_Basic'), 'win.mode::basic')
      menu.append(_('_Advanced'), 'win.mode::advanced')
    end
  end

  def window_action_group
    @window_action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      group.add_action(mode_action)
    end
  end

  def mode_action
    @mode_action ||= Gio::SimpleAction.new(
      'mode',
      GLib::VariantType.new('s'),
      GLib::Variant.new('basic'),
    ).tap do |action|
      action.signal_connect('activate') do |_, parameter|
        action.change_state(parameter)
        @buttons.mode = parameter.to_s.to_sym
      end
    end
  end

  def shortcuts_button
    @shortcuts_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'preferences-desktop-keyboard-shortcuts-symbolic'
      button.tooltip_text = _('Keyboard Shortcuts')
      button.signal_connect('clicked') { MathShortcutsDialog.new.build.present(window) }
    end
  end

  def body
    @body ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.append(@history.build)
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
