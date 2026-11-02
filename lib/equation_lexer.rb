# frozen_string_literal: true

require_relative 'number'

# The token kinds the pre-lexer and the lexer produce.
#
# Ported from the LexerTokenType enum in upstream's lib/equation-lexer.vala.
# Upstream's enum members become symbols, so a token's type prints as itself in
# a backtrace.
module LexerTokenType
  UNKNOWN = :unknown

  # Pre-lexer tokens, returned by PreLexer.
  PL_DECIMAL = :pl_decimal
  PL_DIGIT = :pl_digit
  PL_HEX = :pl_hex
  PL_SUPER_DIGIT = :pl_super_digit
  PL_SUPER_MINUS = :pl_super_minus
  PL_SUB_DIGIT = :pl_sub_digit
  PL_FRACTION = :pl_fraction
  PL_DEGREE = :pl_degree
  PL_MINUTE = :pl_minute
  PL_SECOND = :pl_second
  PL_LETTER = :pl_letter
  PL_EOS = :pl_eos
  PL_SKIP = :pl_skip

  # Tokens returned by Lexer.
  ADD = :add
  SUBTRACT = :subtract
  MULTIPLY = :multiply
  DIVIDE = :divide
  MOD = :mod
  L_FLOOR = :l_floor
  R_FLOOR = :r_floor
  L_CEILING = :l_ceiling
  R_CEILING = :r_ceiling
  ROOT = :root
  ROOT_3 = :root_3
  ROOT_4 = :root_4
  NOT = :not
  AND = :and
  NAND = :nand
  OR = :or
  NOR = :nor
  XOR = :xor
  XNOR = :xnor
  IN = :in
  NUMBER = :number
  SUP_NUMBER = :sup_number
  NSUP_NUMBER = :nsup_number
  SUB_NUMBER = :sub_number
  FUNCTION = :function
  UNIT = :unit
  CURRENCY = :currency
  VARIABLE = :variable
  SHIFT_LEFT = :shift_left
  SHIFT_RIGHT = :shift_right
  SHIFT_URIGHT = :shift_uright
  ASSIGN = :assign
  L_R_BRACKET = :l_r_bracket
  R_R_BRACKET = :r_r_bracket
  L_S_BRACKET = :l_s_bracket
  R_S_BRACKET = :r_s_bracket
  L_C_BRACKET = :l_c_bracket
  R_C_BRACKET = :r_c_bracket
  ABS = :abs
  POWER = :power
  FACTORIAL = :factorial
  PERCENTAGE = :percentage
  ARGUMENT_SEPARATOR = :argument_separator
  FUNC_DESC_SEPARATOR = :func_desc_separator

  # The operator and bracket tokens the pre-lexer already resolves on its own,
  # which the lexer therefore passes straight through.
  PASSTHROUGH = [
    AND, OR, XOR, NOT, NAND, NOR, XNOR,
    ADD, SUBTRACT, MULTIPLY, DIVIDE,
    L_FLOOR, R_FLOOR, L_CEILING, R_CEILING,
    ROOT, ROOT_3, ROOT_4, ASSIGN,
    L_R_BRACKET, R_R_BRACKET, L_S_BRACKET, R_S_BRACKET, L_C_BRACKET, R_C_BRACKET,
    ABS, POWER, FACTORIAL, PERCENTAGE,
    ARGUMENT_SEPARATOR, SHIFT_LEFT, SHIFT_RIGHT, SHIFT_URIGHT, FUNC_DESC_SEPARATOR,
  ].freeze
end

