# frozen_string_literal: true

require_relative 'number'
require_relative 'equation_lexer'

# Which way operators of equal precedence bind.
#
# Ported from the Associativity enum in upstream's lib/equation-parser.vala.
module Associativity
  LEFT = :left
  RIGHT = :right
end

# Operator precedence, as upstream's Precedence enum: the numbers matter, not
# just their order, because a node's precedence is its level plus
# `depth_level × DEPTH`, which is what stops a node from jumping out of its
# bracket depth.
module Precedence
  UNKNOWN = 0
  # A conversion node; only a conversion may sit above TOP at the same depth.
  CONVERT = 0
  # The unit of a conversion.
  UNIT = 1
  TOP = 2
  ADD_SUBTRACT = 3
  MULTIPLY = 4
  # MOD and DIVIDE must share a precedence.
  MOD = 5
  DIVIDE = 5
  NOT = 6
  FUNCTION = 7
  BOOLEAN = 8
  SHIFT = 8
  PERCENTAGE = 9
  # UNARY_MINUS, ROOT and POWER must share a precedence.
  UNARY_MINUS = 10
  POWER = 10
  ROOT = 10
  FACTORIAL = 11
  NUMBER_VARIABLE = 12
  # Always the largest: it is the step between bracket depths.
  DEPTH = 13
end

# A named constant offered by the function and variable popovers.
#
# Ported from the Constant and ConstantCategory structs in upstream's
# lib/equation-parser.vala.
Constant = Struct.new(:name, :symbol, :number)
ConstantCategory = Struct.new(:name, :constants)

# A node of the parse tree.
#
# Ported from upstream's ParseNode in lib/equation-parser.vala. The tree is
# built by precedence comparison rather than by recursive descent over the
# grammar, so each node carries its own precedence and associativity.
class ParseNode
  attr_accessor :parser, :parent, :left, :right, :token_list, :precedence, :associativity, :value

  def initialize(parser, token, precedence, associativity, value = nil)
    @parser = parser
    @token_list = [token]
    @precedence = precedence
    @associativity = associativity
    @value = value
    @parent = nil
    @left = nil
    @right = nil
  end

  def self.with_list(parser, token_list, precedence, associativity, value = nil)
    new(
      parser,
      nil,
      precedence,
      associativity,
      value,
    ).tap do |node|
      node.token_list = token_list.dup
    end
  end

  def token = @token_list.first

  def first_token = @token_list.first

  def last_token = @token_list.last

  # The start of the leftmost token under this node, which is where an error
  # highlight begins. Nodes the parser synthesises carry no token, hence the
  # zero.
  def leftmost_start
    node = self
    while node.left
      node = node.left
    end
    if node.first_token
      node.first_token.start_index
    else
      0
    end
  end

  def rightmost_end
    node = self
    while node.right
      node = node.right
    end
    if node.last_token
      node.last_token.end_index
    else
      0
    end
  end

  def solve
    if @parser.check_budget
      nil
    end
  end

  protected

    # Upstream's post-solve error check, repeated in every node: MPFR's sticky
    # flags are drained and any Number error is reported against the span of
    # the operands.
    def report_number_error(from, to)
      Number.check_flags
      if Number.error
        @parser.set_number_error(from.leftmost_start, to.rightmost_end)
      end
    end
end

# A node with only a right operand.
class RNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    else
      operand = @right.solve
      if operand.nil? || !@parser.check_budget
        nil
      else
        solve_r(operand).tap { report_number_error(@right, @right) }
      end
    end
  end
end

# A node with a left and a right operand.
class LRNode < ParseNode
  def initialize(parser, token, precedence, associativity, value = nil)
    super
    @repeatable = false
  end

  def repeatable? = @repeatable

  def solve
    if !@parser.check_budget
      nil
    else
      l = @left.solve
      if !@parser.check_budget
        nil
      else
        solve_operands(l, @right.solve)
      end
    end
  end

  private

    def solve_operands(l, r)
      if l.nil? || r.nil? || !@parser.check_budget
        nil
      else
        solve_lr(l, r).tap { report_number_error(@left, @right) }
      end
    end
end

# A literal.
class ConstantNode < ParseNode
  def solve
    if @parser.check_budget
      Number.from_string(token.text, @parser.number_base)
    end
  end
end

# `name = expression`.
class AssignNode < RNode
  def solve_r(r)
    @parser.set_variable(@left.token.text, r)
    r
  end
end

# `name (args) = expression`, which defines a custom function.
class AssignFunctionNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    elsif @left.nil? || @right.nil? || @left.left.nil? || @left.right.nil?
      nil
    else
      define_function
    end
  end

  private

    def define_function
      manager = FunctionManager.default
      added = manager.add_function_with_properties(
        @left.left.value,
        @left.right.value,
        @right.value,
        @parser,
      )
      if added
        Number.integer(0)
      end
    end
end

# A bare name: the left side of an assignment, or the unit of a conversion.
class NameNode < ParseNode
end

class VariableNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    else
      answer = @parser.get_variable(token.text)
      if answer
        answer
      else
        product_of_letters
      end
    end
  end

  private

    # A name of more than one character that is not a variable is read as a
    # product of single-letter variables, so "xy" is x × y.
    def product_of_letters
      value = Number.integer(1)
      failed = false
      token.text.each_char do |char|
        unless failed
          term = @parser.get_variable(char)
          if term.nil? || !@parser.check_budget
            @parser.set_error(
              ErrorCode::UNKNOWN_VARIABLE,
              token.text,
              first_token.start_index,
              last_token.end_index,
            )
            failed = true
          else
            value = value.multiply(term)
          end
        end
      end
      if failed
        nil
      else
        value
      end
    end
end

# A variable carrying a superscript exponent, e.g. x².
class VariableWithPowerNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    else
      power = Equation.super_atoi(@value)
      @value = nil
      answer = @parser.get_variable(token.text)
      if answer
        # A superscripted variable bypasses XPowYIntegerNode, so the budget's
        # exponent limits have to be enforced here.
        answer.xpowy_integer(power, @parser.budget)
      else
        product_of_letters(power)
      end
    end
  end

  private

    def product_of_letters(power)
      value = Number.integer(1)
      failed = false
      characters = token.text.each_char.to_a
      characters.each_with_index do |char, index|
        unless failed
          term = @parser.get_variable(char)
          if term.nil? || !@parser.check_budget
            @parser.set_error(
              ErrorCode::UNKNOWN_VARIABLE,
              token.text,
              first_token.start_index,
              last_token.end_index,
            )
            failed = true
          else
            # Only the last term takes the exponent.
            if index == characters.length - 1
              term = term.xpowy_integer(power, @parser.budget)
            end
            value = value.multiply(term)
          end
        end
      end
      if failed
        nil
      else
        value.tap { Number.check_flags }
      end
    end
