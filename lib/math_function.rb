# frozen_string_literal: true

require_relative 'number'
require_relative 'equation_parser'

# A function the parser can call: either one of the built-ins or one the user
# defined in the display.
#
# Ported from upstream's lib/math-function.vala.
class MathFunction
  attr_reader :name, :arguments, :expression, :description

  def self.name_compare(first, second) = first.name <=> second.name

  def self.name_equal?(first, second) = first.name == second.name

  def initialize(function_name, arguments, expression, description)
    @name = function_name
    @arguments = arguments
    @expression = expression || ''
    @description = description || ''
  end

  def evaluate(args, root_parser = nil)
    result = FunctionParser.new(self, root_parser, args).parse
    if result.error_code == ErrorCode::NONE
      result.value
    else
      root_parser.set_error(
        result.error_code,
        result.error_token,
        result.error_start,
        result.error_end,
      )
      nil
    end
  end

  # Whether the definition parses and its name and argument names are legal.
  # Called before a user-defined function is saved.
  def validate(root_parser = nil)
    if !name_valid?(name) || arguments.any? { |argument| !name_valid?(argument) }
      root_parser.set_error(ErrorCode::INVALID)
      false
    else
      result = FunctionParser.new(self, root_parser, []).create_parse_tree
      if result.error_code == ErrorCode::NONE
        true
      else
        root_parser.set_error(
          result.error_code,
          result.error_token,
          result.error_start,
          result.error_end,
        )
        false
      end
    end
  end

  def custom_function? = true

  private

    def name_valid?(text) = !text.empty? && text.each_char.all? { |char| char.match?(/[[:alpha:]]/) }
end

# A parser for an expression nested inside another one — a function argument,
# or a function body — which falls back to the parser that opened it for every
# name it does not know itself.
#
# Ported from upstream's ExpressionParser in lib/math-function.vala.
class ExpressionParser < Parser
  def initialize(expression, root_parser = nil)
    super(
      expression,
      root_parser.number_base,
      root_parser.wordlen,
      root_parser.angle_units,
      root_parser.budget,
    )
    @root_parser = root_parser
  end

  def variable_is_defined(name)
    if super
      true
    else
      @root_parser.variable_is_defined(name)
    end
  end

  def get_variable(name)
    value = super
    if value
      value
    else
      @root_parser.get_variable(name)
    end
  end

  def function_is_defined(name)
    if super
      true
    else
      @root_parser.function_is_defined(name)
    end
  end

  def unit_is_defined(name) = @root_parser.unit_is_defined(name)

  def currency_is_defined(name) = @root_parser.currency_is_defined(name)

  def currency_has_rate(name) = @root_parser.currency_has_rate(name)

  def convert(x, x_units, z_units) = @root_parser.convert(x, x_units, z_units)

  def literal_base_is_defined(name) = @root_parser.literal_base_is_defined(name)
end

# The parser for a custom function's body, which resolves the function's
# argument names to the values it was called with.
#
# Ported from upstream's FunctionParser in lib/math-function.vala.
class FunctionParser < ExpressionParser
  def initialize(function, root_parser, parameters)
    super(function.expression, root_parser)
    @function = function
    @parameters = parameters
  end

  def variable_is_defined(name)
    if @function.arguments.include?(name)
      true
    else
      super
    end
  end

  def get_variable(name)
    index = @function.arguments.index(name)
    if index.nil?
      super
    else
      @parameters[index]
    end
  end
end

