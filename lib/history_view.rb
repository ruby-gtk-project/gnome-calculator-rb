# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'history_entry'

# HistoryView is the scrollable list of past equation/answer pairs shown
# above the display. It tracks the serializer so a base or format change
# redisplays every stored answer, and it reports the equation or answer a
# row's labels were clicked on so MathWindow can re-insert that text.
#
# Ported from upstream's src/math-history.vala (the HistoryView class) and
# src/ui/history-view.blp.
class HistoryView
  attr_reader :rows

  def initialize(serializer, on_equation_clicked: nil, on_answer_clicked: nil)
    @serializer = serializer
    @on_equation_clicked = on_equation_clicked || proc {}
    @on_answer_clicked = on_answer_clicked || proc {}
    @last_equation = nil
    @rows = 0
    @entries = []
  end

  def build = root

  def root
    @root ||= Gtk::ScrolledWindow.new.tap do |scrolled|
      scrolled.vexpand = true
      scrolled.hscrollbar_policy = :never
      scrolled.add_css_class('history-view')
      scrolled.child = viewport
    end
  end

  def viewport
    @viewport ||= Gtk::Viewport.new(nil, nil).tap do |viewport|
      viewport.hexpand = true
      viewport.scroll_to_focus = true
      viewport.child = listbox
    end
  end

  def listbox
    @listbox ||= Gtk::ListBox.new.tap do |box|
      box.vexpand = true
      box.valign = :end
      box.selection_mode = :none
      box.tab_behavior = :item
    end
  end

  # Inserts a new solved equation. Mirrors upstream's insert_entry, which
  # drops the insert when the equation text has not changed since the last
  # one shown (so pressing "=" again on the same answer does not duplicate
  # the row).
  def insert_entry(equation, answer, serializer)
    unless @last_equation == equation
      append_entry(HistoryEntry.new(
        equation,
        serializer.to_string(answer),
        serializer: serializer,
        number: answer,
        on_equation_clicked: @on_equation_clicked,
        on_answer_clicked: @on_answer_clicked,
      ), equation)
    end
  end

  # Restores a row from saved strings (settings.rb's saved history), with no
  # live Number behind it to redisplay from.
  def load_entry(equation, answer)
    append_entry(HistoryEntry.new(
      equation,
      answer,
      on_equation_clicked: @on_equation_clicked,
      on_answer_clicked: @on_answer_clicked,
    ), equation)
  end

  def clear
    @last_equation = nil
    @rows = 0
    @entries = []
    while (child = listbox.get_row_at_index(0))
      listbox.remove(child)
    end
  end

  def set_serializer(serializer)
    @serializer = serializer
    @entries.each { |entry| entry.redisplay(serializer) }
  end

  def scroll_bottom
    adjustment = listbox.adjustment
    adjustment.then do |a|
      a.page_size = root.height_request / 3.0
      a.value = a.upper - a.page_size
    end
  end

  private

    def append_entry(entry, equation)
      listbox.insert(entry.build, -1)
      @entries << entry
      @last_equation = equation
      @rows += 1
      scroll_bottom
    end
end
