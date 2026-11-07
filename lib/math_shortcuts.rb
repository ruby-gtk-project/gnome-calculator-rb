# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'translations'

# MathShortcutsDialog shows the calculator's keyboard shortcuts, grouped
# into the same sections upstream uses.
#
# Ported from upstream's src/ui/math-shortcuts.blp, which builds an
# AdwShortcutsDialog out of AdwShortcutsItem rows. The Ruby bindings cannot
# construct Adwaita::ShortcutsItem: every keyword-argument call upstream's
# two constructor overloads accept (`title:`/`accelerator:` and
# `title:`/`action_name:`) is rejected by the introspection loader with
# "wrong arguments", even though the hash printed back matches a listed
# signature exactly — a binding bug, not a usage mistake. This port shows
# the same sections and shortcuts as a plain Adwaita::Dialog over a
# scrollable list of label/accelerator rows instead.
class MathShortcutsDialog
  include Gettext

  # [section title, [[label, accelerator], ...]]. Translated with `_` at
  # render time, not here — this is a plain class-level constant, not an
  # instance that has included Gettext.
  SECTIONS = [
    [
      'General',
      [
        ['Open a New Window', '<Ctrl>N'],
        ['Close Current Window', '<Ctrl>W'],
        ['Quit the Application', '<Ctrl>Q'],
        ['Show Help', 'F1'],
        ['Open Menu', 'F10'],
        ['Show Preferences', '<Ctrl>comma'],
        ['Keyboard Shortcuts', '<Ctrl>question'],
        ['Clear History', '<Ctrl>Delete'],
      ],
    ],
    [
      'Switching Modes',
      [
        ['Switch to Basic Mode', '<Ctrl>1'],
        ['Switch to Advanced Mode', '<Ctrl>2'],
        ['Switch to Financial Mode', '<Ctrl>3'],
        ['Switch to Programming Mode', '<Ctrl>4'],
        ['Switch to Keyboard Mode', '<Ctrl><Alt>k'],
        ['Switch to Conversion Mode', '<Ctrl>5'],
      ],
    ],
    [
      'Programming Mode',
      [
        ['Switch to Binary', '<Ctrl>B'],
        ['Switch to Octal', '<Ctrl>O'],
        ['Switch to Decimal', '<Ctrl>D'],
        ['Switch to Hexadecimal', '<Ctrl>H'],
      ],
    ],
    [
      'Keyboard Entry',
      [
        ['Multiply (×)', 'asterisk'],
        ['Divide (÷)', 'slash'],
        ['Square (²)', '<Ctrl>2'],
        ['Square Root (√)', '<Ctrl>R'],
        ['Inverse (⁻¹)', '<Ctrl>I'],
        ['Pi (π)', '<Ctrl>P'],
        ['Tau (τ)', '<Ctrl>T'],
        ['Degree (°)', '<Ctrl>apostrophe'],
        ['Enter Numbers in Scientific Format', '<Ctrl>E'],
        ['Enter Superscript Numbers', '<Ctrl>0...9'],
        ['Enter Subscript Numbers', '<Alt>0...9'],
        ['Enter Superscript Minus Sign', '<Ctrl>minus'],
      ],
    ],
    [
      'Equation',
      [
        ['Copy', '<Ctrl>C'],
        ['Paste', '<Ctrl>V'],
        ['Undo', '<Ctrl>Z'],
        ['Redo', '<Shift><Ctrl>Z'],
        ['Previous Equation', '<Alt>Left'],
        ['Next Equation', '<Alt>Right'],
        ['Clear Display', 'Escape'],
        ['Factorize', '<Ctrl>F'],
      ],
    ],
  ].freeze

  def build = root

  def root
    @root ||= Adwaita::Dialog.new.tap do |dialog|
      dialog.title = _('Keyboard Shortcuts')
      dialog.content_width = 480
      dialog.content_height = 560
      dialog.set_child(scrolled_window)
    end
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
      scrolled.vexpand = true
      scrolled.child = sections_box
    end
  end

  def sections_box
    @sections_box ||= Gtk::Box.new(:vertical, 18).tap do |box|
      box.margin_top = 18
      box.margin_bottom = 18
      box.margin_start = 18
      box.margin_end = 18
      SECTIONS.each { |title, shortcuts| box.append(section(title, shortcuts)) }
    end
  end

  private

    def section(title, shortcuts)
      Gtk::Box.new(:vertical, 6).tap do |box|
        box.append(Gtk::Label.new.tap do |label|
          label.label = "<b>#{_(title)}</b>"
          label.use_markup = true
          label.xalign = 0.0
        end)
        box.append(Gtk::ListBox.new.tap do |listbox|
          listbox.selection_mode = :none
          listbox.add_css_class('boxed-list')
          shortcuts.each { |label, accel| listbox.append(shortcut_row(label, accel)) }
        end)
      end
    end

    def shortcut_row(label, accelerator)
      Adwaita::ActionRow.new.tap do |row|
        row.title = _(label)
        row.add_suffix(Gtk::ShortcutLabel.new(accelerator))
      end
    end
end