# PreLexer walks the input one character at a time and classifies each one.
#
# Ported from upstream's PreLexer in lib/equation-lexer.vala. Upstream's
# `index` and `mark_index` are byte offsets into the stream; here they are
# character offsets, which is what the display and the error highlighting both
# want anyway.
class PreLexer
  SUPER_DIGITS = %w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze
  SUB_DIGITS = %w[₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉].freeze
  FRACTIONS = %w[½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞].freeze

  # One character to one token type, for every character that does not need a
  # range test.
  CHARACTERS = {
    '∧'  => LexerTokenType::AND,
    '⊼'  => LexerTokenType::NAND,
    '∨'  => LexerTokenType::OR,
    '⊽'  => LexerTokenType::NOR,
    '⊻'  => LexerTokenType::XOR,
    '⊕'  => LexerTokenType::XOR,
    '⊙'  => LexerTokenType::XNOR,
    '¬'  => LexerTokenType::NOT,
    '~'  => LexerTokenType::NOT,
    '+'  => LexerTokenType::ADD,
    '-'  => LexerTokenType::SUBTRACT,
    '−'  => LexerTokenType::SUBTRACT,
    '–'  => LexerTokenType::SUBTRACT,
    '*'  => LexerTokenType::MULTIPLY,
    '×'  => LexerTokenType::MULTIPLY,
    '/'  => LexerTokenType::DIVIDE,
    '∕'  => LexerTokenType::DIVIDE,
    '÷'  => LexerTokenType::DIVIDE,
    '⌊'  => LexerTokenType::L_FLOOR,
    '⌋'  => LexerTokenType::R_FLOOR,
    '⌈'  => LexerTokenType::L_CEILING,
    '⌉'  => LexerTokenType::R_CEILING,
    '√'  => LexerTokenType::ROOT,
    '∛'  => LexerTokenType::ROOT_3,
    '∜'  => LexerTokenType::ROOT_4,
    '='  => LexerTokenType::ASSIGN,
    '('  => LexerTokenType::L_R_BRACKET,
    ')'  => LexerTokenType::R_R_BRACKET,
    '['  => LexerTokenType::L_S_BRACKET,
    ']'  => LexerTokenType::R_S_BRACKET,
    '{'  => LexerTokenType::L_C_BRACKET,
    '}'  => LexerTokenType::R_C_BRACKET,
    '|'  => LexerTokenType::ABS,
    '^'  => LexerTokenType::POWER,
    '!'  => LexerTokenType::FACTORIAL,
    '%'  => LexerTokenType::PERCENTAGE,
    ';'  => LexerTokenType::ARGUMENT_SEPARATOR,
    '⋙'  => LexerTokenType::SHIFT_URIGHT,
    '»'  => LexerTokenType::SHIFT_RIGHT,
    '≫'  => LexerTokenType::SHIFT_RIGHT,
    '«'  => LexerTokenType::SHIFT_LEFT,
    '≪'  => LexerTokenType::SHIFT_LEFT,
    ' '  => LexerTokenType::PL_SKIP,
    "\r" => LexerTokenType::PL_SKIP,
    "\t" => LexerTokenType::PL_SKIP,
    "\n" => LexerTokenType::PL_SKIP,
    '@'  => LexerTokenType::FUNC_DESC_SEPARATOR,
    ','  => LexerTokenType::PL_DECIMAL,
    '.'  => LexerTokenType::PL_DECIMAL,
    '˚'  => LexerTokenType::PL_DEGREE,
    '°'  => LexerTokenType::PL_DEGREE,
    "'"  => LexerTokenType::PL_MINUTE,
    '′'  => LexerTokenType::PL_MINUTE,
    '’'  => LexerTokenType::PL_MINUTE,
    '"'  => LexerTokenType::PL_SECOND,
    '″'  => LexerTokenType::PL_SECOND,
    '”'  => LexerTokenType::PL_SECOND,
    '_'  => LexerTokenType::PL_LETTER,
    '\\' => LexerTokenType::PL_LETTER,
  }.freeze

  attr_reader :stream, :index, :mark_index

  def initialize(input)
    @stream = input
    @chars = input.chars
    @index = 0
    @mark_index = 0
    @eos = false
  end

  # Rolls back the last scanned character. Rolling back from PL_EOS has no
  # effect, which is why the end of stream is flagged rather than inferred.
  def roll_back
    if @eos
      @eos = false
    elsif @index.positive?
      @index -= 1
    end
  end

  def set_marker
    @mark_index = @index
  end

  def marked_substring = @chars[@mark_index...@index].join

  def get_next_token
    if @index >= @chars.length
      @eos = true
      LexerTokenType::PL_EOS
    else
      char = @chars[@index]
      @index += 1
      @eos = false
      classify(char)
    end
  end

  private

    def classify(char)
      if char.match?(/[0-9]/)
        LexerTokenType::PL_DIGIT
      elsif char.match?(/[a-fA-F]/)
        LexerTokenType::PL_HEX
      elsif SUPER_DIGITS.include?(char)
        LexerTokenType::PL_SUPER_DIGIT
      elsif char == '⁻'
        LexerTokenType::PL_SUPER_MINUS
      elsif SUB_DIGITS.include?(char)
        LexerTokenType::PL_SUB_DIGIT
      elsif FRACTIONS.include?(char)
        LexerTokenType::PL_FRACTION
      elsif CHARACTERS.key?(char)
        CHARACTERS[char]
      elsif char.match?(/[[:alpha:]]/)
        LexerTokenType::PL_LETTER
      else
        LexerTokenType::UNKNOWN
      end
    end
