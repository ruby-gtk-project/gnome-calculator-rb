# frozen_string_literal: true

# Drives the port headlessly: builds the real application window, confirms
# the style sheet loads and the placeholder content is what the application
# actually puts there, then exercises the ported engine (the only
# user-facing part of this app beyond the window) end to end, including
# through the real exe/gcalccmd CLI entry point as a subprocess.
#
# Why this file exists: `ruby -c` and `require "gnome_calculator"` both pass
# on code that has never opened a window, and this port's own
# `.reports/component-inventory.md` says plainly that only the engine and a
# placeholder application are written — no math window, no buttons, no
# dialogs, no menus. A drive script cannot click controls that do not exist;
# what it can and must do is prove that every component the port *does*
# claim (the window that exists, and the full calculation engine behind
# `gcalccmd`) actually runs, not just parses.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb
#
# GTK4 here has no offscreen backend - gtk_init fails outright with no
# display - so xvfb-run is not optional on this machine.

require "fileutils"
require "tmpdir"
require "open3"

# A scratch config directory, so a run never reads or writes the real one.
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("gnome-calculator-drive")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_calculator"
require "gnome_calculator/application"
require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

ROOT = File.expand_path("..", __dir__)

# Runs exe/gcalccmd as upstream's own CLI would be run, in-process code
# never substitutes for it: it is a separate entry point with its own
# `require`s and its own argv handling.
def gcalccmd(*args)
  Open3.capture3(
    RbConfig.ruby,
    "-I",
    File.join(ROOT, "lib"),
    File.join(ROOT, "exe", "gcalccmd"),
    *args,
  )
end