end

class FunctionNameNode < NameNode
end

class FunctionArgumentsNode < NameNode
end

class FunctionDescriptionNode < NameNode
end

# A function call. The arguments are re-parsed one at a time, so a nested
# expression inside an argument gets the full grammar.
class FunctionNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    elsif @right.nil? || @left.nil? || @left.value.nil?
      @parser.set_error(ErrorCode::UNKNOWN_FUNCTION)
      nil
    else
      solve_call
    end
  end

  private

    def solve_call
      name, power = resolve_name
      args = collect_arguments
      if args.nil?
        nil
      elsif args.empty?
        @parser.set_error(
          ErrorCode::MP,
          format('Function “%s” is missing arguments', name),
          @left.token.start_index,
          @left.token.end_index,
        )
        nil
      else
        evaluate(name, args, power)
      end
    end

    # A negative superscript on a function name asks for the inverse, if one
    # is defined: sin⁻¹ rather than (sin x)⁻¹.
    def resolve_name
      name = @left.value
      power = 1
      if @value
        power = Equation.super_atoi(@value)
      end
      if power.negative? && FunctionManager.default.function_defined?("#{name}⁻¹")
        ["#{name}⁻¹", -power]
      else
        [name, power]
      end
    end

    def evaluate(name, args, power)
      answer = FunctionManager.default.evaluate_function(name, args, @parser)
      if answer
        answer = answer.xpowy_integer(power, @parser.budget)
      end
      Number.check_flags
      if Number.error
        @parser.set_number_error(@right.leftmost_start, @right.rightmost_end)
      end
      answer
    end

    def collect_arguments
      if @right.is_a?(FunctionArgumentsNode)
        parse_argument_list(@right.value)
      else
        answer = @right.solve
        if answer
          [answer]
        end
      end
    end

    # Splits on the semicolons that separate this call's arguments, leaving the
    # semicolons of a nested call alone.
    def parse_argument_list(argument_list)
      args = []
      failed = false
      split_arguments(argument_list).each do |piece|
        unless failed
          value = parse_argument(piece)
          if value.nil?
            failed = true
          else
            args << value
          end
        end
      end
      if failed
        nil
      else
        args
      end
    end

    def split_arguments(argument_list)
      depth = 0
      masked = argument_list.each_char.map do |char|
        if char == '('
          depth += 1
          char
        elsif char == ')'
          depth -= 1
          char
        elsif char == ';' && depth != 0
          '$'
        else
          char
        end
      end.join
      masked.split(';', -1)
    end

    def parse_argument(piece)
      result = ExpressionParser.new(piece.tr('$', ';').strip, @parser).parse
      if result.error_code == ErrorCode::NONE && result.value
        result.value
      else
        @parser.set_error(
          result.error_code,
          result.error_token,
          @right.first_token.start_index,
          @right.last_token.end_index,
        )
        nil
      end
    end
end

class UnaryMinusNode < RNode
  def solve_r(r) = r.invert_sign
end

class AbsoluteValueNode < RNode
  def solve_r(r) = r.abs
end

class FloorNode < RNode
  def solve_r(r) = r.floor
end

class CeilingNode < RNode
  def solve_r(r) = r.ceiling
end

class FractionalComponentNode < RNode
  def solve_r(r) = r.fractional_part
end

class RoundNode < RNode
  def solve_r(r) = r.round
end

class PercentNode < RNode
  def solve_r(r) = r.divide_integer(100)
end

class FactorialNode < RNode
  def solve_r(r) = r.factorial(@parser.budget)
end

class AddNode < LRNode
  attr_accessor :do_percentage

  def initialize(parser, token, precedence, associativity, value = nil)
    super
    @repeatable = true
    @do_percentage = false
  end

  def solve_lr(l, r)
    if @do_percentage
      l.multiply(r.add(Number.integer(100)).divide_integer(100))
    else
      l.add(r)
    end
  end
end

class SubtractNode < LRNode
  attr_accessor :do_percentage

  def initialize(parser, token, precedence, associativity, value = nil)
    super
    @repeatable = true
    @do_percentage = false
  end

  def solve_lr(l, r)
    if @do_percentage
      l.multiply(r.add(Number.integer(-100)).divide_integer(-100))
    else
      l.subtract(r)
    end
  end
end

class MultiplyNode < LRNode
  def initialize(parser, token, precedence, associativity, value = nil)
    super
    # An implied multiplication — the one between 2 and x in "2x" — has no
    # token, and repeating the last operation only makes sense for one the
    # user typed.
    @repeatable = !token.nil?
  end

  def solve_lr(l, r) = l.multiply(r)
end

class ShiftNode < LRNode
  def initialize(parser, token, precedence, associativity, value = nil)
    super
    @repeatable = true
  end

  def solve_lr(l, r)
    case first_token.type
    when LexerTokenType::SHIFT_LEFT then l.left_shift(r, @parser.wordlen)
    when LexerTokenType::SHIFT_RIGHT then l.right_shift(r, @parser.wordlen)
    else l.unsigned_right_shift(r, @parser.wordlen)
    end
  end
end

class DivideNode < LRNode
  def initialize(parser, token, precedence, associativity, value = nil)
    super
    @repeatable = true
  end

  def solve_lr(l, r)
    l.divide(r).tap do
      if Number.error
        @parser.set_number_error(@right.leftmost_start, @right.rightmost_end)
      end
    end
  end
end

# `x mod y`, which becomes a modular exponentiation when the left operand is a
# power: `2^10 mod 7` is solved without ever forming 2^10.
class ModulusDivideNode < LRNode
  def solve
    if !@parser.check_budget
      nil
    elsif @left.is_a?(XPowYNode)
      solve_modular_exponentiation
    else
      super
    end
  end

  def solve_lr(l, r) = l.modulus_divide(r)

  private

    def solve_modular_exponentiation
      base_value = @left.left.solve
      if !@parser.check_budget
        nil
      else
        exponent = @left.right.solve
        if !@parser.check_budget
          nil
        else
          modular_result(base_value, exponent, @right.solve)
        end
      end
    end

    def modular_result(base_value, exponent, modulus)
      if base_value.nil? || exponent.nil? || modulus.nil?
        nil
      else
        base_value.modular_exponentiation(exponent, modulus, @parser.budget)
          .tap { report_number_error(@left, @right) }
      end
    end