end

# One token: the text, where it sits in the original stream, and its type.
#
# Ported from upstream's LexerToken in lib/equation-lexer.vala.
class LexerToken
  attr_accessor :text, :start_index, :end_index, :type

  def initialize(text, start_index, end_index, type)
    @text = text
    @start_index = start_index
    @end_index = end_index
    @type = type
  end
end

# Lexer turns the pre-lexer's character classes into the tokens the parser
# consumes, asking the parser whether a name is a function, a unit, a currency
# or a variable.
#
# Ported from upstream's Lexer in lib/equation-lexer.vala.
class Lexer
  attr_reader :tokens

  def initialize(input, parser, number_base = 10)
    @prelexer = PreLexer.new(input)
    @tokens = []
    @next_token = 0
    @parser = parser
    @number_base = number_base
  end

  def scan
    loop do
      token = insert_next_token
      @tokens << token
      if token.type == LexerTokenType::PL_EOS
        break
      end
    end
    demote_bare_units
  end

  def get_next_token
    if @next_token >= @tokens.length
      @tokens.last
    else
      @tokens[@next_token].tap { @next_token += 1 }
    end
  end

  def roll_back
    if @next_token.positive?
      @next_token -= 1
    end
  end

  private

    # A unit or currency name that is not next to an "in" is a variable: "e"
    # is Euler's number, not the symbol for an erg.
    def demote_bare_units
      @tokens.each_with_index do |token, i|
        if [LexerTokenType::UNIT, LexerTokenType::CURRENCY].include?(token.type) &&
           !neighbour_is_in?(i - 1) && !neighbour_is_in?(i + 1) &&
           !token.text.start_with?('°', '˚')
          token.type = LexerTokenType::VARIABLE
        end
      end
    end

    def neighbour_is_in?(index)
      if index.negative? || index >= @tokens.length
        false
      else
        @tokens[index].type == LexerTokenType::IN
      end
    end

    def function?
      @parser.function_is_defined(@prelexer.marked_substring)
    end

    def literal_base?
      @parser.literal_base_is_defined(@prelexer.marked_substring.downcase)
    end

    # A unit may carry a superscript — m³ — so the superscripts are offered to
    # the parser first and rolled back if the shorter name is the unit.
    def unit?
      named_with_superscript? { |name| @parser.unit_is_defined(name) }
    end

    def currency?
      named_with_superscript? { |name| @parser.currency_is_defined(name) }
    end

    def named_with_superscript?
      super_count = 0
      while @prelexer.get_next_token == LexerTokenType::PL_SUPER_DIGIT
        super_count += 1
      end
      @prelexer.roll_back

      if yield(@prelexer.marked_substring)
        true
      else
        super_count.times { @prelexer.roll_back }
        yield(@prelexer.marked_substring)
      end
    end

    # Whether the marked text parses as a number, rolling characters back one
    # at a time to see whether a shorter prefix does.
    def number?
      text = @prelexer.marked_substring
      if Number.from_string(text, @number_base)
        true
      else
        shorter_number?(text)
      end
    end

    def shorter_number?(text)
      count = 0
      found = false
      while !text.empty? && !found
        if Number.from_string(text, @number_base)
          found = true
        else
          count += 1
          @prelexer.roll_back
          text = @prelexer.marked_substring
        end
      end
      unless found
        count.times { @prelexer.get_next_token }
      end
      found
    end

    def insert_token(type)
      LexerToken.new(
        @prelexer.marked_substring,
        @prelexer.mark_index,
        @prelexer.index,
        type,
      )
    end

    def insert_next_token
      type = skip_whitespace
      if LexerTokenType::PASSTHROUGH.include?(type)
        insert_token(type)
      elsif type == LexerTokenType::PL_SUPER_MINUS
        insert_negative_superscript
      elsif type == LexerTokenType::PL_SUPER_DIGIT
        consume_while(LexerTokenType::PL_SUPER_DIGIT)
        insert_token(LexerTokenType::SUP_NUMBER)
      elsif type == LexerTokenType::PL_SUB_DIGIT
        consume_while(LexerTokenType::PL_SUB_DIGIT)
        insert_token(LexerTokenType::SUB_NUMBER)
      elsif type == LexerTokenType::PL_FRACTION
        insert_token(LexerTokenType::NUMBER)
      elsif type == LexerTokenType::PL_DIGIT
        insert_digit
      elsif type == LexerTokenType::PL_DECIMAL
        insert_decimal
      elsif type == LexerTokenType::PL_HEX
        insert_hex
      elsif type == LexerTokenType::PL_LETTER
        insert_letter
      elsif type == LexerTokenType::PL_DEGREE
        insert_degree
      elsif type == LexerTokenType::PL_EOS
        insert_token(LexerTokenType::PL_EOS)
      else
        @parser.set_error(
          ErrorCode::INVALID,
          @prelexer.marked_substring,
          @prelexer.mark_index,
          @prelexer.index,
        )
        insert_token(LexerTokenType::UNKNOWN)
      end
    end

    def skip_whitespace
      @prelexer.set_marker
      type = @prelexer.get_next_token
      while type == LexerTokenType::PL_SKIP
        @prelexer.set_marker
        type = @prelexer.get_next_token
      end
      type
    end

    # Consumes a run of `type`, leaving the first character that is not one of
    # them unread.
    def consume_while(type)
      while @prelexer.get_next_token == type
        # Keep going; the pre-lexer advances on each call.
      end
      @prelexer.roll_back
    end

    def insert_negative_superscript
      if @prelexer.get_next_token == LexerTokenType::PL_SUPER_DIGIT
        consume_while(LexerTokenType::PL_SUPER_DIGIT)
        insert_token(LexerTokenType::NSUP_NUMBER)
      else
        @prelexer.roll_back
        error_token('Missing digits after minus sign')
      end
    end

    def insert_degree
      type = @prelexer.get_next_token
      if [LexerTokenType::PL_HEX, LexerTokenType::PL_LETTER].include?(type) && unit?
        insert_token(LexerTokenType::UNIT)
      else
        @parser.set_error(
          ErrorCode::INVALID,
          @prelexer.marked_substring,
          @prelexer.mark_index,
          @prelexer.index,
        )
        insert_token(LexerTokenType::UNKNOWN)
      end
    end

    def error_token(message)
      @parser.set_error(
        ErrorCode::MP,
        message,
        @prelexer.mark_index,
        @prelexer.index,
      )
      insert_token(LexerTokenType::UNKNOWN)
    end

    def insert_digit
      type = @prelexer.get_next_token
      while type == LexerTokenType::PL_DIGIT
        type = @prelexer.get_next_token
      end

      if type == LexerTokenType::PL_FRACTION
        insert_token(LexerTokenType::NUMBER)
      elsif type == LexerTokenType::PL_SUB_DIGIT
        consume_while(LexerTokenType::PL_SUB_DIGIT)
        insert_token(LexerTokenType::NUMBER)
      elsif type == LexerTokenType::PL_DEGREE
        insert_angle
      elsif type == LexerTokenType::PL_DECIMAL
        insert_decimal
      elsif literal_base?
        insert_hex
      elsif type == LexerTokenType::PL_HEX
        insert_hex_dec
      else
        @prelexer.roll_back
        insert_token(LexerTokenType::NUMBER)
      end
    end

    # A degree sign after the digits opens an angle: 1°, 1°2′ or 1°2′3″.
    def insert_angle
      type = @prelexer.get_next_token
      if type == LexerTokenType::PL_DIGIT
        type = @prelexer.get_next_token
        while type == LexerTokenType::PL_DIGIT
          type = @prelexer.get_next_token
        end
        insert_angle_minutes(type)
      elsif type == LexerTokenType::PL_DECIMAL
        insert_angle_num_dm
      else
        @prelexer.roll_back
        insert_token(LexerTokenType::NUMBER)
      end
    end

    def insert_angle_minutes(type)
      if type == LexerTokenType::PL_DECIMAL
        insert_angle_num_dm
      elsif type == LexerTokenType::PL_MINUTE
        insert_angle_seconds
      else
        @prelexer.roll_back
        error_token('Missing minute symbol (′)')
      end
    end

    def insert_angle_seconds
      type = @prelexer.get_next_token
      if type == LexerTokenType::PL_DIGIT
        type = @prelexer.get_next_token
        while type == LexerTokenType::PL_DIGIT
          type = @prelexer.get_next_token
        end
        if type == LexerTokenType::PL_DECIMAL
          insert_angle_num_dms
        elsif type == LexerTokenType::PL_SECOND
          insert_token(LexerTokenType::NUMBER)
        else
          @prelexer.roll_back
          error_token('Missing second symbol (″)')
        end
      elsif type == LexerTokenType::PL_DECIMAL
        insert_angle_num_dms
      else
        @prelexer.roll_back
        insert_token(LexerTokenType::NUMBER)
      end
    end

    def insert_angle_num_dm
      type = @prelexer.get_next_token
      if type != LexerTokenType::PL_DIGIT
        @prelexer.roll_back
        error_token('Missing digits after decimal point')
      else
        while type == LexerTokenType::PL_DIGIT
          type = @prelexer.get_next_token
        end
        if type == LexerTokenType::PL_MINUTE
          insert_token(LexerTokenType::NUMBER)
        else
          @prelexer.roll_back
          error_token('Missing minute symbol (′)')
        end
      end
    end

    def insert_angle_num_dms
      type = @prelexer.get_next_token
      if type != LexerTokenType::PL_DIGIT
        @prelexer.roll_back
        error_token('Missing digits after decimal point')
      else
        type = @prelexer.get_next_token
        while type == LexerTokenType::PL_DIGIT
          type = @prelexer.get_next_token
        end
        if type == LexerTokenType::PL_SECOND
          insert_token(LexerTokenType::NUMBER)
        else
          @prelexer.roll_back
          error_token('Missing second symbol (″)')
        end
      end
    end

    def insert_decimal
      type = @prelexer.get_next_token
      if type == LexerTokenType::PL_DIGIT
        type = @prelexer.get_next_token
        while type == LexerTokenType::PL_DIGIT
          type = @prelexer.get_next_token
        end
        insert_after_decimal_digits(type)
      elsif type == LexerTokenType::PL_HEX
        insert_decimal_hex
      else
        @prelexer.roll_back
        error_token('Missing digits after decimal point')
      end
    end

    def insert_after_decimal_digits(type)
      if type == LexerTokenType::PL_DEGREE
        insert_token(LexerTokenType::NUMBER)
      elsif type == LexerTokenType::PL_HEX
        insert_decimal_hex
      elsif type == LexerTokenType::PL_SUB_DIGIT
        consume_while(LexerTokenType::PL_SUB_DIGIT)
        insert_token(LexerTokenType::NUMBER)
      else
        @prelexer.roll_back
        insert_token(LexerTokenType::NUMBER)
      end
    end

    def insert_hex
      type = @prelexer.get_next_token
      while type == LexerTokenType::PL_HEX
        type = @prelexer.get_next_token
      end

      if type == LexerTokenType::PL_DIGIT
        insert_hex_dec
      elsif type == LexerTokenType::PL_DECIMAL
        insert_decimal_hex
      elsif type == LexerTokenType::PL_SUB_DIGIT
        consume_while(LexerTokenType::PL_SUB_DIGIT)
        insert_number_or_name
      elsif type == LexerTokenType::PL_LETTER
        insert_letter
      else
        @prelexer.roll_back
        insert_number_or_name
      end
    end

    def insert_number_or_name
      if number?
        insert_token(LexerTokenType::NUMBER)
      elsif function?
        insert_token(LexerTokenType::FUNCTION)
      elsif currency?
        insert_token(LexerTokenType::CURRENCY)
      elsif unit?
        insert_token(LexerTokenType::UNIT)
      else
        insert_token(LexerTokenType::VARIABLE)
      end
    end

    def insert_hex_dec
      type = @prelexer.get_next_token
      while [LexerTokenType::PL_DIGIT, LexerTokenType::PL_HEX].include?(type)
        type = @prelexer.get_next_token
      end

      if type == LexerTokenType::PL_DECIMAL
        insert_decimal_hex
      elsif type == LexerTokenType::PL_SUB_DIGIT
        consume_while(LexerTokenType::PL_SUB_DIGIT)
        insert_token(LexerTokenType::NUMBER)
      elsif number?
        insert_token(LexerTokenType::NUMBER)
      else
        @parser.set_error(
          ErrorCode::MP,
          @prelexer.marked_substring,
          @prelexer.mark_index,
          @prelexer.index,
        )
        insert_token(LexerTokenType::UNKNOWN)
      end
    end

    def insert_decimal_hex
      type = @prelexer.get_next_token
      if ![LexerTokenType::PL_DIGIT, LexerTokenType::PL_HEX].include?(type)
        @prelexer.roll_back
        error_token('Missing digits after decimal point')
      else
        while [LexerTokenType::PL_DIGIT, LexerTokenType::PL_HEX].include?(type)
          type = @prelexer.get_next_token
        end
        while type == LexerTokenType::PL_SUB_DIGIT
          type = @prelexer.get_next_token
        end
        @prelexer.roll_back
        insert_token(LexerTokenType::NUMBER)
      end
    end

    # The words that are operators rather than names. "in" and "to" are the
    # conversion keywords the converter and the search provider both accept.
    KEYWORDS = {
      'mod'    => LexerTokenType::MOD,
      'and'    => LexerTokenType::AND,
      'nand'   => LexerTokenType::NAND,
      '\\cdot' => LexerTokenType::MULTIPLY,
      'or'     => LexerTokenType::OR,
      'nor'    => LexerTokenType::NOR,
      'xor'    => LexerTokenType::XOR,
      'xnor'   => LexerTokenType::XNOR,
      'nxor'   => LexerTokenType::XNOR,
      'not'    => LexerTokenType::NOT,
      'in'     => LexerTokenType::IN,
      'to'     => LexerTokenType::IN,
    }.freeze

    def insert_letter
      type = @prelexer.get_next_token
      while [LexerTokenType::PL_LETTER, LexerTokenType::PL_HEX].include?(type)
        type = @prelexer.get_next_token
      end
      while type == LexerTokenType::PL_SUB_DIGIT
        type = @prelexer.get_next_token
      end
      @prelexer.roll_back

      name = @prelexer.marked_substring.downcase
      if KEYWORDS.key?(name)
        insert_token(KEYWORDS[name])
      elsif function?
        insert_token(LexerTokenType::FUNCTION)
      elsif currency?
        insert_token(LexerTokenType::CURRENCY)
      elsif unit?
        insert_token(LexerTokenType::UNIT)
      else
        insert_token(LexerTokenType::VARIABLE)
      end
    end
end