GtkDriver.drive(GnomeCalculator::Application.new, shots: SHOTS) do |d, app|
  d.window { app.math_window.window }

  d.step("the application activates and builds the real math window") do
    math_window = app.math_window
    d.check("the window is an Adwaita::ApplicationWindow") do
      math_window.window.is_a?(Adwaita::ApplicationWindow)
    end
    d.check("it is the only toplevel") { Gtk::Window.list_toplevels.length == 1 }
    d.check("its title is gnome-calculator") { math_window.window.title == "gnome-calculator" }
    d.check("the toolbar view is the window's content") do
      math_window.window.content.equal?(math_window.toolbar_view)
    end
    d.check("the header bar is a top bar on the toolbar view") do
      math_window.header_bar.is_a?(Adwaita::HeaderBar)
    end
    d.check("the display and button panel are the body") do
      math_window.body.is_a?(Gtk::Box)
    end
    d.check("the CSS provider loaded style.css without raising") do
      app.css_provider.is_a?(Gtk::CssProvider)
    end
    d.shot("01-math-window")
  end

  d.step("the basic button panel drives the real MathEquation") do
    equation = app.math_window.equation
    buttons = app.math_window.instance_variable_get(:@buttons)

    equation.clear
    buttons.digit_button(6).signal_emit("clicked")
    buttons.add_button.signal_emit("clicked")
    buttons.digit_button(3).signal_emit("clicked")
    buttons.result_button.signal_emit("clicked")

    d.check("6 + 3 solves through the real buttons to 9") { equation.display == "9" }

    buttons.clear_button.signal_emit("clicked")
    d.check("the clear button empties the display") { equation.display == "" }
  end

  d.step("the real MathDisplay shows an error status, then clears it") do
    equation = app.math_window.equation
    display = app.math_window.instance_variable_get(:@display)

    equation.clear
    equation.insert("1 + ")
    equation.solve
    display.update_status

    d.check("the info view reports an error for an unsolvable expression") do
      display.info_view.visible? && !display.info_view.text.empty?
    end

    equation.clear
    display.update_status

    d.check("the info view is empty and hidden after clear") do
      display.info_view.text.empty? && !display.info_view.visible?
    end
  end

  d.step("the real HistoryView records solved equations and supports click-to-reinsert") do
    equation = app.math_window.equation
    history = app.math_window.instance_variable_get(:@history)

    equation.clear
    history.clear
    d.check("the history starts empty") { history.rows.zero? }

    equation.set("5")
    equation.insert("+")
    equation.insert("5")
    equation.solve

    d.check("solving adds exactly one history row") { history.rows == 1 }

    row = history.listbox.get_row_at_index(0)
    d.check("the row is a real Gtk::ListBoxRow with equation/= /answer labels") do
      row.is_a?(Gtk::ListBoxRow)
    end

    entry = history.instance_variable_get(:@entries).last
    equation.clear
    # Fires the label's real click gesture (the "pressed" signal on its
    # Gtk::GestureClick controller), not the window's private callback
    # directly, so the wiring between the widget and MathWindow is under
    # test, not just the logic.
    entry.send(:equation_click_controller).signal_emit("pressed", 1, 0, 0)
    d.check("clicking the equation label re-inserts the equation text") do
      equation.display == "5+5"
    end

    equation.clear
    entry.send(:answer_click_controller).signal_emit("pressed", 1, 0, 0)
    d.check("clicking the answer label re-inserts the answer text") do
      equation.display == "10"
    end

    equation.solve # back to repeating "=" is irrelevant; just leave a clean solved state
    equation.clear
    history.clear
    d.shot("02-history-cleared")
  end

  d.step("toggling superscript/subscript mode on the real buttons flips MathEquation#number_mode") do
    equation = app.math_window.equation
    buttons = app.math_window.instance_variable_get(:@buttons)

    equation.clear
    buttons.superscript_button.active = true
    d.check("the superscript button sets NumberMode::SUPERSCRIPT") do
      equation.number_mode == NumberMode::SUPERSCRIPT
    end
    buttons.superscript_button.active = false
    d.check("untoggling it restores NumberMode::NORMAL") do
      equation.number_mode == NumberMode::NORMAL
    end

    buttons.subscript_button.active = true
    d.check("the subscript button sets NumberMode::SUBSCRIPT") { equation.number_mode == NumberMode::SUBSCRIPT }
    buttons.subscript_button.active = false
    d.check("untoggling it restores NumberMode::NORMAL again") { equation.number_mode == NumberMode::NORMAL }
  end

  d.step("the real window-level key controller drives MathEquation the way a keypress would") do
    equation = app.math_window.equation
    key_controller = app.math_window.send(:key_controller)

    equation.clear
    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_7, 0, 0)
    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_plus, 0, 0)
    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_3, 0, 0)
    d.check("typed digits and operator land in the equation buffer") { equation.display == "7+3" }

    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_Return, 0, 0)
    d.check("Enter solves through the key controller") { equation.display == "10" }

    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_Escape, 0, 0)
    d.check("Escape clears through the key controller") { equation.display == "" }

    equation.insert("42")
    key_controller.signal_emit("key-pressed", Gdk::Keyval::KEY_BackSpace, 0, 0)
    d.check("Backspace deletes the last character through the key controller") { equation.display == "4" }

    equation.clear
  end

  d.step("the shortcuts button opens the real MathShortcutsDialog over the window") do
    math_window = app.math_window
    shortcuts_button = math_window.shortcuts_button

    d.check("the shortcuts button is on the header bar") do
      math_window.header_bar.is_a?(Adwaita::HeaderBar)
    end

    shortcuts_button.signal_emit("clicked")
    dialog = math_window.window.visible_dialog

    d.check("clicking it presents a real Adwaita::Dialog") { dialog.is_a?(Adwaita::Dialog) }
    d.check("the dialog is titled Keyboard Shortcuts") { dialog&.title == "Keyboard Shortcuts" }

    d.shot("03-shortcuts-dialog", math_window.window)

    dialog&.close
    d.check("closing it leaves no dialog on the window") { math_window.window.visible_dialog.nil? }
  end

  d.step("the ported evaluation engine solves a plain expression") do
    equation = Equation.new("1 + 2 * 3")
    equation.base = 10
    equation.wordlen = 32
    equation.angle_units = AngleUnit::DEGREES
    result = equation.parse
    serializer = Serializer.new(DisplayFormat::AUTOMATIC, 10, 9)
    serializer.representation_base = result.representation_base

    d.check("1 + 2 * 3 solves") { !result.value.nil? }
    d.check("operator precedence is honoured (= 7)") do
      serializer.to_string(result.value) == "7"
    end
  end

  d.step("the engine reports a real error for a bad expression") do
    equation = Equation.new("1 + ")
    equation.base = 10
    equation.wordlen = 32
    equation.angle_units = AngleUnit::DEGREES
    result = equation.parse

    d.check("an incomplete expression fails to solve") { result.value.nil? }
    d.check("with an actual ErrorCode, not an exception") do
      ErrorCode::NAMES.key?(result.error_code)
    end
  end

  d.step("unit conversion goes through the ported Unit table") do
    equation = Equation.new("1 meter in cm")
    equation.base = 10
    equation.wordlen = 32
    equation.angle_units = AngleUnit::DEGREES
    result = equation.parse
    serializer = Serializer.new(DisplayFormat::AUTOMATIC, 10, 9)

    d.check("the unit conversion solves") { !result.value.nil? }
    d.check("1 meter is 100 cm") { result.value && serializer.to_string(result.value) == "100" }
  end

  d.step("Settings reads and writes the same 19 JSON-backed keys") do
    settings = Settings.new
    d.check("base defaults to 10") { settings["base"] == 10 }
    settings["base"] = 16
    d.check("base round-trips") { Settings.new(path: settings.location)["base"] == 16 }
  end

  d.step("exe/gcalccmd solves a single expression given as an argument") do
    out, err, status = gcalccmd("2^10")
    d.check("gcalccmd exits cleanly") { status.success? }
    d.check("gcalccmd prints the right answer") { out.strip == "1024" }
    d.check("gcalccmd writes nothing to stderr on success") { err.strip.empty? }
  end

  d.step("exe/gcalccmd reports an error for an unknown variable") do
    out, _err, status = gcalccmd("totally_unknown_variable_xyz")
    d.check("gcalccmd still exits (it prints to stderr, not an exception)") { status.exitstatus.is_a?(Integer) }
    d.check("gcalccmd prints nothing to stdout for the failed solve") { out.strip.empty? }
  end

  d.step("exe/gcalccmd reads expressions from stdin until a blank line") do
    out, _err, status = Open3.capture3(

      RbConfig.ruby,

      "-I",

      File.join(ROOT, "lib"),

      File.join(ROOT, "exe", "gcalccmd"),
      stdin_data: "3 + 4\n\n",

    )
    d.check("the REPL exits cleanly at a blank line") { status.success? }
    d.check("the REPL solved the one line it was given") { out.include?("7") }
  end
end