# One of the functions built into the calculator.
#
# Ported from upstream's BuiltInMathFunction in lib/math-function.vala; the
# dispatch table below is upstream's evaluate_built_in_function.
class BuiltInMathFunction < MathFunction
  def initialize(function_name, description, arguments = ['x'])
    super(
      function_name,
      arguments,
      '',
      description,
    )
  end

  def evaluate(args, root_parser = nil)
    self.class.evaluate_built_in(name, args, root_parser)
  end

  def custom_function? = false

  # Every built-in, keyed by its lowercased name. The inverse trigonometric
  # functions answer to both their superscript name and their "a" spelling.
  HANDLERS = {
    'sin'     => ->(args, parser) { args[0].sin(parser.angle_units) },
    'cos'     => ->(args, parser) { args[0].cos(parser.angle_units) },
    'tan'     => ->(args, parser) { args[0].tan(parser.angle_units) },
    'sin⁻¹'   => ->(args, parser) { args[0].asin(parser.angle_units) },
    'asin'    => ->(args, parser) { args[0].asin(parser.angle_units) },
    'cos⁻¹'   => ->(args, parser) { args[0].acos(parser.angle_units) },
    'acos'    => ->(args, parser) { args[0].acos(parser.angle_units) },
    'tan⁻¹'   => ->(args, parser) { args[0].atan(parser.angle_units) },
    'atan'    => ->(args, parser) { args[0].atan(parser.angle_units) },
    'sinh'    => ->(args, _parser) { args[0].sinh },
    'cosh'    => ->(args, _parser) { args[0].cosh },
    'tanh'    => ->(args, _parser) { args[0].tanh },
    'sinh⁻¹'  => ->(args, _parser) { args[0].asinh },
    'asinh'   => ->(args, _parser) { args[0].asinh },
    'cosh⁻¹'  => ->(args, _parser) { args[0].acosh },
    'acosh'   => ->(args, _parser) { args[0].acosh },
    'tanh⁻¹'  => ->(args, _parser) { args[0].atanh },
    'atanh'   => ->(args, _parser) { args[0].atanh },
    'conj'    => ->(args, _parser) { args[0].conjugate },
    'arg'     => ->(args, parser) { args[0].arg(parser.angle_units) },
    're'      => ->(args, _parser) { args[0].real_component },
    'im'      => ->(args, _parser) { args[0].imaginary_component },
    'twos'    => ->(args, parser) { args[0].twos_complement(parser.wordlen) },
    'bswap'   => ->(args, parser) { args[0].swap_endianness(parser.wordlen) },
    'mod'     => ->(args, _parser) { args[0].modulus_divide(args[1]) },
    'modexp'  => ->(args, parser) { args[0].modular_exponentiation(args[1], args[2], parser.budget) },
    'round'   => ->(args, _parser) { args[0].round },
    'floor'   => ->(args, _parser) { args[0].floor },
    'ceil'    => ->(args, _parser) { args[0].ceiling },
    'int'     => ->(args, _parser) { args[0].integer_component },
    'frac'    => ->(args, _parser) { args[0].fractional_component },
    'sum'     => ->(args, _parser) { Number.sum(args) },
    'sumsq'   => ->(args, _parser) { Number.sum_squares(args) },
    'average' => ->(args, _parser) { Number.sum(args).divide_integer(args.length) },
    'median'  => ->(args, _parser) { Number.median(args) },
    'min'     => ->(args, _parser) { Number.min(args) },
    'max'     => ->(args, _parser) { Number.max(args) },
    'stdev'   => ->(args, _parser) { Number.variance(args, true).sqrt },
    'stdevp'  => ->(args, _parser) { Number.variance(args, false).sqrt },
    'var'     => ->(args, _parser) { Number.variance(args, true) },
    'varp'    => ->(args, _parser) { Number.variance(args, false) },
    'log'     => ->(args, _parser) { args[0].logarithm(args.fetch(1, Number.integer(10))) },
    'ln'      => ->(args, _parser) { args[0].ln },
    'sqrt'    => ->(args, parser) { args[0].sqrt(parser.budget) },
    'abs'     => ->(args, _parser) { args[0].abs },
    'sgn'     => ->(args, _parser) { args[0].sgn },
    'ncr'     => ->(args, parser) { args[0].combination(args[1], parser.budget) },
    'npr'     => ->(args, parser) { args[0].permutation(args[1], parser.budget) },
    'gcd'     => ->(args, parser) { Number.gcd(args, parser.budget) },
    'lcm'     => ->(args, parser) { Number.lcm(args, parser.budget) },
    'cmp'     => ->(args, _parser) { args[0].kronecker_delta(args[1]) },
  }.freeze

  def self.evaluate_built_in(name, args, root_parser)
    handler = HANDLERS[name.downcase]
    if handler.nil? || args.empty?
      nil
    else
      handler.call(args, root_parser)
    end
  end
end