end

# `√x`, `∛x`, `ⁿ√x` and `ₙ√x`.
class RootNode < RNode
  def initialize(parser, token, precedence, associativity, degree)
    super(
      parser,
token,
precedence,
associativity
)
    @degree = degree
    @token_n = nil
  end

  def self.with_token(parser, token, precedence, associativity, token_n)
    new(
      parser,
      token,
      precedence,
      associativity,
      0,
    ).tap do |node|
      node.token_n = token_n
    end
  end

  attr_writer :token_n

  def solve_r(r)
    if @degree.zero? && @token_n
      @degree = degree_from_token
    end
    if @degree.zero?
      @parser.set_error(
        ErrorCode::MP,
        'The zeroth root of a number is undefined',
        @token_n.start_index,
        @token_n.end_index,
      )
      nil
    else
      r.root(@degree, @parser.budget)
    end
  end

  private

    def degree_from_token
      if @token_n.type == LexerTokenType::SUP_NUMBER
        Equation.super_atoi(@token_n.text)
      else
        Equation.sub_atoi(@token_n.text)
      end
    end
end

class XPowYNode < LRNode
  def solve_lr(l, r) = l.xpowy(r, @parser.budget)
end

# An `x^y` whose right operand is a superscript literal.
class XPowYIntegerNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    else
      base_value = left_value
      if base_value.nil?
        nil
      else
        exponent = right_exponent
        if exponent.nil?
          nil
        else
          base_value.xpowy_integer(exponent, @parser.budget)
            .tap { report_number_error(@left, @right) }
        end
      end
    end
  end

  private

    # Inside a nested power the left operand is itself a superscript literal,
    # which does not solve on its own.
    def left_value
      value = @left.solve
      if value.nil?
        Number.integer(Equation.super_atoi(@left.token.text))
      else
        value
      end
    end

    def right_exponent
      if @right.token
        Equation.super_atoi(@right.token.text)
      else
        value = @right.solve
        if value
          value.to_integer
        end
      end
    end
end

class NotNode < RNode
  def solve_r(r) = r.not(@parser.wordlen, @parser.budget)
end

class AndNode < LRNode
  def solve_lr(l, r) = l.and_with(r, @parser.budget)
end

class NandNode < LRNode
  def solve_lr(l, r) = l.nand(r, @parser.wordlen, @parser.budget)
end

class OrNode < LRNode
  def solve_lr(l, r) = l.or_with(r, @parser.budget)
end

class NorNode < LRNode
  def solve_lr(l, r) = l.nor(r, @parser.wordlen, @parser.budget)
end

class XorNode < LRNode
  def solve_lr(l, r) = l.xor(r, @parser.budget)
end

class XnorNode < LRNode
  def solve_lr(l, r) = l.xnor(r, @parser.wordlen, @parser.budget)
end

# `unit in unit` with no value, which answers the rate between the two.
class ConvertNode < LRNode
  def solve_lr(_l, _r)
    from = take_name(@left)
    to = take_name(@right)
    answer, = @parser.convert(Number.integer(1), from, to)
    if answer.nil?
      @parser.set_error(ErrorCode::UNKNOWN_CONVERSION)
    end
    answer
  end

  private

    def take_name(node)
      if node.value
        node.value.tap { node.value = nil }
      else
        node.token.text
      end
    end
end

# `expression in hex`, which changes the base the answer is displayed in.
class ConvertBaseNode < ParseNode
  BASES = {
    'hex'         => 16,
    'hexadecimal' => 16,
    'dec'         => 10,
    'decimal'     => 10,
    'oct'         => 8,
    'octal'       => 8,
    'bin'         => 2,
    'binary'      => 2,
  }.freeze

  def solve
    if !@parser.check_budget
      nil
    else
      name = @value
      if name.nil? && @right
        name = @right.token.text
      end
      if BASES.key?(name)
        @parser.representation_base = BASES[name]
        @left.solve
      else
        @parser.set_error(
          ErrorCode::UNKNOWN_CONVERSION,
          token.text,
          first_token.start_index,
          last_token.end_index,
        )
        nil
      end
    end
  end
end

# `value unit in unit`.
class ConvertNumberNode < ParseNode
  def solve
    if !@parser.check_budget
      nil
    else
      from = take_name(@left)
      to = take_name(@right)
      value = @left.left.solve
      if value.nil?
        nil
      else
        convert(value, from, to)
      end
    end
  end

  private

    def take_name(node)
      if node.value
        node.value.tap { node.value = nil }
      else
        node.token.text
      end
    end

    def convert(value, from, to)
      answer, from_unit, to_unit = @parser.convert(value, from, to)
      if answer.nil?
        report_failure(
          from,
          to,
          from_unit,
          to_unit,
        )
      end
      answer
    end

    # Which half of the conversion failed decides what the user is told: an
    # unknown unit, or a known currency with no rate downloaded yet.
    def report_failure(from, to, from_unit, to_unit)
      if from_unit.nil?
        @parser.set_error(
          ErrorCode::UNKNOWN_UNIT,
          from,
          @left.token.start_index,
          @left.token.end_index,
        )
      elsif to_unit.nil?
        @parser.set_error(
          ErrorCode::UNKNOWN_UNIT,
          to,
          @right.token.start_index,
          @right.token.end_index,
        )
      elsif !@parser.currency_has_rate(from_unit.name)
        @parser.set_error(
          ErrorCode::UNKNOWN_RATE,
          from_unit.display_name,
          @left.token.start_index,
          @left.token.end_index,
        )
      elsif !@parser.currency_has_rate(to_unit.name)
        @parser.set_error(
          ErrorCode::UNKNOWN_RATE,
          to_unit.display_name,
          @right.token.start_index,
          @right.token.end_index,
        )
      else
        @parser.set_error(ErrorCode::UNKNOWN_CONVERSION)
      end
    end
end

