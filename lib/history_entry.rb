# frozen_string_literal: true

require 'gtk4'

# HistoryEntry is one row in the history view: the equation that was solved
# on the left, an "=" separator, and the answer on the right. Clicking either
# label fires a callback so the window can re-insert it into the display.
#
# Ported from upstream's src/math-history.vala (the HistoryEntry class) and
# src/ui/history-entry.blp.
class HistoryEntry
  attr_reader :equation, :answer

  def initialize(equation, answer, serializer: nil, number: nil, on_equation_clicked: nil, on_answer_clicked: nil)
    @equation = equation
    @answer = answer
    @serializer = serializer
    @number = number
    @on_equation_clicked = on_equation_clicked || proc {}
    @on_answer_clicked = on_answer_clicked || proc {}
  end

  def build = root

  # Recomputes the answer text from the stored Number, the way redisplay()
  # does upstream when the display format or base changes. Restored rows
  # (loaded from saved strings, with no Number attached) are left alone.
  def redisplay(serializer)
    @number.then do |number|
      @answer = serializer.to_string(number)
      answer_label.text = @answer
      answer_label.tooltip_text = "‎#{@answer}"
    end
  end

  def root
    @root ||= Gtk::ListBoxRow.new.tap do |row|
      row.focus_on_click = false
      row.add_css_class('history-entry')
      row.child = grid
    end
  end

  def grid
    @grid ||= Gtk::Grid.new.tap do |grid|
      grid.margin_start = 12
      grid.margin_end = 16
      grid.column_homogeneous = true
      grid.attach(equation_label, 0, 0, 4, 1)
      grid.attach(equation_symbol, 4, 0, 1, 1)
      grid.attach(answer_label, 5, 0, 2, 1)
    end
  end

  def equation_label
    @equation_label ||= Gtk::Label.new.tap do |label|
      label.direction = :ltr
      label.text = @equation
      label.tooltip_text = "‎#{@equation}"
      label.ellipsize = :none
      label.xalign = 0.0
      label.yalign = 0.5
      label.wrap = true
      label.wrap_mode = :word_char
      label.add_css_class('equation-label')
      label.add_controller(equation_click_controller)
    end
  end

  def equation_symbol
    @equation_symbol ||= Gtk::Label.new('=').tap do |label|
      label.xalign = 0.5
      label.yalign = 0.5
      label.max_width_chars = 1
      label.add_css_class('equation-symbol')
      label.add_css_class('dimmed')
    end
  end

  def answer_label
    @answer_label ||= Gtk::Label.new.tap do |label|
      label.direction = :ltr
      label.text = @answer
      label.tooltip_text = "‎#{@answer}"
      label.ellipsize = :end
      label.xalign = 1.0
      label.yalign = 0.5
      label.max_width_chars = 12
      label.add_css_class('answer-label')
      label.add_controller(answer_click_controller)
    end
  end

  private

    def equation_click_controller
      @equation_click_controller ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.signal_connect('pressed') { |*| @on_equation_clicked.call(@equation) }
      end
    end

    def answer_click_controller
      @answer_click_controller ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.signal_connect('pressed') { |*| @on_answer_clicked.call(@answer) }
      end
    end
end
