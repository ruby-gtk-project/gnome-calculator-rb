# frozen_string_literal: true

require 'fileutils'

require_relative 'math_function'
require_relative 'serializer'

# A group of functions, as the function popover lists them.
#
# Ported from the FunctionCategory struct in upstream's
# lib/function-manager.vala.
FunctionCategory = Struct.new(:name, :functions)

# FunctionManager owns every function the parser can call: the built-ins, and
# the ones the user defined, which it loads from and saves to
# `custom-functions` under the user's data directory.
#
# Ported from upstream's lib/function-manager.vala. Upstream's
# function_added/function_edited/function_deleted signals become the
# on_function_added/edited/deleted callbacks below.
class FunctionManager
  class << self
    # Upstream's get_default_function_manager.
    def default = @default ||= new
  end

  def initialize(path: nil)
    @functions = {}
    @file_name = path || default_path
    @serializer = Serializer.new(DisplayFormat::SCIENTIFIC, 10, 50)
    @serializer.radix = '.'
    @added_handlers = []
    @edited_handlers = []
    @deleted_handlers = []
    reload_functions
  end

  def on_function_added(&block) = @added_handlers << block

  def on_function_edited(&block) = @edited_handlers << block

  def on_function_deleted(&block) = @deleted_handlers << block

  # The categories the function popover shows, in upstream's order. Built on
  # demand so that requiring this file does not construct any Numbers.
  def self.function_categories
    @function_categories ||= [
      FunctionCategory.new('Trigonometry', trigonometry_functions),
      FunctionCategory.new('Complex', complex_functions),
      FunctionCategory.new('Programming', programming_functions),
      FunctionCategory.new('Rounding', rounding_functions),
      FunctionCategory.new('Statistics', statistics_functions),
      FunctionCategory.new('Sundry', sundry_functions),
    ]
  end

  SERIES_ARGUMENTS = ['x₁', 'x₂', '…'].freeze

  class << self
    private

      def trigonometry_functions
        [
          BuiltInMathFunction.new('sin', 'Sine'),
          BuiltInMathFunction.new('cos', 'Cosine'),
          BuiltInMathFunction.new('tan', 'Tangent'),
          BuiltInMathFunction.new('sin⁻¹', 'Inverse Sine'),
          BuiltInMathFunction.new('cos⁻¹', 'Inverse Cosine'),
          BuiltInMathFunction.new('tan⁻¹', 'Inverse Tangent'),
          BuiltInMathFunction.new('sinh', 'Hyperbolic Sine'),
          BuiltInMathFunction.new('cosh', 'Hyperbolic Cosine'),
          BuiltInMathFunction.new('tanh', 'Hyperbolic Tangent'),
          BuiltInMathFunction.new('sinh⁻¹', 'Inverse Hyperbolic Sine'),
          BuiltInMathFunction.new('cosh⁻¹', 'Inverse Hyperbolic Cosine'),
          BuiltInMathFunction.new('tanh⁻¹', 'Inverse Hyperbolic Tangent'),
        ]
      end

      def complex_functions
        [
          BuiltInMathFunction.new('conj', 'Complex Conjugate'),
          BuiltInMathFunction.new('arg', 'Complex Argument'),
          BuiltInMathFunction.new('re', 'Real Component'),
          BuiltInMathFunction.new('im', 'Imaginary Component'),
        ]
      end

      def programming_functions
        [
          BuiltInMathFunction.new('twos', 'Two’s Complement'),
          BuiltInMathFunction.new('bswap', 'Swap Endianness'),
          BuiltInMathFunction.new('mod', 'Modulus Divide', %w[x y]),
          BuiltInMathFunction.new('modexp', 'Modular Exponentiation', %w[x y p]),
        ]
      end

      def rounding_functions
        [
          BuiltInMathFunction.new('round', 'Round'),
          BuiltInMathFunction.new('floor', 'Floor'),
          BuiltInMathFunction.new('ceil', 'Ceiling'),
          BuiltInMathFunction.new('int', 'Integer Component'),
          BuiltInMathFunction.new('frac', 'Fractional Component'),
        ]
      end

      def statistics_functions
        [
          BuiltInMathFunction.new('sum', 'Sum', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('sumsq', 'Sum of Squares', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('average', 'Average', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('median', 'Median', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('min', 'Minimum Value', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('max', 'Maximum Value', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('stdev', 'Sample Standard Deviation', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('stdevp', 'Population Standard Deviation', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('var', 'Sample Variance', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('varp', 'Population Variance', SERIES_ARGUMENTS),
        ]
      end

      def sundry_functions
        [
          BuiltInMathFunction.new('log', 'Logarithm', ['x', '[y]']),
          BuiltInMathFunction.new('ln', 'Natural Logarithm'),
          BuiltInMathFunction.new('sqrt', 'Square Root'),
          BuiltInMathFunction.new('abs', 'Absolute Value'),
          BuiltInMathFunction.new('sgn', 'Signum'),
          BuiltInMathFunction.new('ncr', 'Combination', %w[n r]),
          BuiltInMathFunction.new('npr', 'Permutation', %w[n r]),
          BuiltInMathFunction.new('gcd', 'Greatest Common Divisor', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('lcm', 'Least Common Multiple', SERIES_ARGUMENTS),
          BuiltInMathFunction.new('cmp', 'Comparison (Kronecker Delta)', %w[x y]),
        ]
      end
  end

  # Every function name. Upstream's array_sort_string sorts descending, and the
  # function list is built from that order, so it is kept.
  def names = @functions.keys.sort.reverse

  def [](name) = get(name)

  def get(name)
    @functions[name] || @functions[name.downcase]
  end

  def delete(name)
    function = get(name)
    if function&.custom_function?
      @functions.delete(function.name)
      save
      @deleted_handlers.each { |handler| handler.call(function) }
    end
  end

  # A name is a function if it is in the table, or if it is a logₙ name such as
  # log₂.
  def function_defined?(name)
    lower_name = name.downcase
    if lower_name.start_with?('log') && Equation.sub_atoi(lower_name[3..]) >= 0
      true
    else
      @functions.key?(name) || @functions.key?(lower_name)
    end
  end

  # Adds a function from the pieces the parser collected for a
  # `name(args) = body` statement.
  def add_function_with_properties(name, arguments, description, root_parser = nil)
    new_function = parse_function_from_string("#{name}(#{arguments})=#{description}")
    if new_function.nil? || !new_function.validate(root_parser)
      root_parser.set_error(ErrorCode::INVALID)
      false
    else
      added = add(new_function)
      if added
        save
      end
      added
    end
  end

  def evaluate_function(name, arguments, parser)
    name, args = resolve_log_base(name, arguments)
    if args.nil?
      nil
    else
      function = get(name)
      if function.nil?
        parser.set_error(ErrorCode::UNKNOWN_FUNCTION)
        nil
      else
        evaluate_checked(
          function,
          name,
          args,
          parser,
        )
      end
    end
  end

  # Every function whose name starts with `text`, for the completion popup.
  def functions_eligible_for_autocompletion(text)
    prefix = text.downcase
    @functions.values
      .select { |function| function.name.downcase.start_with?(prefix) }
      .sort { |a, b| a.name <=> b.name }
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
        'gnome-calculator',
        'custom-functions',
      )
    end

    def reload_functions
      @functions.clear
      reload_custom_functions
      reload_builtin_functions
    end

    # The "a" spellings of the inverse functions, which the popover does not
    # list but the parser accepts.
    ALIASED_BUILTINS = {
      'asin'  => 'Inverse Sine',
      'acos'  => 'Inverse Cosine',
      'atan'  => 'Inverse Tangent',
      'asinh' => 'Inverse Hyperbolic Sine',
      'acosh' => 'Inverse Hyperbolic Cosine',
      'atanh' => 'Inverse Hyperbolic Tangent',
    }.freeze

    def reload_builtin_functions
      ALIASED_BUILTINS.each { |name, description| add(BuiltInMathFunction.new(name, description)) }
      self.class.function_categories.each do |category|
        category.functions.each { |function| add(function) }
      end
    end

    def reload_custom_functions
      if File.exist?(@file_name)
        File.read(@file_name).split("\n").each do |line|
          function = parse_function_from_string(line)
          if function
            @functions[function.name] = function
          end
        end
      end
    end

    # `<name> (<a1>;<a2>;…) = <expression> @ <description>`
    def parse_function_from_string(data)
      if data.nil? || !data.include?('=')
        nil
      else
        left, right = data.split('=', 2).map(&:strip)
        expression, description = split_description(right)
        name, argument_list = split_signature(left)
        if name.nil?
          nil
        else
          MathFunction.new(
            name,
            argument_list.split(';', -1),
            expression,
            description,
          )
        end
      end
    end

    def split_description(right)
      if right.include?('@')
        right.split('@', 2).map(&:strip)
      else
        [right, '']
      end
    end

    def split_signature(left)
      if left.include?('(')
        name, argument_list = left.split('(', 2)
        [name.strip, argument_list.strip.delete(')')]
      else
        [nil, nil]
      end
    end

    def save
      data = @functions.each_value.select(&:custom_function?).map do |function|
        format(
          "%s(%s)=%s@%s\n",
          function.name,
          function.arguments.join(';'),
          function.expression,
          function.description,
        )
      end.join

      FileUtils.mkdir_p(File.dirname(@file_name), mode: 0o700)
      File.write(@file_name, data)
    end

    # Adds a function unless the name is already taken by a built-in.
    def add(new_function)
      existing = get(new_function.name)
      if existing && !existing.custom_function?
        false
      else
        @functions[new_function.name] = new_function
        if existing
          @edited_handlers.each { |handler| handler.call(new_function) }
        else
          @added_handlers.each { |handler| handler.call(new_function) }
        end
        true
      end
    end

    # `log₂(8)` arrives as the name "log₂" with one argument; the subscript
    # becomes the second argument of plain `log`.
    def resolve_log_base(name, arguments)
      lower_name = name.downcase
      if lower_name.start_with?('log') && lower_name.length > 3
        log_base = Equation.sub_atoi(lower_name[3..])
        if log_base.negative?
          [name, arguments]
        elsif arguments.length > 1
          Number.error = format('Function “%s” takes 1 argument', name)
          [name, nil]
        else
          ['log', arguments + [Number.integer(log_base)]]
        end
      else
        [name, arguments]
      end
    end

    def evaluate_checked(function, name, args, parser)
      message = argument_count_error(function, name, args)
      if message
        Number.error = message
        nil
      else
        function.evaluate(args, parser)
      end
    end

    # log takes one or two arguments and the series functions take at least
    # two, so neither is held to its declared argument count.
    def argument_count_error(function, name, args)
      lower_name = name.downcase
      if lower_name == 'log'
        log_argument_error(name, args)
      elsif %w[stdev var].include?(lower_name)
        series_argument_error(name, args)
      elsif fixed_arity_mismatch?(function, args)
        format(
          'Function “%s” takes %d argument%s',
          name,
          function.arguments.length,
          plural_suffix(function.arguments.length),
        )
      end
    end

    def log_argument_error(name, args)
      if args.length > 2
        format('Function “%s” takes 1 or 2 arguments', name)
      end
    end

    def series_argument_error(name, args)
      if args.length == 1
        format('Function “%s” takes at least 2 arguments', name)
      end
    end

    def plural_suffix(count)
      if count == 1
        ''
      else
        's'
      end
    end

    def fixed_arity_mismatch?(function, args)
      args.length != function.arguments.length &&
        !function.arguments.empty? &&
        function.arguments.last != '…'
    end
end
