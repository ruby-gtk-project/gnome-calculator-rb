# frozen_string_literal: true

require_relative 'number'

# How a Number is rendered as text.
#
# Ported from the DisplayFormat enum in upstream's lib/serializer.vala.
module DisplayFormat
  AUTOMATIC = :automatic
  FIXED = :fixed
  SCIENTIFIC = :scientific
  ENGINEERING = :engineering

  ALL = [AUTOMATIC, FIXED, SCIENTIFIC, ENGINEERING].freeze
end

# Serializer renders a Number as the string the display shows, and parses one
# back.
#
# Ported from upstream's lib/serializer.vala. Every digit is produced by
# Number arithmetic rather than by formatting a float, which is what lets a
# value be shown in any base from 2 to 16 at the full internal precision.
#
# Upstream asks nl_langinfo for the locale's radix character and thousands
# separator. Ruby has no binding for nl_langinfo, so this port starts from the
# values nl_langinfo answers in the C locale — '.' and a space — and leaves
# radix= and thousands_separator= for the preferences to set.
class Serializer
  DIGITS = '0123456789ABCDEF'
  SUB_DIGITS = %w[₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉].freeze
  SUPER_DIGITS = %w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ᴬ ᴮ ᶜ ᴰ ᴱ ᶠ].freeze

  # Set when an error — a precision error while converting, say — stopped the
  # conversion.
  attr_accessor :error
  # Whether to refuse a value larger than `fixed_max` in FIXED format.
  attr_accessor :check_fixed_max

  class << self
    # The largest value FIXED format will display, or nil for no limit.
    attr_accessor :fixed_max
  end

  def initialize(format, number_base, trailing_digits)
    @radix = '.'
    @tsep = ' '
    @tsep_count = 3
    @number_base = number_base
    @representation_base = number_base
    @leading_digits = 12
    @trailing_digits = trailing_digits
    @show_zeroes = false
    @show_tsep = false
    @format = format
    @error = nil
    @check_fixed_max = true
    update_zero_string
  end

  def to_string(x, budget = nil)
    @error = nil
    if !x.finite?
      non_finite_string(x)
    elsif @representation_base != @number_base
      # A base conversion equation always renders in FIXED format.
      cast_to_string(x, budget).first
    else
      formatted_string(x, budget)
    end
  end

  # Degrees, minutes and seconds, carrying 60′ and 60″ up the way upstream
  # does so 1°59′60″ reads as 2°0′0″.
  def to_dms_string(number)
    epsilon = number.multiply(Number.integer(2).xpowy_integer(8 - Number.precision)).abs
    number = snap(number, epsilon)
    minute = snap(number.fractional_component.multiply_integer(60), epsilon)

    degrees = to_string(number.integer_component)
    minutes = to_string(minute.integer_component)
    seconds = to_string(minute.fractional_component.multiply_integer(60))
    if seconds.start_with?('60')
      seconds = @zero_string
      if minutes.start_with?('59')
        minutes = @zero_string
        degrees = to_string(number.integer_component.add(Number.integer(1)))
      else
        minutes = to_string(minute.integer_component.add(Number.integer(1)))
      end
    end
    format(
      '%s°%s′%s″',
      degrees,
      minutes,
      seconds,
    )
  end

  def from_string(str) = Number.from_string(str, @number_base)

  attr_reader :number_base, :representation_base, :radix, :leading_digits, :trailing_digits

  def number_base=(value)
    @number_base = value
  end

  def representation_base=(value)
    @representation_base = value
  end

  def radix=(value)
    @radix = value
    update_zero_string
  end

  def thousands_separator
    if @representation_base == 10
      @tsep
    else
      ' '
    end
  end

  def thousands_separator=(separator)
    @tsep = separator
  end

  def thousands_separator?(char) = char == @tsep || char == ' '

  def thousands_separator_count
    if @representation_base == 10
      @tsep_count
    else
      4
    end
  end

  def thousands_separator_count=(count)
    @tsep_count = count
  end

  def show_thousands_separators = @show_tsep

  def show_thousands_separators=(visible)
    @show_tsep = visible
  end

  def show_trailing_zeroes = @show_zeroes

  def show_trailing_zeroes=(visible)
    @show_zeroes = visible
    update_zero_string
  end

  def leading_digits=(value)
    @leading_digits = value
  end

  def trailing_digits=(value)
    @trailing_digits = value
    update_zero_string
  end

  def number_format = @format

  def number_format=(value)
    @format = value
  end

  private

    def non_finite_string(x)
      infinity = x.to_double.infinite?
      if infinity.nil?
        'NaN'
      elsif infinity.positive?
        '∞'
      else
        '−∞'
      end
    end

    def formatted_string(x, budget)
      case @format
      when DisplayFormat::FIXED
        cast_to_string(x, budget).first
      when DisplayFormat::SCIENTIFIC
        exponential_or_automatic(x, false, budget)
      when DisplayFormat::ENGINEERING
        exponential_or_automatic(x, true, budget)
      else
        to_automatic_string(x, false, budget)
      end
    end

    def exponential_or_automatic(x, eng_format, budget)
      if @representation_base == 10
        cast_to_exponential_string(x, eng_format, budget)
      else
        to_automatic_string(x, eng_format, budget)
      end
    end

    def snap(number, epsilon)
      rounded = number.round
      if number.subtract(rounded).abs.compare(epsilon) < 0
        rounded
      else
        number
      end
    end

    def update_zero_string
      @zero_string = cast_to_string(Number.integer(0)).first
    end

    # The leading-digit budget each representation base gets before the value
    # is shown in exponential form instead.
    AUTOMATIC_LEADING_DIGITS = { 2 => 64, 8 => 22, 16 => 16 }.freeze

    def to_automatic_string(x, eng_format, budget = nil)
      text, n_digits = cast_to_string(x, budget)
      @error = nil
      allowed = AUTOMATIC_LEADING_DIGITS.fetch(@representation_base, @leading_digits)
      if n_digits <= allowed && text != @zero_string
        text
      else
        cast_to_exponential_string(x, eng_format, budget)
      end
    end

    # Answers [text, digit count]; upstream passes the digit count back through
    # a `ref int n_digits` parameter.
    def cast_to_string(x, budget = nil)
      real_text, n_digits = cast_to_string_real(
        x.real_component,
        false,
        0,
        budget,
      )
      if real_text.nil?
        [@zero_string, n_digits]
      elsif x.complex?
        cast_to_string_complex(
          x,
          real_text,
          n_digits,
          budget,
        )
      else
        [real_text, n_digits]
      end
    end

    def cast_to_string_complex(x, real_text, n_digits, budget)
      force_sign = true
      if real_text == @zero_string
        real_text = ''
        force_sign = false
      end

      imaginary_text, n_complex_digits = cast_to_string_real(
        x.imaginary_component,
        force_sign,
        0,
        budget,
      )
      if imaginary_text.nil?
        [@zero_string, n_digits]
      else
        digits = [n_digits, n_complex_digits].max
        [real_text + imaginary_suffix(imaginary_text, real_text), digits]
      end
    end

    def imaginary_suffix(imaginary_text, real_text)
      if [@zero_string, "+#{@zero_string}", "−#{@zero_string}"].include?(imaginary_text)
        # The real component is empty and the imaginary one vanishingly small;
        # a blank display would be worse than a zero.
        if real_text.empty?
          @zero_string
        else
          ''
        end
      elsif imaginary_text == '1'
        'i'
      elsif imaginary_text == '+1'
        '+i'
      elsif imaginary_text == '−1'
        '−i'
      else
        "#{imaginary_text}i"
      end
    end

    # Answers [text, digit count], or [nil, digit count] once @error is set.
    def cast_to_string_real(x, force_sign, n_digits, budget = nil)
      number = x
      if number.negative?
        number = number.abs
      end
      if @check_fixed_max && self.class.fixed_max && number.compare(self.class.fixed_max) > 0
        @error = 'The result is too long to display in fixed format. Try other result formats'
        [nil, n_digits]
      else
        render_real(
          x,
          number,
          force_sign,
          n_digits,
          budget,
        )
      end
    end

    def render_real(x, number, force_sign, n_digits, budget)
      rounded = number.add(rounding_factor)
      integer_text, n_digits = integer_digits(rounded, n_digits, budget)
      if integer_text.nil?
        [nil, n_digits]
      else
        fraction_text, n_digits = fraction_digits(rounded, n_digits, budget)
        if fraction_text.nil?
          [nil, n_digits]
        else
          [sign_prefix(x, integer_text + fraction_text, force_sign) + base_suffix, n_digits]
        end
      end
    end

    # base^-(trailing+1) × base ÷ 2 — half of the last displayed digit, which
    # is what makes the truncating digit loop below round.
    def rounding_factor
      Number.integer(current_base)
        .xpowy_integer(-(@trailing_digits + 1))
        .multiply_integer(current_base)
        .divide_integer(2)
    end

    def current_base = @representation_base.to_i

    def integer_digits(rounded, n_digits, budget)
      text = ''
      temp = rounded.floor
      run = 0
      overflowed = false
      loop do
        breach = output_digit_breach(budget, n_digits + 1)
        if breach
          @error = breach.message
          overflowed = true
        end
        if overflowed
          break
        end
        if @show_tsep && run == thousands_separator_count
          text = thousands_separator + text
          run = 0
        end
        run += 1

        quotient = temp.divide_integer(current_base).floor
        digit = temp.subtract(quotient.multiply_integer(current_base)).to_integer
        if digit >= 16 || digit.negative?
          @error = 'The result is too long to display in fixed format. Try other result formats'
          overflowed = true
        else
          text = DIGITS[digit] + text
          n_digits += 1
          temp = quotient
        end
        if overflowed || temp.zero?
          break
        end
      end
      if overflowed
        [nil, n_digits]
      else
        [text, n_digits]
      end
    end

    # Only the integer digits are counted: the digit count decides whether the
    # value fits the display, and upstream counts it in the integer loop alone.
    def fraction_digits(rounded, n_digits, budget)
      digits = ''
      temp = rounded.fractional_component
      overflowed = false
      @trailing_digits.times do
        unless overflowed || temp.zero?
          breach = output_digit_breach(budget, n_digits + 1)
          if breach
            @error = breach.message
            overflowed = true
          else
            temp = temp.multiply_integer(current_base)
            digit = temp.floor
            digits += DIGITS[digit.to_integer]
            temp = temp.subtract(digit)
          end
        end
      end
      if overflowed
        [nil, n_digits]
      else
        [trimmed_fraction(digits), n_digits]
      end
    end

    def trimmed_fraction(digits)
      if !@show_zeroes || @trailing_digits.zero?
        stripped = digits.sub(/0+\z/, '')
        if stripped.empty?
          ''
        else
          @radix + stripped
        end
      else
        @radix + digits
      end
    end

    def output_digit_breach(budget, digits)
      if budget
        budget.check_output_digits(digits)
      end
    end

    def sign_prefix(x, text, force_sign)
      if text == '0' && !force_sign
        text
      elsif x.negative?
        "−#{text}"
      elsif force_sign
        "+#{text}"
      else
        text
      end
    end

    # The subscript base a value rendered outside the equation's own base
    # carries, e.g. the ₁₆ of FF₁₆.
    def base_suffix
      if current_base == @number_base
        ''
      else
        current_base.to_s.each_char.map { |digit| SUB_DIGITS[digit.to_i] }.join
      end
    end

    def cast_to_exponential_string(x, eng_format, budget = nil)
      text, exponent = exponential_real(
        x.real_component,
        eng_format,
        false,
        budget,
      )
      text += exponent_suffix(exponent)

      if x.complex?
        force_sign = true
        if text == @zero_string
          text = ''
          force_sign = false
        end
        imaginary, exponent = exponential_real(
          x.imaginary_component,
          eng_format,
          force_sign,
          budget,
        )
        text += exponential_imaginary_suffix(imaginary)
        text += exponent_suffix(exponent)
      end
      text
    end

    def exponential_imaginary_suffix(imaginary)
      if %w[0 +0 −0].include?(imaginary)
        ''
      elsif imaginary == '1'
        'i'
      elsif imaginary == '+1'
        '+i'
      elsif imaginary == '−1'
        '−i'
      else
        "#{imaginary}i"
      end
    end

    # Answers [mantissa text, exponent].
    def exponential_real(x, eng_format, force_sign, budget)
      sign = ''
      if x.negative?
        sign = '−'
      elsif force_sign
        sign = '+'
      end

      mantissa = x.abs
      exponent = 0
      unless mantissa.zero?
        exponent, mantissa = normalise_mantissa(mantissa, eng_format)
      end

      text, = cast_to_string(mantissa, budget)
      text, exponent = carry_mantissa(text, exponent, eng_format)
      [sign + text, exponent]
    end

    def normalise_mantissa(mantissa, eng_format)
      numeric_base = Number.integer(@number_base)
      exponent = mantissa.logarithm(numeric_base).floor.to_integer
      # Integer#remainder, not #%: Vala's % truncates toward zero and Ruby's
      # floors, and the engineering exponent has to land on the multiple of
      # three at or below the exponent either way.
      if eng_format && !exponent.remainder(3).zero?
        if exponent.positive?
          exponent -= exponent.remainder(3)
        else
          exponent -= exponent.remainder(3) + 3
        end
      end
      [exponent, mantissa.divide(numeric_base.xpowy_integer(exponent))]
    end

    # Rounding the mantissa can push it up to the next power, e.g. 9.99 → 10;
    # carrying it keeps a single digit before the radix.
    def carry_mantissa(text, exponent, eng_format)
      if eng_format
        stripped = text.gsub(@tsep, '')
        if stripped.start_with?('1000')
          ["1#{stripped[4..]}", exponent + 3]
        else
          [stripped, exponent]
        end
      elsif text.start_with?('10')
        ["1#{text[2..]}", exponent + 1]
      else
        [text, exponent]
      end
    end

    def exponent_suffix(exponent)
      if exponent.zero?
        ''
      else
        remaining = exponent.abs
        digits = []
        while remaining.positive? || digits.empty?
          digits.unshift(SUPER_DIGITS[remaining % @number_base])
          remaining /= @number_base
        end
        sign = ''
        if exponent.negative?
          sign = '⁻'
        end
        "×10#{sign}#{digits.join}"
      end
    end
end
