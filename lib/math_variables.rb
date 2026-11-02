# frozen_string_literal: true

require 'fileutils'

require_relative 'number'
require_relative 'serializer'

# MathVariables owns the named values the user has stored, loading them from
# and saving them to `registers` under the user's data directory.
#
# Ported from upstream's lib/math-variables.vala. Upstream's variable_added,
# variable_edited and variable_deleted signals become the on_variable_*
# callbacks below.
class MathVariables
  def initialize(path: nil)
    @registers = {}
    @file_name = path || default_path
    @serializer = Serializer.new(DisplayFormat::SCIENTIFIC, 10, 50)
    @serializer.radix = '.'
    @added_handlers = []
    @edited_handlers = []
    @deleted_handlers = []
    load_registers
  end

  def on_variable_added(&block) = @added_handlers << block

  def on_variable_edited(&block) = @edited_handlers << block

  def on_variable_deleted(&block) = @deleted_handlers << block

  # Every variable name. Upstream's array_sort_string sorts descending, and the
  # variable list is built from that order, so it is kept.
  def names = @registers.keys.sort.reverse

  # Every variable name starting with `text`, for the completion popup.
  def variables_eligible_for_autocompletion(text)
    if text.empty?
      []
    else
      names.select { |name| name.start_with?(text) }
    end
  end

  def []=(name, value)
    editing = @registers.key?(name)
    @registers[name] = value
    save
    if editing
      @edited_handlers.each { |handler| handler.call(name, value) }
    else
      @added_handlers.each { |handler| handler.call(name, value) }
    end
    value
  end

  def [](name) = @registers[name]

  def delete(name)
    @registers.delete(name)
    save
    @deleted_handlers.each { |handler| handler.call(name) }
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
        'gnome-calculator',
        'registers',
      )
    end

    def load_registers
      if File.exist?(@file_name)
        @registers.clear
        File.read(@file_name).split("\n").each { |line| load_register(line) }
      end
    end

    # One `name=value` line. The value is written in scientific notation, so
    # the mantissa and the superscript exponent are parsed separately.
    def load_register(line)
      if line.include?('=')
        name, text = line.split('=', 2).map(&:strip)
        mantissa, exponent = text.split('×10', 2)
        value = Number.from_string(mantissa)
        if value
          @registers[name] = scaled(value, exponent)
        end
      end
    end

    def scaled(value, exponent)
      if exponent.nil?
        value
      else
        value.multiply(Number.integer(10).xpowy_integer(Equation.super_atoi(exponent)))
      end
    end

    def save
      data = @registers.map { |name, value| format("%s=%s\n", name, @serializer.to_string(value)) }.join
      FileUtils.mkdir_p(File.dirname(@file_name), mode: 0o700)
      File.write(@file_name, data)
    end
end
