# frozen_string_literal: true

require 'gtk4'

require_relative 'math_equation'
require_relative 'translations'

# MathDisplay is the equation editor: a scrolled text view bound to a
# MathEquation's buffer, with a status line and a backspace button below it.
#
# Ported from upstream's src/math-display.vala. Upstream templates a
# GtkSource.View inside the box; this port uses a plain Gtk::TextView bound
# to MathEquation#buffer (see lib/math_equation.rb and FINDINGS.md for why).
# House style keeps this as a plain Ruby object whose `build` returns the
# root widget, rather than a Gtk::Box subclass, the same shape
# gnome-contacts-rb uses for its own non-trivial widgets.
class MathDisplay
  include Gettext

  attr_reader :equation

  def initialize(equation)
    @equation = equation
    @equation.on_display_changed { update_status }
  end

  def build
    root.tap do |box|
      box.append(display_container)
      box.append(info_view)
    end
  end

  def root
    @root ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.add_css_class('display-container')
      box.vexpand = false
    end
  end

  def display_container
    @display_container ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.append(display_scrolled)
      box.append(backspace_button)
    end
  end

  def display_scrolled
    @display_scrolled ||= Gtk::ScrolledWindow.new.tap do |scrolled|
      scrolled.add_css_class('display-scrolled')
      scrolled.hscrollbar_policy = :external
      scrolled.vscrollbar_policy = :never
      scrolled.hexpand = true
      scrolled.child = source_view
    end
  end

  def source_view
    @source_view ||= Gtk::TextView.new(@equation.buffer).tap do |view|
      view.add_css_class('sourceview')
      view.wrap_mode = :none
      view.top_margin = 6
      view.bottom_margin = 6
      view.left_margin = 8
      view.right_margin = 8
      view.hexpand = true
    end
  end

  def backspace_button
    @backspace_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'edit-clear-symbolic'
      button.add_css_class('flat')
      button.tooltip_text = _('Clear Display')
      button.signal_connect('clicked') { @equation.backspace }
    end
  end

  def info_view
    @info_view ||= Gtk::Label.new.tap do |label|
      label.add_css_class('info-view')
      label.xalign = 0
      label.wrap = true
      label.margin_start = 8
      label.margin_end = 8
    end
  end

  # Called by MathWindow after every action that can change `equation.status`
  # (solve, clear, store) — see that class's `after_action`.
  def update_status
    info_view.text = @equation.status.to_s
    info_view.visible = !@equation.status.to_s.empty?
  end
end
