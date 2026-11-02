# frozen_string_literal: true

require_relative 'number'
require_relative 'equation_parser'

# What went wrong while parsing or evaluating an expression.
#
# Ported from the ErrorCode enum in upstream's lib/equation.vala. The values
# keep upstream's order, because gcalccmd prints the number.
module ErrorCode
  NONE = 0
  INVALID = 1
  UNKNOWN_VARIABLE = 2
  UNKNOWN_FUNCTION = 3
  UNKNOWN_CONVERSION = 4
  UNKNOWN_UNIT = 5
  UNKNOWN_RATE = 6
  MP = 7
  TIMED_OUT = 8
  RESOURCE_LIMIT = 9

  NAMES = {
    NONE               => 'ErrorCode.NONE',
    INVALID            => 'ErrorCode.INVALID',
    UNKNOWN_VARIABLE   => 'ErrorCode.UNKNOWN_VARIABLE',
    UNKNOWN_FUNCTION   => 'ErrorCode.UNKNOWN_FUNCTION',
    UNKNOWN_CONVERSION => 'ErrorCode.UNKNOWN_CONVERSION',
    UNKNOWN_UNIT       => 'ErrorCode.UNKNOWN_UNIT',
    UNKNOWN_RATE       => 'ErrorCode.UNKNOWN_RATE',
    MP                 => 'ErrorCode.MP',
    TIMED_OUT          => 'ErrorCode.TIMED_OUT',
    RESOURCE_LIMIT     => 'ErrorCode.RESOURCE_LIMIT',
  }.freeze

  # Upstream's mp_error_code_to_string.
  def self.to_name(code) = NAMES.fetch(code, 'ErrorCode.NONE')
end

# Equation is one expression, with the settings — base, word length, angle
# units — it is to be read under, and the hooks a host fills in to supply
# variables, functions and units.
#
# Ported from upstream's lib/equation.vala. MathEquation subclasses it to hand
# the parser the window's variables and functions; UnitSolveEquation subclasses
# it to solve a unit's conversion formula.
#
# Upstream's parse writes its answer to five out parameters; here it answers
# the Parser::ParseResult the parser already builds.
class Equation
  SUB_DIGITS = %w[₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉].freeze
  SUPER_DIGITS = %w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze

  attr_accessor :base, :wordlen, :angle_units

  # The integer a run of subscript digits spells, or -1 when the text holds
  # anything else. Upstream's sub_atoi, including its answer of 0 for the
  # empty string — which is what makes a bare "log" count as a logₙ name.
  def self.sub_atoi(data)
    digits = data.to_s.each_char.map { |char| SUB_DIGITS.index(char) }
    if digits.any?(&:nil?)
      -1
    else
      digits.reduce(0) { |value, digit| (value * 10) + digit }
    end
  end

  # The integer a run of superscript digits spells, with an optional leading
  # superscript minus; zero when the text holds anything else. Upstream's
  # super_atoi.
  def self.super_atoi(data)
    sign = 1
    text = data.to_s
    if text.start_with?('⁻')
      sign = -1
      text = text[1..]
    end
    digits = text.each_char.map { |char| SUPER_DIGITS.index(char) }
    if digits.any?(&:nil?)
      0
    else
      sign * digits.reduce(0) { |value, digit| (value * 10) + digit }
    end
  end

  def initialize(expression)
    @expression = expression
    @base = 10
    @wordlen = 32
    @angle_units = AngleUnit::RADIANS
    @last_operand = nil
    @last_token = ''
  end

  def parse = parse_with_budget(nil)

  def parse_with_budget(budget)
    parser = EquationParser.new(self, @expression, budget)
    Number.clear_error
    result = parser.parse

    if result.error_code != ErrorCode::NONE
      blank_value(result)
    elsif Number.error
      number_error(result)
    else
      remember_last_operation(parser, budget)
      result
    end
  end

  # The hooks a host overrides. Upstream declares each one virtual on Equation.
  def variable_is_defined(_name) = false

  def get_variable(_name) = nil

  def unit_is_defined(_name) = false

  def literal_base_is_defined(_name) = false

  def set_variable(_name, _value) = nil

  def function_is_defined(_name) = false

  # Answers [value, from unit, to unit].
  def convert(x, x_units, z_units)
    UnitManager.default.convert_by_symbol(x, x_units, z_units)
  end

  # The operator and right operand of the last operation, which is what "="
  # repeats. Answers [token, operand].
  def last_operation = [@last_token, @last_operand]

  private

    def blank_value(result)
      Parser::ParseResult.new(
        nil,
        result.representation_base,
        result.error_code,
        result.error_token,
        result.error_start,
        result.error_end,
      )
    end

    def number_error(result)
      code = ErrorCode::MP
      if Number.error_code != ErrorCode::NONE
        code = Number.error_code
      end
      Parser::ParseResult.new(
        nil,
        result.representation_base,
        code,
        result.error_token,
        result.error_start,
        result.error_end,
      )
    end

    # Saving the repeat-operation state re-solves the right-hand side, which a
    # budgeted caller such as the search provider has no use for.
    def remember_last_operation(parser, budget)
      if budget.nil?
        @last_token, @last_operand = parser.last_operation
      else
        @last_token = ''
        @last_operand = nil
      end
    end
end

# The parser an Equation hands its expression to: it resolves the built-in
# constants itself and passes everything else back to the equation.
#
# Ported from upstream's EquationParser in lib/equation.vala.
class EquationParser < Parser
  BASE_NAMES = %w[hex hexadecimal dec decimal oct octal bin binary].freeze
  LITERAL_PREFIXES = %w[0x 0b 0o].freeze

  def initialize(equation, expression, budget = nil)
    super(
      expression,
equation.base,
equation.wordlen,
equation.angle_units,
budget
)
    @equation = equation
  end

  def variable_is_defined(name)
    if Parser.constants.key?(name)
      true
    else
      @equation.variable_is_defined(name)
    end
  end

  def get_variable(name)
    if Parser.constants.key?(name)
      Parser.constants[name]
    else
      @equation.get_variable(name)
    end
  end

  def set_variable(name, value)
    # The constants are reserved: e, π, τ and the rest cannot be assigned to.
    unless Parser.constants.key?(name)
      @equation.set_variable(name, value)
    end
  end

  def function_is_defined(name)
    if FunctionManager.default.function_defined?(name)
      true
    else
      @equation.function_is_defined(name)
    end
  end

  def unit_is_defined(name)
    if BASE_NAMES.include?(name)
      true
    elsif UnitManager.default.defined_unit(name)
      true
    else
      @equation.unit_is_defined(name)
    end
  end

  def currency_is_defined(name)
    manager = UnitManager.default
    found = manager.unit_by_symbol(name)
    !found.nil? && manager.category_of_unit(found.name)&.name == 'currency'
  end

  def currency_has_rate(name)
    !CurrencyManager.default.currency(name).nil?
  end

  def convert(x, x_units, z_units)
    @equation.convert(x, x_units, z_units)
  end

  def literal_base_is_defined(name)
    if LITERAL_PREFIXES.include?(name)
      true
    else
      @equation.literal_base_is_defined(name)
    end
  end
end