# Parser turns an expression into a parse tree and solves it.
#
# Ported from upstream's Parser in lib/equation-parser.vala: an LL(*) parser
# whose lookahead depends on the token, building the tree by inserting each
# node at the place its precedence puts it rather than by recursive descent.
#
# Upstream's `parse` and `create_parse_tree` write their answers to five out
# parameters; here they answer a ParseResult carrying the same five fields plus
# the value.
class Parser
  ParseResult = Struct.new(
    :value,
    :representation_base,
    :error_code,
    :error_token,
    :error_start,
    :error_end,
  )

  attr_reader :number_base, :wordlen, :angle_units, :budget
  attr_accessor :representation_base

  class << self
    # The physical and mathematical constants the parser resolves as
    # variables, by category, as upstream's CONSTANT_CATEGORIES. Built on
    # demand because every value is a Number.
    def constant_categories
      @constant_categories ||= build_constant_categories
    end

    # Every constant by symbol, plus the spelled-out names upstream adds.
    def constants
      @constants ||= build_constants
    end

    private

      def build_constants
        {
          'pi'  => Number.pi,
          'tau' => Number.tau,
          'i'   => Number.i,
        }.tap do |table|
          constant_categories.each do |category|
            category.constants.each { |constant| table[constant.symbol] = constant.number }
          end
        end
      end

      def build_constant_categories
        [
          ConstantCategory.new('Mathematics', mathematics_constants),
          ConstantCategory.new('Electromagnetism', electromagnetism_constants),
          ConstantCategory.new('Atomic & Nuclear', atomic_constants),
          ConstantCategory.new('Thermodynamics', thermodynamics_constants),
          ConstantCategory.new('Gravitation', gravitation_constants),
        ]
      end

      def mathematics_constants
        [
          Constant.new('Euler’s Number', 'e', Number.eulers),
          Constant.new('Pi', 'π', Number.pi),
          Constant.new('Tau', 'τ', Number.tau),
          Constant.new(
            'Golden Ratio',
            'φ',
            Number.integer(1).add(Number.integer(5).sqrt).divide_integer(2),
          ),
        ]
      end

      def electromagnetism_constants
        [
          Constant.new('Light Speed', 'c₀', Number.integer(299_792_458)),
          Constant.new('Elementary Charge', 'е', Number.from_string('0.0000000000000000001602176634')),
          Constant.new('Impedance of Vacuum', 'Z₀', Number.from_string('376.730313412')),
          Constant.new('Permeability of Vacuum', 'μ₀', Number.from_string('0.00000125663706127')),
          Constant.new('Permittivity of Vacuum', 'ε₀', Number.from_string('0.0000000000088541878188')),
        ]
      end

      def atomic_constants
        [
          Constant.new(
            'Planck’s Constant',
            'h',
            Number.from_string('0.000000000000000000000000000000000662607015'),
          ),
          Constant.new('Fine-Structure Constant', 'α', Number.from_string('0.0072973525643')),
          Constant.new(
            'Electron Mass',
            'mₑ',
            Number.from_string('0.00000000000000000000000000000091093837139'),
          ),
          Constant.new(
            'Proton Mass',
            'mₚ',
            Number.from_string('0.00000000000000000000000000167262192595'),
          ),
        ]
      end

      def thermodynamics_constants
        [
          Constant.new('Boltzmann Constant', 'k', Number.from_string('0.00000000000000000000001380649')),
          Constant.new(
            'Atomic Mass Unit',
            'mᵤ',
            Number.from_string('0.00000000000000000000000000166053906892'),
          ),
          Constant.new('Molar Gas Constant', 'R', Number.from_string('8.31446261815324')),
          Constant.new('Stefan-Boltzmann Constant', 'σ', Number.from_string('0.00000005670374419')),
          Constant.new('Avogadro’s Number', 'Nᴀ', Number.from_string('602214076000000000000000')),
        ]
      end

      def gravitation_constants
        [
          Constant.new('Gravitational Constant', 'G', Number.from_string('0.000000000066743')),
          Constant.new('Earth Acceleration', 'g', Number.from_string('9.80665')),
        ]
      end
  end

  def initialize(input, number_base, wordlen, angle_units, budget = nil)
    @input = input
    @lexer = Lexer.new(input, self, number_base)
    @root = nil
    @right_most = nil
    @depth_level = 0
    @number_base = number_base
    @representation_base = number_base
    @wordlen = wordlen
    @angle_units = angle_units
    @budget = budget
    @error = ErrorCode::NONE
    @error_token = nil
    @error_token_start = 0
    @error_token_end = 0
  end

  def create_parse_tree
    breach = input_breach
    if breach
      set_error(breach.code, breach.message)
      failure
    else
      scan_and_parse
    end
  end

  def set_error(errorno, token = nil, token_start = 0, token_end = 0)
    @error = errorno
    @error_token = token
    @error_token_start = token_start
    @error_token_end = token_end
  end

  def set_number_error(token_start = 0, token_end = 0)
    errorno = ErrorCode::MP
    if Number.error_code != ErrorCode::NONE
      errorno = Number.error_code
    end
    set_error(
      errorno,
      Number.error,
      token_start,
      token_end,
    )
    Number.clear_error
  end

  def check_budget(steps = 1, token_start = 0, token_end = 0)
    if @budget.nil?
      true
    else
      breach = @budget.charge(steps)
      if breach
        set_error(
          breach.code,
          breach.message,
          token_start,
          token_end,
        )
        false
      else
        true
      end
    end
  end

  # The hooks a subclass fills in. Upstream declares these virtual on Parser
  # and overrides them in EquationParser, ExpressionParser and FunctionParser.
  def variable_is_defined(_name) = false

  def get_variable(_name) = nil

  def set_variable(_name, _value) = nil

  def function_is_defined(_name) = false

  def unit_is_defined(_name) = false

  def currency_is_defined(_name) = false

  def currency_has_rate(_name) = false

  def literal_base_is_defined(_name) = false

  # Answers [value, from unit, to unit]; the units come back so the caller can
  # say which half of a failed conversion was at fault.
  def convert(_x, _x_units, _z_units) = [nil, nil, nil]

  # The operator and right operand of the last operation, which is what the
  # equation repeats when the user presses "=" again. Answers [token, operand].
  def last_operation
    node = @root
    if !node.is_a?(LRNode) || !node.repeatable? || !check_budget
      ['', nil]
    else
      [@root.last_token.text, node.right.solve]
    end
  end

  def parse
    result = create_parse_tree
    if result.error_code != ErrorCode::NONE
      result
    elsif !check_budget
      failure
    else
      solve_tree
    end
  end

  private

    def input_breach
      if @budget
        @budget.check_input(@input)
      end
    end

    def token_breach
      if @budget
        @budget.check_tokens(@lexer.tokens.length)
      end
    end

    def failure
      ParseResult.new(
        nil,
        @representation_base,
        @error,
        @error_token,
        @error_token_start,
        @error_token_end,
      )
    end

    def scan_and_parse
      @lexer.scan
      breach = token_breach
      if breach
        set_error(breach.code, breach.message)
        failure
      else
        parsed = statement
        check_fully_parsed(parsed)
      end
    end

    def check_fully_parsed(parsed)
      token = @lexer.get_next_token
      if token.type == LexerTokenType::ASSIGN
        token = @lexer.get_next_token
      end
      if token.type != LexerTokenType::PL_EOS
        if @error == ErrorCode::NONE
          set_error(
            ErrorCode::INVALID,
            token.text,
            token.start_index,
            token.end_index,
          )
        end
        failure
      elsif !parsed
        if @error == ErrorCode::NONE
          set_error(ErrorCode::INVALID)
        end
        failure
      else
        ParseResult.new(
          nil,
          @number_base,
          ErrorCode::NONE,
          nil,
          0,
          0,
        )
      end
    end

    def solve_tree
      answer = @root.solve
      if answer.nil? && @error == ErrorCode::NONE
        set_error(ErrorCode::INVALID)
        ParseResult.new(
          nil,
          @representation_base,
          ErrorCode::INVALID,
          nil,
          @error_token_start,
          @error_token_end,
        )
      else
        ParseResult.new(
          answer,
          @representation_base,
          @error,
          @error_token,
          @error_token_start,
          @error_token_end,
        )
      end
    end

    # Precedence by token type. Unary plus and unary minus are not here: their
    # precedence is passed in directly where they are inserted.
    PRECEDENCES = {
      LexerTokenType::ADD          => Precedence::ADD_SUBTRACT,
      LexerTokenType::SUBTRACT     => Precedence::ADD_SUBTRACT,
      LexerTokenType::MULTIPLY     => Precedence::MULTIPLY,
      LexerTokenType::MOD          => Precedence::MOD,
      LexerTokenType::DIVIDE       => Precedence::DIVIDE,
      LexerTokenType::NOT          => Precedence::NOT,
      LexerTokenType::ROOT         => Precedence::ROOT,
      LexerTokenType::ROOT_3       => Precedence::ROOT,
      LexerTokenType::ROOT_4       => Precedence::ROOT,
      LexerTokenType::FUNCTION     => Precedence::FUNCTION,
      LexerTokenType::AND          => Precedence::BOOLEAN,
      LexerTokenType::NAND         => Precedence::BOOLEAN,
      LexerTokenType::OR           => Precedence::BOOLEAN,
      LexerTokenType::NOR          => Precedence::BOOLEAN,
      LexerTokenType::XOR          => Precedence::BOOLEAN,
      LexerTokenType::XNOR         => Precedence::BOOLEAN,
      LexerTokenType::PERCENTAGE   => Precedence::PERCENTAGE,
      LexerTokenType::POWER        => Precedence::POWER,
      LexerTokenType::FACTORIAL    => Precedence::FACTORIAL,
      LexerTokenType::NUMBER       => Precedence::NUMBER_VARIABLE,
      LexerTokenType::VARIABLE     => Precedence::NUMBER_VARIABLE,
      LexerTokenType::UNIT         => Precedence::UNIT,
      LexerTokenType::IN           => Precedence::CONVERT,
      LexerTokenType::SHIFT_LEFT   => Precedence::SHIFT,
      LexerTokenType::SHIFT_RIGHT  => Precedence::SHIFT,
      LexerTokenType::SHIFT_URIGHT => Precedence::SHIFT,
      LexerTokenType::L_R_BRACKET  => Precedence::DEPTH,
      LexerTokenType::R_R_BRACKET  => Precedence::DEPTH,
    }.freeze

    def precedence_of(type) = PRECEDENCES.fetch(type, Precedence::TOP)

    def associativity_p(precedence)
      if precedence == Precedence::POWER
        Associativity::RIGHT
      else
        Associativity::LEFT
      end
    end

    def associativity(token) = associativity_p(precedence_of(token.type))

    def make_precedence_p(precedence) = precedence + (@depth_level * Precedence::DEPTH)

    def make_precedence_t(type) = precedence_of(type) + (@depth_level * Precedence::DEPTH)

    # True when `right` goes nearer the root than `left`.
    def cmp_nodes(left, right)
      if left.nil?
        false
      elsif left.precedence > right.precedence
        true
      elsif left.precedence < right.precedence
        false
      else
        right.associativity != Associativity::RIGHT
      end
    end

    def insert_into_tree_all(node, unary_function)
      if @root.nil?
        @root = node
        @right_most = @root
      else
        tmp = @right_most
        while cmp_nodes(tmp, node)
          tmp = tmp.parent
        end
        if unary_function
          attach_unary(node, tmp)
        else
          attach_binary(node, tmp)
        end
      end
    end

    def attach_unary(node, tmp)
      if tmp.nil?
        node.right = @root
        node.right.parent = node
        @root = node
      else
        node.right = tmp.right
        if node.right
          node.right.parent = node
        end
        tmp.right = node
        tmp.right.parent = tmp
      end
      @right_most = node
      while @right_most.right
        @right_most = @right_most.right
      end
    end

    def attach_binary(node, tmp)
      if tmp.nil?
        node.left = @root
        node.left.parent = node
        @root = node
      else
        node.left = tmp.right
        if node.left
          node.left.parent = node
        end
        tmp.right = node
        tmp.right.parent = tmp
      end
      @right_most = node
    end

    def insert_into_tree(node) = insert_into_tree_all(node, false)

    def insert_into_tree_unary(node) = insert_into_tree_all(node, true)

    # Whether `name` resolves as a variable, either on its own or as a product
    # of single-letter variables.
    def check_variable(name)
      if variable_is_defined(name)
        true
      else
        name.each_char.all? { |char| variable_is_defined(char) }
      end
    end

    def statement
      token = @lexer.get_next_token
      if [LexerTokenType::VARIABLE, LexerTokenType::FUNCTION].include?(token.type)
        named_statement(token)
      else
        @lexer.roll_back
        expression
      end
    end

    def named_statement(name_token)
      token = @lexer.get_next_token
      if token.type == LexerTokenType::ASSIGN
        insert_into_tree(
          NameNode.new(
            self,
            name_token,
            make_precedence_p(Precedence::NUMBER_VARIABLE),
            associativity(name_token),
          ),
        )
        insert_into_tree(
          AssignNode.new(
            self,
            token,
            0,
            associativity(token),
          ),
        )
        expression
      else
        @lexer.roll_back
        @lexer.roll_back
        if token.type == LexerTokenType::L_R_BRACKET && function_definition
          true
        else
          expression
        end
      end
    end

    def function_definition
      consumed = 0
      token = @lexer.get_next_token
      consumed += 1
      function_name = token.text
      @lexer.get_next_token
      consumed += 1

      token = @lexer.get_next_token
      consumed += 1
      argument_list = ''
      token_list = []
      while token.type != LexerTokenType::R_R_BRACKET && token.type != LexerTokenType::PL_EOS
        token_list << token
        argument_list += token.text
        token = @lexer.get_next_token
        consumed += 1
      end

      if token.type == LexerTokenType::PL_EOS
        consumed.times { @lexer.roll_back }
        false
      else
        finish_function_definition(
          function_name,
          argument_list,
          token_list,
          consumed,
        )
      end
    end

    def finish_function_definition(function_name, argument_list, token_list, consumed)
      assign_token = @lexer.get_next_token
      consumed += 1
      if assign_token.type != LexerTokenType::ASSIGN
        consumed.times { @lexer.roll_back }
        false
      else
        insert_function_definition(
          function_name,
          argument_list,
          token_list,
          assign_token,
        )
      end
    end

    def insert_function_definition(function_name, argument_list, token_list, assign_token)
      expression_text = ''
      token = @lexer.get_next_token
      while token.type != LexerTokenType::PL_EOS
        if token.type == LexerTokenType::VARIABLE
          expression_text += "(#{token.text})"
        else
          expression_text += token.text
        end
        token = @lexer.get_next_token
      end

      name_precedence = make_precedence_p(Precedence::NUMBER_VARIABLE)
      name_associativity = associativity_p(Precedence::NUMBER_VARIABLE)
      insert_into_tree(
        FunctionNameNode.new(
          self,
          nil,
          name_precedence,
          name_associativity,
          function_name,
        ),
      )
      insert_into_tree(
        FunctionNode.new(
          self,
          nil,
          make_precedence_p(Precedence::FUNCTION),
          associativity_p(Precedence::FUNCTION),
          nil,
        ),
      )
      insert_into_tree(
        FunctionArgumentsNode.with_list(
          self,
          token_list,
          name_precedence,
          name_associativity,
          argument_list,
        ),
      )
      insert_into_tree(
        AssignFunctionNode.new(
          self,
          assign_token,
          0,
          associativity(assign_token),
        ),
      )
      insert_into_tree(
        FunctionDescriptionNode.new(
          self,
          nil,
          name_precedence,
          name_associativity,
          expression_text,
        ),
      )
      true
    end

    def conversion
      token = @lexer.get_next_token
      if token.type == LexerTokenType::IN
        base_conversion(token)
      elsif [LexerTokenType::UNIT, LexerTokenType::CURRENCY].include?(token.type)
        unit_conversion(token)
      else
        @lexer.roll_back
        false
      end
    end

    # `expression in hex`: a representation base may only be converted at the
    # very end of the expression.
    def base_conversion(token_in)
      token = @lexer.get_next_token
      if token.type != LexerTokenType::UNIT
        2.times { @lexer.roll_back }
        false
      else
        token_to = token
        if @lexer.get_next_token.type == LexerTokenType::PL_EOS
          insert_into_tree(
            ConvertBaseNode.new(
              self,
              token_in,
              make_precedence_p(Precedence::CONVERT),
              associativity(token_in),
            ),
          )
          insert_into_tree(
            NameNode.new(
              self,
              token_to,
              make_precedence_p(Precedence::UNIT),
              associativity(token_to),
            ),
          )
          true
        else
          3.times { @lexer.roll_back }
          false
        end
      end
    end

    def unit_conversion(token_from)
      token = @lexer.get_next_token
      if token.type != LexerTokenType::IN
        2.times { @lexer.roll_back }
        false
      else
        token_in = token
        token = @lexer.get_next_token
        if [LexerTokenType::UNIT, LexerTokenType::CURRENCY].include?(token.type)
          insert_into_tree(
            NameNode.new(
              self,
              token_from,
              make_precedence_p(Precedence::UNIT),
              associativity(token_from),
            ),
          )
          insert_into_tree(
            ConvertNumberNode.new(
              self,
              token_in,
              make_precedence_p(Precedence::CONVERT),
              associativity(token_in),
            ),
          )
          insert_into_tree(
            NameNode.new(
              self,
              token,
              make_precedence_p(Precedence::UNIT),
              associativity(token),
            ),
          )
          true
        else
          3.times { @lexer.roll_back }
          false
        end
      end
    end

    def expression
      if !expression_1
        false
      elsif !expression_2
        false
      else
        # A conversion at this level goes into the tree above everything else.
        conversion
        true
      end
    end

    def expression_1
      token = @lexer.get_next_token
      case token.type
      when LexerTokenType::PL_EOS, LexerTokenType::ASSIGN
        @lexer.roll_back
        false
      when LexerTokenType::L_R_BRACKET
        bracketed_expression
      when LexerTokenType::L_S_BRACKET
        wrapped_expression(RoundNode, token, LexerTokenType::R_S_BRACKET)
      when LexerTokenType::L_C_BRACKET
        wrapped_expression(FractionalComponentNode, token, LexerTokenType::R_C_BRACKET)
      when LexerTokenType::ABS
        wrapped_expression(AbsoluteValueNode, token, LexerTokenType::ABS)
      when LexerTokenType::NOT
        insert_into_tree_unary(
          NotNode.new(
            self,
            token,
            make_precedence_p(Precedence::NOT),
            associativity(token),
          ),
        )
        expression
      when LexerTokenType::NUMBER
        number_expression(token)
      when LexerTokenType::L_FLOOR
        fenced_expression(FloorNode, LexerTokenType::R_FLOOR)
      when LexerTokenType::L_CEILING
        fenced_expression(CeilingNode, LexerTokenType::R_CEILING)
      when LexerTokenType::SUBTRACT
        insert_into_tree_unary(
          UnaryMinusNode.new(
            self,
            token,
            make_precedence_p(Precedence::UNARY_MINUS),
            associativity_p(Precedence::UNARY_MINUS),
          ),
        )
        expression_1
      when LexerTokenType::ADD
        unary_plus
      else
        @lexer.roll_back
        variable
      end
    end

    def bracketed_expression
      @depth_level += 1
      if !expression
        false
      elsif @lexer.get_next_token.type != LexerTokenType::R_R_BRACKET
        false
      else
        @depth_level -= 1
        token = @lexer.get_next_token
        @lexer.roll_back
        if token.type == LexerTokenType::NUMBER
          # "(2)3" is a multiplication.
          insert_into_tree(
            MultiplyNode.new(
              self,
              nil,
              make_precedence_p(Precedence::MULTIPLY),
              associativity_p(Precedence::MULTIPLY),
            ),
          )
          expression
        else
          true
        end
      end
    end

    # `[x]`, `{x}` and `|x|`: the operator sits at TOP so it stays above the
    # expression it wraps.
    def wrapped_expression(node_class, token, closing)
      @depth_level += 1
      insert_into_tree_unary(
        node_class.new(
          self,
          token,
          make_precedence_p(Precedence::TOP),
          associativity(token),
        ),
      )
      if !expression
        false
      elsif @lexer.get_next_token.type != closing
        false
      else
        @depth_level -= 1
        true
      end
    end

    # `⌊x⌋` and `⌈x⌉`, whose node carries no token.
    def fenced_expression(node_class, closing)
      @depth_level += 1
      insert_into_tree_unary(
        node_class.new(
          self,
          nil,
          make_precedence_p(Precedence::TOP),
          associativity_p(Precedence::TOP),
        ),
      )
      if !expression
        false
      elsif @lexer.get_next_token.type != closing
        false
      else
        @depth_level -= 1
        true
      end
    end

    IMPLIED_MULTIPLY_FOLLOWERS = [
      LexerTokenType::FUNCTION,
      LexerTokenType::VARIABLE,
      LexerTokenType::SUB_NUMBER,
      LexerTokenType::ROOT,
      LexerTokenType::ROOT_3,
      LexerTokenType::ROOT_4,
    ].freeze

    def number_expression(token)
      insert_into_tree(
        ConstantNode.new(
          self,
          token,
          make_precedence_t(token.type),
          associativity(token),
        ),
      )
      following = @lexer.get_next_token
      @lexer.roll_back
      if IMPLIED_MULTIPLY_FOLLOWERS.include?(following.type)
        insert_into_tree(
          MultiplyNode.new(
            self,
            nil,
            make_precedence_p(Precedence::MULTIPLY),
            associativity_p(Precedence::MULTIPLY),
          ),
        )
        variable
      else
        true
      end
    end

    # A leading plus is dropped; it carries no meaning.
    def unary_plus
      token = @lexer.get_next_token
      if token.type == LexerTokenType::NUMBER
        insert_into_tree(
          ConstantNode.new(
            self,
            token,
            make_precedence_t(token.type),
            associativity(token),
          ),
        )
        true
      else
        false
      end
    end

    BINARY_NODES = {
      LexerTokenType::MULTIPLY     => MultiplyNode,
      LexerTokenType::AND          => AndNode,
      LexerTokenType::NAND         => NandNode,
      LexerTokenType::OR           => OrNode,
      LexerTokenType::NOR          => NorNode,
      LexerTokenType::XOR          => XorNode,
      LexerTokenType::XNOR         => XnorNode,
      LexerTokenType::DIVIDE       => DivideNode,
      LexerTokenType::SHIFT_LEFT   => ShiftNode,
      LexerTokenType::SHIFT_RIGHT  => ShiftNode,
      LexerTokenType::SHIFT_URIGHT => ShiftNode,
      LexerTokenType::MOD          => ModulusDivideNode,
      LexerTokenType::POWER        => XPowYNode,
    }.freeze

    def expression_2
      token = @lexer.get_next_token
      type = token.type
      if type == LexerTokenType::L_R_BRACKET
        implied_multiply_bracket
      elsif BINARY_NODES.key?(type)
        binary_operator(BINARY_NODES[type], token)
      elsif [LexerTokenType::SUP_NUMBER, LexerTokenType::NSUP_NUMBER].include?(type)
        superscript_power(token)
      elsif type == LexerTokenType::FACTORIAL
        insert_into_tree_unary(
          FactorialNode.new(
            self,
            token,
            make_precedence_t(type),
            associativity(token),
          ),
        )
        expression_2
      elsif type == LexerTokenType::PERCENTAGE
        insert_into_tree_unary(
          PercentNode.new(
            self,
            token,
            make_precedence_t(type),
            associativity(token),
          ),
        )
        expression_2
      elsif [LexerTokenType::ADD, LexerTokenType::SUBTRACT].include?(type)
        additive_operator(token)
      else
        @lexer.roll_back
        true
      end
    end

    def implied_multiply_bracket
      insert_into_tree(
        MultiplyNode.new(
          self,
          nil,
          make_precedence_p(Precedence::MULTIPLY),
          associativity_p(Precedence::MULTIPLY),
        ),
      )
      @depth_level += 1
      if !expression
        false
      elsif @lexer.get_next_token.type != LexerTokenType::R_R_BRACKET
        false
      else
        @depth_level -= 1
        expression_2
      end
    end

    def binary_operator(node_class, token)
      insert_into_tree(
        node_class.new(
          self,
          token,
          make_precedence_t(token.type),
          associativity(token),
        ),
      )
      if !expression_1
        false
      else
        expression_2
      end
    end

    def superscript_power(token)
      insert_into_tree(
        XPowYIntegerNode.new(
          self,
          nil,
          make_precedence_p(Precedence::POWER),
          associativity_p(Precedence::POWER),
        ),
      )
      insert_into_tree(
        NameNode.new(
          self,
          token,
          make_precedence_p(Precedence::NUMBER_VARIABLE),
          associativity_p(Precedence::NUMBER_VARIABLE),
        ),
      )
      expression_2
    end

    # `a + b%` is "a plus b percent of a", not "a plus b/100" — but only when
    # the right operand binds tighter than the percentage.
    def additive_operator(token)
      node = additive_node(token)
      insert_into_tree(node)
      if !expression_1
        false
      else
        percentage_or_continue(node)
      end
    end

    def additive_node(token)
      if token.type == LexerTokenType::ADD
        AddNode.new(
          self,
          token,
          make_precedence_t(token.type),
          associativity(token),
        )
      else
        SubtractNode.new(
          self,
          token,
          make_precedence_t(token.type),
          associativity(token),
        )
      end
    end

    def percentage_or_continue(node)
      token = @lexer.get_next_token
      if token.type != LexerTokenType::PERCENTAGE
        @lexer.roll_back
        expression_2
      elsif node.right.precedence > Precedence::PERCENTAGE
        relative_percentage(node)
      else
        # Read the '%' as the percentage operator instead.
        @lexer.roll_back
        if expression_2
          expression_2
        else
          true
        end
      end
    end

    def relative_percentage(node)
      next_token = @lexer.get_next_token
      @lexer.roll_back
      if !next_token.text.empty? && next_token.text != '=' &&
         precedence_of(next_token.type) < Precedence::PERCENTAGE
        @lexer.roll_back
        expression_2
      end
      node.precedence = make_precedence_p(Precedence::PERCENTAGE)
      node.do_percentage = true
      true
    end

    def variable
      token = @lexer.get_next_token
      type = token.type
      if [LexerTokenType::FUNCTION, LexerTokenType::MOD].include?(type)
        @lexer.roll_back
        function_invocation
      elsif [LexerTokenType::SUB_NUMBER, LexerTokenType::SUP_NUMBER].include?(type)
        indexed_root(token)
      elsif type == LexerTokenType::ROOT
        fixed_root(token, 2)
      elsif type == LexerTokenType::ROOT_3
        fixed_root(token, 3)
      elsif type == LexerTokenType::ROOT_4
        fixed_root(token, 4)
      elsif type == LexerTokenType::VARIABLE
        @lexer.roll_back
        term
      else
        false
      end
    end

    def indexed_root(degree_token)
      token = @lexer.get_next_token
      if token.type == LexerTokenType::ROOT
        insert_into_tree_unary(
          RootNode.with_token(
            self,
            token,
            make_precedence_t(token.type),
            associativity(token),
            degree_token,
          ),
        )
        expression
      else
        false
      end
    end

    def fixed_root(token, degree)
      insert_into_tree_unary(
        RootNode.new(
          self,
          token,
          make_precedence_t(token.type),
          associativity(token),
          degree,
        ),
      )
      expression
    end

    def function_invocation
      @depth_level += 1
      consumed = 0
      fun_token = @lexer.get_next_token
      consumed += 1
      function_name = fun_token.text

      insert_into_tree(
        FunctionNameNode.new(
          self,
          fun_token,
          make_precedence_p(Precedence::NUMBER_VARIABLE),
          associativity_p(Precedence::NUMBER_VARIABLE),
          function_name,
        ),
      )

      token = @lexer.get_next_token
      consumed += 1
      power = nil
      if [LexerTokenType::SUP_NUMBER, LexerTokenType::NSUP_NUMBER].include?(token.type)
        power = token.text
        token = @lexer.get_next_token
        consumed += 1
      end

      insert_into_tree(
        FunctionNode.new(
          self,
          fun_token,
          make_precedence_t(fun_token.type),
          associativity(fun_token),
          power,
        ),
      )

      log_base = nil
      if function_name.downcase == 'log' && token.type == LexerTokenType::NUMBER
        log_base = token.text
        token = @lexer.get_next_token
        consumed += 1
      end

      if token.type == LexerTokenType::L_R_BRACKET
        bracketed_arguments(log_base, consumed)
      else
        bare_argument(log_base)
      end
    end

    def bracketed_arguments(log_base, consumed)
      token = @lexer.get_next_token
      consumed += 1
      depth = 1
      argument_list = ''
      token_list = []
      closed = false

      while token.type != LexerTokenType::PL_EOS && token.type != LexerTokenType::ASSIGN && !closed
        if token.type == LexerTokenType::L_R_BRACKET
          depth += 1
        elsif token.type == LexerTokenType::R_R_BRACKET
          depth -= 1
          if log_base && !argument_list.empty?
            argument_list += ";#{log_base}"
          end
          if depth.zero?
            closed = true
          end
        else
          token_list << token
        end
        unless closed
          argument_list += " #{token.text}"
          token = @lexer.get_next_token
          consumed += 1
        end
      end

      if token.type != LexerTokenType::R_R_BRACKET
        consumed.times { @lexer.roll_back }
        @depth_level -= 1
        false
      else
        insert_into_tree(
          FunctionArgumentsNode.with_list(
            self,
            token_list,
            make_precedence_p(Precedence::NUMBER_VARIABLE),
            associativity_p(Precedence::NUMBER_VARIABLE),
            argument_list,
          ),
        )
        @depth_level -= 1
        true
      end
    end

    # `sin 5` with no brackets: the argument is whatever expression_1 reads.
    def bare_argument(log_base)
      @lexer.roll_back
      if log_base
        @lexer.roll_back
      end
      if !expression_1
        @lexer.roll_back
        @depth_level -= 1
        false
      else
        token = @lexer.get_next_token
        if token.type == LexerTokenType::FACTORIAL
          insert_into_tree_unary(
            FactorialNode.new(
              self,
              token,
              make_precedence_t(token.type),
              associativity(token),
            ),
          )
        else
          @lexer.roll_back
        end
        @depth_level -= 1
        finish_bare_argument
      end
    end

    def finish_bare_argument
      if expression_2
        true
      else
        @lexer.roll_back
        false
      end
    end

    def term
      token = @lexer.get_next_token
      if token.type != LexerTokenType::VARIABLE
        false
      else
        variable_term(token)
      end
    end

    def variable_term(name_token)
      token = @lexer.get_next_token
      if !check_variable(name_token.text)
        report_unknown_name(name_token, token)
        false
      else
        if token.type == LexerTokenType::SUP_NUMBER
          insert_into_tree(
            VariableWithPowerNode.new(
              self,
              name_token,
              make_precedence_t(name_token.type),
              associativity(name_token),
              token.text,
            ),
          )
        else
          @lexer.roll_back
          insert_into_tree(
            VariableNode.new(
              self,
              name_token,
              make_precedence_t(name_token.type),
              associativity(name_token),
            ),
          )
        end
        term_2
      end
    end

    def report_unknown_name(name_token, token)
      code = ErrorCode::UNKNOWN_VARIABLE
      if token.text == '('
        code = ErrorCode::UNKNOWN_FUNCTION
      end
      set_error(
        code,
        name_token.text,
        name_token.start_index,
        name_token.end_index,
      )
    end

    def term_2
      token = @lexer.get_next_token
      @lexer.roll_back
      if [LexerTokenType::PL_EOS, LexerTokenType::ASSIGN].include?(token.type)
        true
      elsif IMPLIED_MULTIPLY_FOLLOWERS.include?(token.type)
        # An implied multiplication between a variable and a function,
        # variable or root.
        insert_into_tree(
          MultiplyNode.new(
            self,
            nil,
            make_precedence_p(Precedence::MULTIPLY),
            associativity_p(Precedence::MULTIPLY),
          ),
        )
        variable
      else
        true
      end
    end
end
