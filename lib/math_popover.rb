# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative 'translations'

# MathPopover is the shared chrome for the memory ("x") and function
# ("f(x)") popovers: a name entry with live validation, an add button that
# only turns sensitive once the name is valid, an error label that reveals
# under the entry, and the two helpers — make_item_row and
# make_category_row — that build an item's row and a drill-in category
# header the same way in both.
#
# Ported from upstream's abstract MathPopover<T> in src/math-popover.vala.
# Vala's generic subclassing — name_entry/add_button/error_label as abstract
# properties the GtkTemplate for each subclass overrides — has no Ruby
# equivalent, so this port takes the subclass's content widget and its name
# validator as constructor arguments instead of requiring template overrides.
class MathPopover < Gtk::Popover
  include Gettext

  RESERVED_VARIABLE_NAMES = %w[_ rand].freeze
  OPERATORS = %w[mod and nand or nor xor xnor nxor not in to].freeze

  attr_reader :equation, :name_entry, :add_button

  # `content` is the subclass's main widget (its Gtk::Stack of lists).
  # `validator` is called with the entry text and answers an error string, or
  # nil when the name is valid. `extra`, when given, is an additional widget
  # — the function popover's argument-count spinner — shown between the name
  # entry and the add button.
  def initialize(equation, content, validator:, extra: nil)
    super()
    @equation = equation
    @validator = validator
    @extra = extra
    self.child = chrome(content)
    name_entry.signal_connect('changed') { on_name_entry_changed }
    signal_connect('closed') { name_entry.text = '' }
  end

  # The row for one item: its (markup-bearing) text, an edit button when
  # `editable` is given a proc, and a delete button when `deletable` is.
  # Ported from upstream's make_item_row.
  def make_item_row(text, editable: nil, deletable: nil)
    Gtk::Box.new(:horizontal, 2).tap do |hbox|
      hbox.halign = :fill
      hbox.append(item_label(text))
      if editable
        hbox.append(row_button('document-edit-symbolic', _('Edit'), &editable))
      end
      if deletable
        hbox.append(row_button('user-trash-symbolic', _('Delete'), &deletable))
      end
    end
  end

  # A category header row — name plus a forward arrow — and the (empty)
  # submenu ListBox it drills into, whose first row is a "back" row.
  # Ported from upstream's make_category_row.
  def make_category_row(name)
    submenu = Gtk::ListBox.new.tap do |box|
      box.selection_mode = :none
      box.add_css_class('category-list')
      box.insert(back_row(name), -1)
    end
    category_row = Gtk::Box.new(:horizontal, 0).tap do |box|
      box.append(Gtk::Label.new(name))
      box.append(Gtk::Image.new(icon_name: 'go-next-symbolic').tap do |image|
        image.halign = :end
        image.hexpand = true
        image.add_css_class('forward-arrow')
      end)
    end
    [category_row, submenu]
  end

  protected

    def close_popover = popdown

    def clear_listbox(listbox)
      while (row = listbox.get_row_at_index(0))
        listbox.remove(row)
      end
    end

  private

    def back_row(name)
      Gtk::CenterBox.new.tap do |center|
        center.add_css_class('back-button')
        center.center_widget = Gtk::Label.new(name)
        center.start_widget = Gtk::Image.new(icon_name: 'go-previous-symbolic').tap do |image|
          image.add_css_class('back-arrow')
        end
      end
    end

    def item_label(text)
      Gtk::Label.new.tap do |label|
        label.label = "‎#{text}"
        label.use_markup = true
        label.xalign = 0
        label.hexpand = true
        label.wrap = true
        label.wrap_mode = :word_char
        label.margin_start = 10
        label.margin_end = 8
        label.margin_top = 4
        label.margin_bottom = 4
      end
    end

    def row_button(icon_name, tooltip)
      Gtk::Button.new.tap do |button|
        button.icon_name = icon_name
        button.tooltip_text = tooltip
        button.has_frame = false
        button.halign = :end
        button.signal_connect('clicked') { yield }
      end
    end

    def chrome(content)
      Gtk::Box.new(:vertical, 6).tap do |box|
        box.margin_top = 6
        box.margin_bottom = 6
        box.margin_start = 6
        box.margin_end = 6
        box.width_request = 260
        box.append(content)
        box.append(Gtk::Separator.new(:horizontal))
        box.append(entry_row)
        box.append(error_revealer)
      end
    end

    def entry_row
      @entry_row ||= Gtk::Box.new(:horizontal, 4).tap do |box|
        box.append(name_entry)
        if @extra
          box.append(@extra)
        end
        box.append(add_button)
      end
    end

    def name_entry
      @name_entry ||= Gtk::Entry.new.tap do |entry|
        entry.hexpand = true
        entry.placeholder_text = _('Name')
        entry.enable_undo = false
      end
    end

    def add_button
      @add_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'list-add-symbolic'
        button.tooltip_text = _('Add')
        button.sensitive = false
      end
    end

    def error_label
      @error_label ||= Gtk::Label.new.tap do |label|
        label.add_css_class('error')
        label.wrap = true
        label.xalign = 0
      end
    end

    def error_revealer
      @error_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.child = error_label
        revealer.reveal_child = false
      end
    end

    # Mirrors upstream's name_entry_changed_cb: spaces become underscores as
    # they are typed, then the corrected text is validated.
    def on_name_entry_changed
      text = name_entry.text
      if text.include?(' ')
        cursor = name_entry.position
        name_entry.text = text.gsub(' ', '_')
        name_entry.position = cursor
      else
        update_entry_state(text.empty? ? nil : @validator.call(text))
      end
    end

    def update_entry_state(error)
      if error
        name_entry.add_css_class('error')
      else
        name_entry.remove_css_class('error')
      end
      add_button.sensitive = !name_entry.text.empty? && error.nil?
      error_label.label = error.to_s
      error_revealer.reveal_child = !error.nil?
    end
end
