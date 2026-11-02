# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/math'

require_relative 'serializer'

# The angle unit a trigonometric operation interprets its argument in.
#
# Ported from the AngleUnit enum at the top of upstream's lib/number.vala.
module AngleUnit
  RADIANS = :radians
  DEGREES = :degrees
  GRADIANS = :gradians

  ALL = [RADIANS, DEGREES, GRADIANS].freeze
end

# Number is an arbitrary precision complex number.
#
# Ported from upstream's lib/number.vala. Upstream stores an MPC complex of two
# MPFR reals at `Number.precision` bits, with an exact GMP rational shadow that
# keeps rational arithmetic exact regardless of binary rounding. This port
# keeps exactly that shape: two BigDecimals carried at the decimal precision
# `Number.precision` bits buy, and a Ruby Rational shadow with the same
# lifecycle — set by the integer and fraction constructors, propagated through
# +, -, × and ÷, and dropped by every operation that can be irrational.
#
# The transcendental functions MPC provides are built here from BigMath's real
# exp/log/sin/cos/atan/sqrt at the working precision, using the standard
# complex identities; the comment on each one names the identity.
#
# ErrorCode is defined in equation.rb, the port of upstream's lib/equation.vala.
class Number
  BD_ZERO = BigDecimal(0)
  BD_ONE = BigDecimal(1)
  BD_TWO = BigDecimal(2)

  INT64_MAX = (2**63) - 1
  INT64_MIN = -(2**63)
  UINT64_MAX = (2**64) - 1
  MASK64 = UINT64_MAX

  # Arith is the MPC/MPFR glue of upstream's number.vala: everything that
  # operates on the raw [real, imaginary] BigDecimal pair rather than on a
  # Number. Kept private to the class for the same reason upstream keeps
  # mpc_from_radians and friends private.
  module Arith
    module_function

    # Significant decimal digits bought by Number.precision bits, plus guard
    # digits so the last displayed digits are not the rounding noise.
    def digits = ((Number.precision * 30_103) / 100_000) + 1

    def working = digits + 20

    def pi
      @pi ||= {}
      @pi[working] ||= BigMath::PI(working)
    end

    def tau = pi * 2

    def eulers
      @eulers ||= {}
      @eulers[working] ||= BigMath::E(working)
    end

    def norm(value) = value.mult(BD_ONE, working)

    def div(numerator, denominator) = numerator.div(denominator, working)

    # BigDecimal#floor, #ceil, #round and #truncate answer an Integer once the
    # digit count is zero, so every integral result is carried back into a
    # BigDecimal here.
    def bd(value) = BigDecimal(value)

    def exp_r(x)
      if x.zero?
        BD_ONE
      else
        BigMath.exp(x, working).tap do |result|
          if result.zero?
            Number.note_underflow
          end
          unless result.finite?
            Number.note_overflow
          end
        end
      end
    end

    def log_r(x) = norm(BigMath.log(x, working))

    def sqrt_r(x) = norm(BigMath.sqrt(x, working))

    def atan_r(x) = norm(BigMath.atan(x, working))

    # BigMath's sine and cosine are Taylor sums, so a large argument costs both
    # terms and accuracy. Reduce into [-π, π] first, exactly as MPFR does.
    def reduce_angle(x)
      turn = tau
      turns = div(x, turn).round
      x - (turn * turns)
    end

    def sin_r(x) = norm(BigMath.sin(reduce_angle(x), working))

    def cos_r(x) = norm(BigMath.cos(reduce_angle(x), working))

    def sinh_r(x) = norm(div(exp_r(x) - exp_r(-x), BD_TWO))

    def cosh_r(x) = norm(div(exp_r(x) + exp_r(-x), BD_TWO))

    def hypot_r(a, b)
      if b.zero?
        a.abs
      elsif a.zero?
        b.abs
      else
        sqrt_r((a * a) + (b * b))
      end
    end

    def atan2_r(y, x)
      if x.positive?
        atan_r(div(y, x))
      elsif x.negative? && !y.negative?
        atan_r(div(y, x)) + pi
      elsif x.negative?
        atan_r(div(y, x)) - pi
      elsif y.positive?
        div(pi, BD_TWO)
      elsif y.negative?
        -div(pi, BD_TWO)
      else
        BD_ZERO
      end
    end

    def c_add(a, b) = [a[0] + b[0], a[1] + b[1]]

    def c_sub(a, b) = [a[0] - b[0], a[1] - b[1]]

    def c_mul(a, b)
      [
        (a[0] * b[0]) - (a[1] * b[1]),
        (a[0] * b[1]) + (a[1] * b[0]),
      ]
    end

    def c_div(a, b)
      denominator = (b[0] * b[0]) + (b[1] * b[1])
      [
        div((a[0] * b[0]) + (a[1] * b[1]), denominator),
        div((a[1] * b[0]) - (a[0] * b[1]), denominator),
      ]
    end

    def c_neg(a) = [-a[0], -a[1]]

    def c_abs(a) = hypot_r(a[0], a[1])

    def c_arg(a) = atan2_r(a[1], a[0])

    # e^(a+bi) = e^a (cos b + i sin b)
    def c_exp(a)
      magnitude = exp_r(a[0])
      if a[1].zero?
        [magnitude, BD_ZERO]
      else
        [norm(magnitude * cos_r(a[1])), norm(magnitude * sin_r(a[1]))]
      end
    end

    # ln(a+bi) = ln|a+bi| + i arg(a+bi)
    def c_log(a)
      if a[1].zero? && a[0].positive?
        [log_r(a[0]), BD_ZERO]
      else
        [log_r(c_abs(a)), c_arg(a)]
      end
    end

    # z^w = e^(w ln z), with the exact real paths kept out of the logarithm.
    def c_pow(a, b)
      if b[1].zero? && b[0].frac.zero? && b[0].abs < BigDecimal(1_000_000)
        c_pow_integer(a, b[0].to_i)
      else
        c_exp(c_mul(b, c_log(a)))
      end
    end

    def c_pow_integer(a, n)
      if n.negative?
        c_div([BD_ONE, BD_ZERO], c_pow_integer(a, -n))
      else
        c_pow_natural(a, n)
      end
    end

    # Exponentiation by squaring, so a large exponent costs log n multiplies.
    def c_pow_natural(a, n)
      result = [BD_ONE, BD_ZERO]
      square = a
      remaining = n
      while remaining.positive?
        if remaining.odd?
          result = c_mul(result, square)
        end
        remaining >>= 1
        if remaining.positive?
          square = c_mul(square, square)
        end
      end
      [norm(result[0]), norm(result[1])]
    end

    def c_sqrt(a)
      if a[1].zero? && !a[0].negative?
        [sqrt_r(a[0]), BD_ZERO]
      else
        magnitude = sqrt_r(c_abs(a))
        half_arg = div(c_arg(a), BD_TWO)
        [norm(magnitude * cos_r(half_arg)), norm(magnitude * sin_r(half_arg))]
      end
    end

    # sin(a+bi) = sin a cosh b + i cos a sinh b
    def c_sin(a)
      if a[1].zero?
        [sin_r(a[0]), BD_ZERO]
      else
        [norm(sin_r(a[0]) * cosh_r(a[1])), norm(cos_r(a[0]) * sinh_r(a[1]))]
      end
    end

    # cos(a+bi) = cos a cosh b − i sin a sinh b
    def c_cos(a)
      if a[1].zero?
        [cos_r(a[0]), BD_ZERO]
      else
        [norm(cos_r(a[0]) * cosh_r(a[1])), norm(-(sin_r(a[0]) * sinh_r(a[1])))]
      end
    end

    def c_tan(a) = c_div(c_sin(a), c_cos(a))

    # sinh(a+bi) = sinh a cos b + i cosh a sin b
    def c_sinh(a)
      if a[1].zero?
        [sinh_r(a[0]), BD_ZERO]
      else
        [norm(sinh_r(a[0]) * cos_r(a[1])), norm(cosh_r(a[0]) * sin_r(a[1]))]
      end
    end

    # cosh(a+bi) = cosh a cos b + i sinh a sin b
    def c_cosh(a)
      if a[1].zero?
        [cosh_r(a[0]), BD_ZERO]
      else
        [norm(cosh_r(a[0]) * cos_r(a[1])), norm(sinh_r(a[0]) * sin_r(a[1]))]
      end
    end

    def c_tanh(a) = c_div(c_sinh(a), c_cosh(a))

    # asin z = −i ln(iz + √(1 − z²))
    def c_asin(a)
      i = [BD_ZERO, BD_ONE]
      inner = c_add(c_mul(i, a), c_sqrt(c_sub([BD_ONE, BD_ZERO], c_mul(a, a))))
      c_mul(c_neg(i), c_log(inner))
    end

    # acos z = π/2 − asin z
    def c_acos(a) = c_sub([div(pi, BD_TWO), BD_ZERO], c_asin(a))

    # atan z = ln((1 + iz) / (1 − iz)) / 2i
    def c_atan(a)
      i = [BD_ZERO, BD_ONE]
      iz = c_mul(i, a)
      quotient = c_div(c_add([BD_ONE, BD_ZERO], iz), c_sub([BD_ONE, BD_ZERO], iz))
      c_div(c_log(quotient), [BD_ZERO, BD_TWO])
    end

    # asinh z = ln(z + √(z² + 1))
    def c_asinh(a) = c_log(c_add(a, c_sqrt(c_add(c_mul(a, a), [BD_ONE, BD_ZERO]))))

    # acosh z = ln(z + √(z² − 1))
    def c_acosh(a) = c_log(c_add(a, c_sqrt(c_sub(c_mul(a, a), [BD_ONE, BD_ZERO]))))

    # atanh z = ln((1 + z) / (1 − z)) / 2
    def c_atanh(a)
      quotient = c_div(c_add([BD_ONE, BD_ZERO], a), c_sub([BD_ONE, BD_ZERO], a))
      c_div(c_log(quotient), [BD_TWO, BD_ZERO])
    end

    # Γ(x) for a real x, which is what upstream's factorial reaches for through
    # mpfr_gamma. Below ½ the reflection formula carries the argument across;
    # above it the value comes from ln Γ.
    def gamma_r(x)
      if x < BigDecimal('0.5')
        # Γ(x) = π / (sin(πx) Γ(1 − x))
        div(pi, sin_r(pi * x) * gamma_r(BD_ONE - x))
      else
        exp_r(log_gamma_r(x))
      end
    end

    # ln Γ(x) by Stirling's series. The series is asymptotic, so the recurrence
    # Γ(z + 1) = z Γ(z) first walks the argument up past the working precision,
    # where the series converges in a few dozen terms, and the product walked
    # over is divided back out in the logarithm.
    def log_gamma_r(x)
      z = x
      product = BD_ONE
      while z < BigDecimal(working)
        product *= z
        z += BD_ONE
      end
      stirling_log_gamma(z) - log_r(product)
    end

    # ln Γ(z) = (z − ½) ln z − z + ½ ln 2π + Σ B₂ₙ / (2n(2n−1) z^(2n−1))
    def stirling_log_gamma(z)
      head = ((z - BigDecimal('0.5')) * log_r(z)) - z + div(log_r(tau), BD_TWO)
      norm(head + stirling_tail(z))
    end

    def stirling_tail(z)
      epsilon = BigDecimal("1e-#{working}")
      square = z * z
      power = z
      sum = BD_ZERO
      n = 1
      converged = false
      while !converged && n <= MAX_STIRLING_TERMS
        term = div(BigDecimal(tangent_number(n)), BigDecimal(stirling_divisor(n)) * power)
        if term.abs < epsilon
          converged = true
        else
          if n.even?
            sum -= term
          else
            sum += term
          end
          power *= square
          n += 1
        end
      end
      sum
    end

    MAX_STIRLING_TERMS = 500

    # B₂ₙ / (2n(2n − 1)) = (−1)^(n−1) Tₙ / (4ⁿ(4ⁿ − 1)(2n − 1)), where Tₙ is the
    # nth tangent number. Going through the tangent numbers keeps the whole
    # coefficient in integers: the Bernoulli recurrence over Rationals spends
    # all its time taking the gcd of several-hundred-digit denominators.
    def stirling_divisor(n) = (4**n) * ((4**n) - 1) * ((2 * n) - 1)

    def tangent_number(index)
      @tangent ||= []
      if @tangent.length <= index
        @tangent = tangent_table([index * 2, 64].max)
      end
      @tangent[index]
    end

    # Brent and Harvey's integer recurrence for the tangent numbers: after it
    # runs, table[k] is Tₖ, the coefficient of x^(2k−1)(2k−1)! in tan x.
    def tangent_table(count)
      Array.new(count + 1, 0).tap do |table|
        table[1] = 1
        (2..count).each { |k| table[k] = (k - 1) * table[k - 1] }
        (2..count).each do |k|
          (k..count).each { |j| table[j] = ((j - k) * table[j - 1]) + ((j - k + 2) * table[j]) }
        end
      end
    end

    # x^y for positive real x: e^(y ln x).
    def pow_r(x, y)
      if y.zero?
        BD_ONE
      elsif x.zero?
        BD_ZERO
      else
        exp_r(y * log_r(x))
      end
    end
  end

  class << self
    attr_writer :error, :error_code

    # Upstream's `Number.precision`, in bits, so the same setting value means
    # the same thing in both ports.
    def precision = @precision ||= 1000

    def precision=(bits)
      @precision = bits
    end

    def error = @error

    def error_code = @error_code ||= ErrorCode::NONE

    def clear_error
      @error = nil
      @error_code = ErrorCode::NONE
    end

    def set_resource_error(code, message)
      @error = message
      @error_code = code
    end

    def note_overflow
      @overflow = true
    end

    def note_underflow
      @underflow = true
    end

    # Upstream reads MPFR's sticky overflow/underflow flags here. The flags are
    # raised by Arith where a BigDecimal result can leave the finite range.
    def check_flags
      if @underflow
        @underflow = false
        @error = 'Underflow error'
      elsif @overflow
        @overflow = false
        @error = 'Overflow error'
      end
    end

    def integer(real, imag = 0)
      decimal(BigDecimal(real), BigDecimal(imag)).tap do |z|
        if imag.zero?
          z.send(:set_exact_rational, real, 1)
        end
      end
    end

    def unsigned_integer(real, imag = 0)
      decimal(BigDecimal(real), BigDecimal(imag)).tap do |z|
        if imag.zero? && real <= INT64_MAX
          z.send(:set_exact_rational, real, 1)
        end
      end
    end

    def fraction(numerator, denominator)
      if denominator.negative?
        fraction(-numerator, -denominator)
      else
        from_exact_rational(Rational(numerator, denominator))
      end
    end

    def from_exact_rational(value)
      real = BigDecimal(value.numerator).div(BigDecimal(value.denominator), Arith.working)
      decimal(real, BD_ZERO).tap do |z|
        z.send(:adopt_exact_rational, value)
      end
    end

    # Upstream's Number.float / Number.double keep the bit pattern of a
    # non-finite value in the mantissa; this port keeps the Float itself, which
    # the serializer reads back through to_double for "∞", "−∞" and "NaN".
    def float(real, imag = 0) = double(real, imag)

    def double(real, imag = 0)
      if real.finite?
        decimal(BigDecimal(real, Arith.digits), BigDecimal(imag, Arith.digits))
      else
        decimal(BD_ZERO, BD_ZERO).tap { |z| z.send(:adopt_non_finite, real) }
      end
    end

    def complex(real_part, imaginary_part)
      decimal(real_part.real_value, imaginary_part.real_value).tap do |z|
        if imaginary_part.zero?
          z.send(:copy_exact_rational, real_part)
        end
      end
    end

    def polar(radius, theta, unit = AngleUnit::RADIANS)
      complex(theta.cos(unit).multiply(radius), theta.sin(unit).multiply(radius))
    end

    def eulers = decimal(Arith.eulers, BD_ZERO)

    def i = integer(0, 1)

    def pi = decimal(Arith.pi, BD_ZERO)

    def tau = decimal(Arith.tau, BD_ZERO)

    # A uniform random number in [0, 1].
    def random = double(Kernel.rand)

    def decimal(real, imag = BD_ZERO) = new(real, imag)

    # Upstream's mp_set_from_string. Parses `str` in `default_base`, honouring a
    # subscript base suffix, a 0x/0o/0b literal prefix, vulgar fractions and
    # sexagesimal degrees, and answers nil when the whole string is not a
    # number.
    def from_string(str, default_base = 10, may_have_prefix = true)
      if str.include?('°')
        from_sexagesimal(str)
      else
        parse_in_base(str, default_base, may_have_prefix)
      end
    end
  end

  SUB_DIGITS = %w[₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉].freeze
  SUPER_DIGITS = %w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze
  VULGAR_FRACTIONS = {
    '½' => [1, 2],
    '⅓' => [1, 3],
    '⅔' => [2, 3],
    '¼' => [1, 4],
    '¾' => [3, 4],
    '⅕' => [1, 5],
    '⅖' => [2, 5],
    '⅗' => [3, 5],
    '⅘' => [4, 5],
    '⅙' => [1, 6],
    '⅚' => [5, 6],
    '⅛' => [1, 8],
    '⅜' => [3, 8],
    '⅝' => [5, 8],
    '⅞' => [7, 8],
  }.freeze
  LITERAL_PREFIXES = { 'b' => 2, 'o' => 8, 'x' => 16 }.freeze
  HEX_DIGITS = '0123456789ABCDEF'

  attr_reader :real_value, :imag_value

  def initialize(real = BD_ZERO, imag = BD_ZERO)
    @real_value = real
    @imag_value = imag
    @force_float = false
    @finite = true
    @non_finite_value = nil
    @rational = nil
  end

  def to_integer = @real_value.truncate.to_i

  def to_unsigned_integer = to_integer

  def to_float = to_double.to_f

  def to_double
    if @finite
      @real_value.to_f
    else
      @non_finite_value
    end
  end

  def force_float = @force_float

  def force_float=(value)
    @force_float = value
  end

  def set_force_float(value)
    @force_float = value
  end

  def zero? = @real_value.zero? && @imag_value.zero?

  def negative? = @real_value.negative?

  def integer?
    if complex?
      false
    else
      @real_value.frac.zero?
    end
  end

  def natural?
    if complex?
      false
    else
      !@real_value.negative? && integer?
    end
  end

  def float?
    if @force_float || !fractional_component.zero?
      true
    else
      compare(self.class.unsigned_integer(UINT64_MAX)) > 0 ||
        compare(self.class.integer(INT64_MIN)) < 0
    end
  end

  def finite? = @finite

  def complex? = !@imag_value.zero?

  # True when the value is 180 × n degrees, the angles whose sine is exactly
  # zero. The radian case allows a precision-sized epsilon, since π is not
  # representable.
  def one_eighty_n_degrees?(unit)
    if complex?
      false
    else
      check = divide(self.class.turn_half(unit))
      if check.integer?
        true
      elsif unit == AngleUnit::RADIANS
        epsilon = multiply(self.class.integer(2).xpowy_integer(-self.class.precision)).abs
        check.subtract(check.round).abs.compare(epsilon) < 0
      else
        false
      end
    end
  end

  # True when the value is 180 × n + 90 degrees, the angles whose cosine is
  # exactly zero.
  def one_eighty_n_plus_ninety_degrees?(unit)
    subtract(self.class.turn_quarter(unit)).one_eighty_n_degrees?(unit)
  end

  def self.turn_half(unit)
    case unit
    when AngleUnit::RADIANS then pi
    when AngleUnit::DEGREES then integer(180)
    when AngleUnit::GRADIANS then integer(200)
    end
  end

  def self.turn_quarter(unit)
    case unit
    when AngleUnit::RADIANS then pi.divide_integer(2)
    when AngleUnit::DEGREES then integer(90)
    when AngleUnit::GRADIANS then integer(100)
    end
  end

  # True when the value cannot be represented in a binary word of `wordlen`
  # bits.
  def overflow?(wordlen, may_be_negative = false)
    maximum = self.class.unsigned_integer(UINT64_MAX >> (64 - wordlen))
    if may_be_negative
      minimum = self.class.integer(-(2**(wordlen - 1)))
      compare(maximum) > 0 || compare(minimum) < 0
    else
      compare(maximum) > 0
    end
  end

  def equals(other) = @real_value == other.real_value && @imag_value == other.imag_value

  def compare(other) = @real_value <=> other.real_value

  def kronecker_delta(other)
    if equals(other)
      self.class.integer(1)
    else
      self.class.integer(0)
    end
  end

  def sgn
    if complex?
      divide(abs)
    else
      self.class.integer(@real_value <=> BD_ZERO)
    end
  end

  def invert_sign
    self.class.decimal(-@real_value, -@imag_value).tap do |z|
      if @rational
        z.send(:adopt_exact_rational, -@rational)
      end
    end
  end

  def abs = self.class.decimal(Arith.c_abs(pair), BD_ZERO)

  def arg(unit = AngleUnit::RADIANS)
    if zero?
      self.class.error = 'Argument not defined for zero'
      self.class.integer(0)
    else
      value = self.class.decimal(Arith.c_arg(pair), BD_ZERO).from_radians(unit)
      # MPC answers −π for a negative real whose imaginary part is −0; +π is
      # wanted for every negative real.
      if !complex? && negative?
        value.abs
      else
        value
      end
    end
  end

  def conjugate = self.class.decimal(@real_value, -@imag_value)

  def real_component
    self.class.decimal(@real_value, BD_ZERO).tap { |z| z.send(:copy_exact_rational, self) }
  end

  def imaginary_component = self.class.decimal(@imag_value, BD_ZERO)

  def integer_component = self.class.decimal(Arith.bd(@real_value.truncate), BD_ZERO)

  def fractional_component = self.class.decimal(@real_value.frac, BD_ZERO)

  def fractional_part = subtract(floor)

  def floor
    if complex?
      self.class.error = 'Floor is only defined for real numbers'
      self.class.integer(0)
    else
      self.class.decimal(Arith.bd(@real_value.floor), BD_ZERO)
    end
  end

  def ceiling
    if complex?
      self.class.error = 'Ceiling is only defined for real numbers'
      self.class.integer(0)
    else
      self.class.decimal(Arith.bd(@real_value.ceil), BD_ZERO)
    end
  end

  def round
    if complex?
      self.class.error = 'Round is only defined for real numbers'
      self.class.integer(0)
    else
      self.class.decimal(Arith.bd(@real_value.round), BD_ZERO)
    end
  end

  def reciprocal = self.class.integer(1).divide(self)

  def epowy = self.class.from_pair(Arith.c_exp(pair))

  def xpowy(exponent, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif self.class.exponent_too_large?(budget, exponent)
      self.class.integer(0)
    elsif zero? && exponent.negative?
      self.class.error = 'The power of zero is undefined for a negative exponent'
      self.class.integer(0)
    elsif zero? && exponent.zero?
      self.class.error = 'Zero raised to zero is undefined'
      self.class.integer(0)
    elsif !complex? && !exponent.complex? && !exponent.integer? && exponent.reciprocal.integer?
      root(exponent.reciprocal.to_integer)
    else
      self.class.from_pair(Arith.c_pow(pair, exponent.pair))
    end
  end

  def xpowy_integer(exponent, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif budget && budget.max_power_exponent.positive? && exponent.abs > budget.max_power_exponent
      self.class.set_resource_error(ErrorCode::RESOURCE_LIMIT, 'Exponent is too large')
      self.class.integer(0)
    elsif zero? && exponent.negative?
      self.class.error = 'The power of zero is undefined for a negative exponent'
      self.class.integer(0)
    elsif zero? && exponent.zero?
      self.class.error = 'Zero raised to zero is undefined'
      self.class.integer(0)
    elsif @rational
      self.class.from_exact_rational(@rational**exponent)
    else
      self.class.from_pair(Arith.c_pow_integer(pair, exponent))
    end
  end

  def root(degree, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif budget && budget.max_power_exponent.positive? && degree.abs > budget.max_power_exponent
      self.class.set_resource_error(ErrorCode::RESOURCE_LIMIT, 'Root is too large')
      self.class.integer(0)
    elsif degree.zero?
      self.class.error = 'The zeroth root of a number is undefined'
      self.class.integer(0)
    elsif degree.negative?
      reciprocal.root(-degree)
    elsif !complex? && (!negative? || degree.odd?)
      real_root(degree)
    else
      self.class.from_pair(Arith.c_pow(pair, [Arith.div(BD_ONE, BigDecimal(degree)), BD_ZERO]))
    end
  end

  def sqrt(budget = nil) = root(2, budget)

  def ln
    if zero?
      self.class.error = 'Logarithm of zero is undefined'
      self.class.integer(0)
    else
      value = self.class.from_pair(Arith.c_log(pair))
      # MPC answers −π for the imaginary part of the log of a negative real
      # whose imaginary part is −0; +π is wanted.
      if !complex? && negative?
        self.class.decimal(value.real_value, value.imag_value.abs)
      else
        value
      end
    end
  end

  def logarithm(logarithm_base)
    if zero?
      self.class.error = 'Logarithm of zero is undefined'
      self.class.integer(0)
    elsif logarithm_base.zero? || logarithm_base.equals(self.class.integer(1))
      self.class.error = 'Logarithm with base 0 or 1 is undefined'
      self.class.integer(0)
    else
      ln.divide(logarithm_base.ln)
    end
  end

  def factorial(budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif zero?
      self.class.integer(1)
    elsif complex?
      self.class.error = 'Factorial of complex numbers is not supported'
      self.class.integer(0)
    elsif negative? && integer?
      self.class.error = 'Factorial is undefined for negative integers'
      self.class.integer(0)
    elsif !check_abs_limit(budget, self.class.budget_limit(budget, :max_factorial), 'Factorial is too large')
      self.class.integer(0)
    elsif natural?
      natural_factorial
    else
      # Factorial(x) = Γ(x + 1)
      self.class.decimal(Arith.gamma_r(@real_value + BD_ONE), BD_ZERO)
    end
  end

  def add(other)
    exact = exact_rational_sum(other, false)
    if exact
      exact
    else
      self.class.from_pair(Arith.c_add(pair, other.pair))
    end
  end

  def subtract(other)
    exact = exact_rational_sum(other, true)
    if exact
      exact
    else
      self.class.from_pair(Arith.c_sub(pair, other.pair))
    end
  end

  def multiply(other)
    exact = exact_rational_product(other)
    if exact
      exact
    else
      self.class.from_pair(Arith.c_mul(pair, other.pair))
    end
  end

  def multiply_integer(factor)
    if @rational
      self.class.from_exact_rational(@rational * factor)
    else
      self.class.from_pair(Arith.c_mul(pair, [BigDecimal(factor), BD_ZERO]))
    end
  end

  def divide(other)
    if other.zero?
      self.class.error = 'Division by zero is undefined'
      self.class.integer(0)
    else
      exact = exact_rational_quotient(other)
      if exact
        exact
      else
        self.class.from_pair(Arith.c_div(pair, other.pair))
      end
    end
  end

  def divide_integer(divisor) = divide(self.class.integer(divisor))

  def modulus_divide(other)
    if complex? || other.complex?
      self.class.error = 'Modulus division is only defined for real numbers'
      self.class.integer(0)
    else
      remainder = subtract(divide(other).floor.multiply(other))
      zero = self.class.integer(0)
      if (other.compare(zero) < 0 && remainder.compare(zero) > 0) ||
         (other.compare(zero) > 0 && remainder.compare(zero) < 0)
        remainder.add(other)
      else
        remainder
      end
    end
  end

  # x^exponent mod modulus, by squaring, so a large exponent stays affordable.
  def modular_exponentiation(exponent, modulus, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif self.class.modular_exponent_too_large?(budget, exponent)
      self.class.integer(0)
    else
      modular_exponentiation_loop(exponent, modulus, budget)
    end
  end

  def sin(unit = AngleUnit::RADIANS)
    if one_eighty_n_degrees?(unit)
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_sin(in_radians(unit).pair))
    end
  end

  def cos(unit = AngleUnit::RADIANS)
    if one_eighty_n_plus_ninety_degrees?(unit)
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_cos(in_radians(unit).pair))
    end
  end

  def tan(unit = AngleUnit::RADIANS)
    if one_eighty_n_degrees?(unit)
      self.class.integer(0)
    elsif one_eighty_n_plus_ninety_degrees?(unit)
      self.class.error = 'Tangent is undefined for angles that are multiples of π (180°) from π∕2 (90°)'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_tan(in_radians(unit).pair))
    end
  end

  def asin(unit = AngleUnit::RADIANS)
    if !complex? && (compare(self.class.integer(1)) > 0 || compare(self.class.integer(-1)) < 0)
      self.class.error = 'Inverse sine is undefined for values outside [-1, 1]'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_asin(pair)).from_radians_unless_complex(unit)
    end
  end

  def acos(unit = AngleUnit::RADIANS)
    if !complex? && (compare(self.class.integer(1)) > 0 || compare(self.class.integer(-1)) < 0)
      self.class.error = 'Inverse cosine is undefined for values outside [-1, 1]'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_acos(pair)).from_radians_unless_complex(unit)
    end
  end

  def atan(unit = AngleUnit::RADIANS)
    if equals(self.class.integer(0, 1)) || equals(self.class.integer(0, -1))
      self.class.error = 'Inverse tangent is undefined for values i and -i'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_atan(pair)).from_radians_unless_complex(unit)
    end
  end

  def sinh = self.class.from_pair(Arith.c_sinh(pair))

  def cosh = self.class.from_pair(Arith.c_cosh(pair))

  def tanh = self.class.from_pair(Arith.c_tanh(pair))

  def asinh = self.class.from_pair(Arith.c_asinh(pair))

  def acosh
    if !complex? && compare(self.class.integer(1)) < 0
      self.class.error = 'Inverse hyperbolic cosine is undefined for values less than one'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_acosh(pair))
    end
  end

  def atanh
    if !complex? && (compare(self.class.integer(1)) >= 0 || compare(self.class.integer(-1)) <= 0)
      self.class.error = 'Inverse hyperbolic tangent is undefined for values outside [-1, 1]'
      self.class.integer(0)
    else
      self.class.from_pair(Arith.c_atanh(pair))
    end
  end

  def and_with(other, budget = nil)
    bitwise_pair(
      other,
      0,
      budget,
      'Bitwise AND is only defined for non-negative integers',
    ) { |a, b| a & b }
  end

  def nand(other, wordlen, budget = nil)
    bitwise_pair(
      other,
      wordlen,
      budget,
      'Bitwise NAND is only defined for non-negative integers',
    ) { |a, b| a & b }
      .not(wordlen, budget)
  end

  def or_with(other, budget = nil)
    bitwise_pair(
      other,
      0,
      budget,
      'Bitwise OR is only defined for non-negative integers',
    ) { |a, b| a | b }
  end

  def nor(other, wordlen, budget = nil)
    bitwise_pair(
      other,
      wordlen,
      budget,
      'Bitwise NOR is only defined for non-negative integers',
    ) { |a, b| a | b }
      .not(wordlen, budget)
  end

  def xor(other, budget = nil)
    bitwise_pair(
      other,
      0,
      budget,
      'Bitwise XOR is only defined for non-negative integers',
    ) { |a, b| a ^ b }
  end

  def xnor(other, wordlen, budget = nil)
    bitwise_pair(
      other,
      wordlen,
      budget,
      'Bitwise XNOR is only defined for non-negative integers',
    ) { |a, b| a ^ b }
      .not(wordlen, budget)
  end

  def not(wordlen, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif !natural?
      self.class.error = 'Bitwise NOT is only defined for non-negative integers'
      self.class.integer(0)
    else
      bitwise(self.class.integer(0), wordlen, budget) { |a, _b| a ^ 0xF }
    end
  end

  def left_shift(count, wordlen)
    if !can_shift?(count, wordlen)
      self.class.integer(0)
    else
      bits = (two_complement_bits << shift_count(count, wordlen)) & MASK64
      self.class.from_word_bits(masked_shift_bits(bits, wordlen), negative?)
    end
  end

  def right_shift(count, wordlen)
    if !can_shift?(count, wordlen)
      self.class.integer(0)
    elsif negative?
      self.class.integer(to_integer >> shift_count(count, wordlen))
    else
      self.class.unsigned_integer(to_unsigned_integer >> shift_count(count, wordlen))
    end
  end

  def unsigned_right_shift(count, wordlen)
    if !can_shift?(count, wordlen)
      self.class.integer(0)
    else
      bits = two_complement_bits
      if wordlen != 64 && negative?
        bits &= MASK64 >> (64 - wordlen)
      end
      self.class.unsigned_integer(bits >> shift_count(count, wordlen))
    end
  end

  def twos_complement(wordlen)
    if !natural?
      self.class.error = 'Two’s complement is only defined for non-negative integers'
      self.class.integer(0)
    else
      self.not(wordlen).add(self.class.integer(1))
    end
  end

  def swap_endianness(wordlen)
    if !integer?
      self.class.error = 'Swap endianness is only possible on integers'
      self.class.integer(0)
    elsif overflow?(wordlen, true)
      self.class.error = 'Overflow. Try a bigger word size'
      self.class.integer(0)
    else
      self.class.from_word_bits(reversed_bytes(wordlen), negative?)
    end
  end

  def combination(chosen, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif !natural? || !chosen.natural?
      self.class.error = 'Combination is only defined for non-negative integers'
      self.class.integer(0)
    elsif compare(chosen) < 0
      self.class.error = 'Combination is undefined if n is less than r'
      self.class.integer(0)
    else
      combination_value(chosen, budget)
    end
  end

  def permutation(chosen, budget = nil)
    if !self.class.charge_budget(budget)
      self.class.integer(0)
    elsif !natural? || !chosen.natural?
      self.class.error = 'Permutation is only defined for non-negative integers'
      self.class.integer(0)
    elsif compare(chosen) < 0
      self.class.error = 'Permutation is undefined if n is less than r'
      self.class.integer(0)
    elsif chosen.zero?
      self.class.integer(1)
    elsif !permutation_within_limit?(chosen, budget)
      self.class.integer(0)
    else
      permutation_value(chosen, budget)
    end
  end

  def self.gcd(args, budget = nil)
    if !charge_budget(budget)
      integer(0)
    elsif args.any? { |x| !x.integer? }
      self.error = 'Greatest common divisor is only defined for integers'
      integer(0)
    elsif args.length == 1
      args[0].abs
    else
      args[1..].reduce(args[0]) { |a, b| gcd_x_y(a, b, budget) }.abs
    end
  end

  def self.lcm(args, budget = nil)
    if !charge_budget(budget)
      integer(0)
    elsif args.any? { |x| !x.integer? }
      self.error = 'Least common multiple is only defined for integers'
      integer(0)
    elsif args.length == 1
      args[0].abs
    else
      args[1..].reduce(args[0]) { |a, b| lcm_x_y(a, b, budget) }.abs
    end
  end

  def self.gcd_x_y(x, y, budget = nil)
    a = x
    b = y
    cancelled = false
    while !b.zero? && !cancelled
      if charge_budget(budget)
        remainder = a.modulus_divide(b)
        a = b
        b = remainder
      else
        a = integer(0)
        cancelled = true
      end
    end
    a
  end

  def self.lcm_x_y(x, y, budget = nil)
    if x.zero? || y.zero?
      integer(0)
    else
      divisor = gcd_x_y(x, y, budget)
      if error
        integer(0)
      else
        x.divide(divisor).multiply(y)
      end
    end
  end

  def self.sum(args) = args.reduce(integer(0)) { |total, x| total.add(x) }

  def self.sum_squares(args) = args.reduce(integer(0)) { |total, x| total.add(x.xpowy_integer(2)) }

  def self.median(args)
    if args.any?(&:complex?)
      self.error = 'Median is only defined for real numbers'
      integer(0)
    else
      sorted = args.sort { |a, b| a.compare(b) }
      if args.length.odd?
        sorted[args.length / 2]
      else
        sorted[args.length / 2].add(sorted[(args.length / 2) - 1]).divide_integer(2)
      end
    end
  end

  def self.min(args)
    if args.any?(&:complex?)
      self.error = 'Minimum value is only defined for real numbers'
      integer(0)
    else
      args.reduce { |best, x| extreme(best, x, -1) }
    end
  end

  def self.max(args)
    if args.any?(&:complex?)
      self.error = 'Maximum value is only defined for real numbers'
      integer(0)
    else
      args.reduce { |best, x| extreme(best, x, 1) }
    end
  end

  def self.extreme(best, candidate, direction)
    if (candidate.compare(best) <=> 0) == direction
      candidate
    else
      best
    end
  end

  def self.variance(args, is_sample)
    average = sum(args).divide_integer(args.length)
    total = args.reduce(integer(0)) { |z, x| z.add(x.subtract(average).abs.xpowy_integer(2)) }
    if is_sample
      total.divide_integer(args.length - 1)
    else
      total.divide_integer(args.length)
    end
  end

  # Every prime factor of the value, smallest first, carrying the sign on the
  # first factor the way upstream does.
  def factorize(budget = nil)
    if !self.class.charge_budget(budget)
      []
    else
      factorize_value(budget)
    end
  end

  def factorize_uint64(value, budget = nil)
    [].tap do |factors|
      remaining = value
      cancelled = false
      while remaining.even? && remaining.positive? && !cancelled
        if self.class.charge_budget(budget)
          remaining /= 2
          factors << self.class.unsigned_integer(2)
        else
          cancelled = true
        end
      end
      divisor = 3
      while divisor <= remaining / divisor && !cancelled
        if self.class.charge_budget(budget)
          while (remaining % divisor).zero? && !cancelled
            if self.class.charge_budget(budget)
              remaining /= divisor
              factors << self.class.unsigned_integer(divisor)
            else
              cancelled = true
            end
          end
          divisor += 2
        else
          cancelled = true
        end
      end
      if remaining > 1 && !cancelled
        factors << self.class.unsigned_integer(remaining)
      end
    end
  end

  def pair = [@real_value, @imag_value]

  def self.from_pair(values)
    decimal(values[0], values[1])
  end

  # The shift and byte-swap operators work on a 64-bit two's complement word
  # and hand the bits back here, where the sign of the operand decides whether
  # the word reads as signed or unsigned — the same split upstream makes
  # between Number.integer and Number.unsigned_integer.
  def self.from_word_bits(bits, was_negative)
    if was_negative
      integer(signed_from_bits(bits))
    else
      unsigned_integer(bits)
    end
  end

  def self.signed_from_bits(bits)
    if bits > INT64_MAX
      bits - (UINT64_MAX + 1)
    else
      bits
    end
  end

  # Upstream's mpc_from_radians: scales a radian result into `unit`.
  def from_radians(unit)
    case unit
    when AngleUnit::DEGREES then multiply(self.class.integer(180)).divide(self.class.pi)
    when AngleUnit::GRADIANS then multiply(self.class.integer(200)).divide(self.class.pi)
    else self
    end
  end

  def from_radians_unless_complex(unit)
    if complex?
      self
    else
      from_radians(unit)
    end
  end

  # Upstream's mpc_to_radians: scales an argument given in `unit` into radians.
  def in_radians(unit)
    if complex?
      self
    else
      case unit
      when AngleUnit::DEGREES then multiply(self.class.pi.divide(self.class.integer(180)))
      when AngleUnit::GRADIANS then multiply(self.class.pi.divide(self.class.integer(200)))
      else self
      end
    end
  end

  def self.charge_budget(budget, steps = 1)
    if budget.nil?
      true
    else
      breach = budget.charge(steps)
      if breach
        set_resource_error(breach.code, breach.message)
        false
      else
        true
      end
    end
  end

  def self.budget_limit(budget, limit)
    if budget
      budget.public_send(limit)
    else
      0
    end
  end

  def self.exponent_too_large?(budget, exponent)
    if budget && budget.max_power_exponent.positive? && !exponent.complex? && exponent.integer? &&
       exponent.abs.compare(unsigned_integer(budget.max_power_exponent)) > 0
      set_resource_error(ErrorCode::RESOURCE_LIMIT, 'Exponent is too large')
      true
    else
      false
    end
  end

  def self.modular_exponent_too_large?(budget, exponent)
    if budget && budget.max_modular_exponent.positive? && !exponent.complex? && exponent.integer? &&
       exponent.abs.compare(unsigned_integer(budget.max_modular_exponent)) > 0
      set_resource_error(ErrorCode::RESOURCE_LIMIT, 'Modular exponent is too large')
      true
    else
      false
    end
  end

  def check_abs_limit(budget, limit, message)
    if !self.class.charge_budget(budget)
      false
    elsif budget && limit.positive? && !complex? &&
          abs.compare(self.class.unsigned_integer(limit)) > 0
      self.class.set_resource_error(ErrorCode::RESOURCE_LIMIT, message)
      false
    else
      true
    end
  end

  class << self
    # A strong probable prime test to base b, upstream's is_sprp.
    def strong_probable_prime?(candidate, b)
      one = unsigned_integer(1)
      candidate_minus = candidate.subtract(one)
      two = unsigned_integer(2)
      odd_part = candidate_minus
      two_factors = 0
      stripping = true
      while stripping
        halved = odd_part.divide(two)
        if halved.integer?
          odd_part = halved
          two_factors += 1
        else
          stripping = false
        end
      end

      x = unsigned_integer(b).modular_exponentiation(odd_part, candidate)
      if x.equals(one) || x.equals(candidate_minus)
        true
      else
        witness_found = false
        (1...two_factors).each do
          unless witness_found
            x = x.multiply(x).modulus_divide(candidate)
            if x.equals(candidate_minus)
              witness_found = true
            end
          end
        end
        witness_found
      end
    end

    SPRP_BASES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41].freeze

    # Upstream's is_prime: the 13 fixed bases below the Sorenson/Webster bound,
    # every base up to 2 ln(x)² above it.
    def probably_prime?(x)
      bound = x.ln.to_integer + 1
      if bound < 56
        SPRP_BASES.all? { |b| strong_probable_prime?(x, b) }
      else
        (0...(bound * bound * 2)).all? { |b| strong_probable_prime?(x, b) }
      end
    end

    private

      def parse_in_base(str, default_base, may_have_prefix)
        suffix_base, body_end = trailing_base(str)
        if suffix_base.nil?
          nil
        else
          prefix_base, body_start = literal_prefix(str, may_have_prefix)
          resolve_base(suffix_base, prefix_base, default_base).then do |number_base|
            if number_base.nil?
              nil
            else
              parse_digits(str[body_start...body_end], number_base)
            end
          end
        end
      end

      # The subscript digits a literal may end with, e.g. 1010₂. Answers the
      # base and where the digits stop, or nil when the suffix is not a legal
      # base.
      def trailing_base(str)
        digits = []
        index = str.length
        while index.positive? && SUB_DIGITS.include?(str[index - 1])
          digits.unshift(SUB_DIGITS.index(str[index - 1]))
          index -= 1
        end
        number_base = digits.reduce(0) { |value, digit| (value * 10) + digit }
        if digits.empty?
          [0, str.length]
        elsif number_base < 2 || number_base > 16
          [nil, nil]
        else
          [number_base, index]
        end
      end

      def literal_prefix(str, may_have_prefix)
        if may_have_prefix && str.length >= 3 && str[0] == '0' && LITERAL_PREFIXES.key?(str[1].downcase)
          [LITERAL_PREFIXES[str[1].downcase], 2]
        else
          [0, 0]
        end
      end

      def resolve_base(suffix_base, prefix_base, default_base)
        if suffix_base.positive? && prefix_base.positive? && suffix_base != prefix_base
          nil
        elsif suffix_base.positive?
          suffix_base
        elsif prefix_base.positive?
          prefix_base
        else
          default_base
        end
      end

      def parse_digits(body, number_base)
        sign, rest = split_sign(body)
        integer_text, remainder = split_run(rest, number_base)
        if integer_text.empty? && remainder.empty?
          nil
        else
          assemble(
            sign,
            integer_text,
            remainder,
            number_base,
          )
        end
      end

      def split_sign(body)
        if body.start_with?('+')
          [1, body[1..]]
        elsif body.start_with?('-', '−')
          [-1, body[1..]]
        else
          [1, body]
        end
      end

      def split_run(text, number_base)
        index = 0
        while index < text.length && digit_value(text[index], number_base)
          index += 1
        end
        [text[0...index], text[index..]]
      end

      def digit_value(char, number_base)
        value = HEX_DIGITS.index(char.upcase)
        if value && value < number_base
          value
        end
      end

      def assemble(sign, integer_text, remainder, number_base)
        whole = digits_to_number(integer_text, number_base)
        if VULGAR_FRACTIONS.key?(remainder)
          numerator, denominator = VULGAR_FRACTIONS[remainder]
          signed(sign, whole.add(fraction(numerator, denominator)))
        elsif remainder.empty?
          signed(sign, whole)
        elsif remainder.start_with?('.')
          assemble_fraction(
            sign,
            whole,
            remainder[1..],
            number_base,
          )
        end
      end

      def assemble_fraction(sign, whole, text, number_base)
        fraction_text, leftover = split_run(text, number_base)
        if !leftover.empty? || fraction_text.empty?
          nil
        else
          denominator = integer(number_base).xpowy_integer(fraction_text.length)
          value = whole.add(digits_to_number(fraction_text, number_base).divide(denominator))
          signed(sign, value).tap { |z| z.force_float = true }
        end
      end

      def digits_to_number(text, number_base)
        text.each_char.reduce(integer(0)) do |value, char|
          value.multiply_integer(number_base).add(integer(digit_value(char, number_base)))
        end
      end

      def signed(sign, value)
        if sign.negative?
          value.invert_sign
        else
          value
        end
      end

      # Upstream's set_from_sexagesimal: 1°2′3″, with the prime and
      # double-prime variants the keyboard and the display both produce.
      def from_sexagesimal(text)
        normalised = text.gsub(/[′’]/, "'").gsub(/(''|″|”)/, '"')
        degree_index = normalised.index('°')
        degrees = from_string(normalised[0...degree_index])
        if degrees.nil?
          nil
        else
          add_minutes(degrees, normalised[(degree_index + 1)..])
        end
      end

      def add_minutes(degrees, rest)
        if rest.nil? || rest.empty?
          degrees
        else
          minute_index = rest.index("'") || rest.length
          minutes = from_string(rest[0...minute_index])
          if minutes.nil?
            nil
          else
            add_seconds(degrees.add(minutes.divide_integer(60)), rest[(minute_index + 1)..])
          end
        end
      end

      def add_seconds(degrees, rest)
        if rest.nil? || rest.empty?
          degrees
        else
          second_index = rest.index('"') || rest.length
          seconds = from_string(rest[0...second_index])
          if seconds.nil? || !rest[(second_index + 1)..].to_s.empty?
            nil
          else
            degrees.add(seconds.divide_integer(3600))
          end
        end
      end
  end
  private

    def set_exact_rational(numerator, denominator)
      if denominator.zero?
        @rational = nil
      else
        @rational = Rational(numerator, denominator)
      end
    end

    def adopt_exact_rational(value)
      @rational = value
    end

    def exact_rational = @rational

    def adopt_non_finite(value)
      @finite = false
      @non_finite_value = value
    end

    def copy_exact_rational(other)
      @rational = other.send(:exact_rational)
    end

    def exact_rational_sum(other, subtracting)
      mine = @rational
      theirs = other.send(:exact_rational)
      if mine && theirs
        if subtracting
          self.class.from_exact_rational(mine - theirs)
        else
          self.class.from_exact_rational(mine + theirs)
        end
      end
    end

    def exact_rational_product(other)
      mine = @rational
      theirs = other.send(:exact_rational)
      if mine && theirs
        self.class.from_exact_rational(mine * theirs)
      end
    end

    def exact_rational_quotient(other)
      mine = @rational
      theirs = other.send(:exact_rational)
      if mine && theirs && !theirs.zero?
        self.class.from_exact_rational(mine / theirs)
      end
    end

    def real_root(degree)
      if negative?
        self.class.decimal(-Arith.pow_r(-@real_value, Arith.div(BD_ONE, BigDecimal(degree))), BD_ZERO)
      elsif degree == 2
        self.class.decimal(Arith.sqrt_r(@real_value), BD_ZERO)
      else
        self.class.decimal(Arith.pow_r(@real_value, Arith.div(BD_ONE, BigDecimal(degree))), BD_ZERO)
      end
    end

    def natural_factorial
      (1..to_integer).reduce(self.class.integer(1)) { |product, i| product.multiply_integer(i) }
    end

    def modular_exponentiation_loop(exponent, modulus, budget)
      base_value = self
      if exponent.negative?
        base_value = base_value.reciprocal
      end
      remaining = exponent.abs
      answer = self.class.integer(1)
      two = self.class.integer(2)
      cancelled = false
      while !remaining.zero? && !cancelled
        if self.class.charge_budget(budget)
          unless remaining.modulus_divide(two).zero?
            answer = answer.multiply(base_value).modulus_divide(modulus)
          end
          base_value = base_value.multiply(base_value).modulus_divide(modulus)
          remaining = remaining.divide_integer(2).floor
        else
          answer = self.class.integer(0)
          cancelled = true
        end
      end
      answer.modulus_divide(modulus)
    end

    def combination_value(chosen, budget)
      taken = chosen
      if chosen.compare(divide_integer(2)) > 0
        taken = subtract(chosen)
      end
      permutations = permutation(taken, budget)
      if self.class.error
        self.class.integer(0)
      else
        arrangements = taken.factorial(budget)
        if self.class.error
          self.class.integer(0)
        else
          permutations.divide(arrangements)
        end
      end
    end

    def permutation_within_limit?(chosen, budget)
      limit = self.class.budget_limit(budget, :max_permutation)
      check_abs_limit(budget, limit, 'Permutation is too large') &&
        chosen.check_abs_limit(budget, limit, 'Permutation is too large')
    end

    def permutation_value(chosen, budget)
      value = to_integer
      product = self
      cancelled = false
      ((value - chosen.to_integer + 1)...value).each do |i|
        unless cancelled
          if self.class.charge_budget(budget)
            product = product.multiply_integer(i)
          else
            product = self.class.integer(0)
            cancelled = true
          end
        end
      end
      product
    end

    def bitwise_pair(other, wordlen, budget, message, &operator)
      if !self.class.charge_budget(budget)
        self.class.integer(0)
      elsif !natural? || !other.natural?
        self.class.error = message
        self.class.integer(0)
      else
        bitwise(
          other,
          wordlen,
          budget,
          &operator
        )
      end
    end

    # Upstream's bitwise(): both operands are rendered as hexadecimal strings
    # and the operator is applied nibble by nibble from the right, so word
    # lengths past 64 bits still work.
    def bitwise(other, wordlen, budget = nil)
      if !self.class.charge_budget(budget)
        self.class.integer(0)
      elsif wordlen.positive? && (overflow?(wordlen) || other.overflow?(wordlen))
        self.class.error = 'Overflow. Try a bigger word size'
        self.class.integer(0)
      else
        left = to_hex_string(budget)
        right = other.send(:to_hex_string, budget)
        if left.nil? || right.nil?
          self.class.integer(0)
        else
          self.class.from_string(combine_nibbles(left, right, wordlen) { |a, b| yield(a, b) }, 16, false)
        end
      end
    end

    def combine_nibbles(left, right, wordlen)
      width = (wordlen / 4) - 1
      if width <= 0
        width = [left.length, right.length].max - 1
      end
      (0..width).map do |offset|
        a = nibble_at(left, left.length - 1 - offset)
        b = nibble_at(right, right.length - 1 - offset)
        HEX_DIGITS[yield(a, b)]
      end.reverse.join
    end

    def nibble_at(text, index)
      if index.negative?
        0
      else
        HEX_DIGITS.index(text[index].upcase) || 0
      end
    end

    def to_hex_string(budget = nil)
      serializer = Serializer.new(DisplayFormat::FIXED, 16, 0)
      serializer.check_fixed_max = false
      text = serializer.to_string(self, budget)
      if serializer.error
        self.class.set_resource_error(ErrorCode::RESOURCE_LIMIT, serializer.error)
        nil
      else
        text
      end
    end

    def can_shift?(count, wordlen)
      if !integer? || !count.integer?
        self.class.error = 'Shift is only possible on integers'
        false
      elsif overflow?(wordlen, true)
        self.class.error = 'Overflow. Try a bigger word size'
        false
      else
        true
      end
    end

    def shift_count(count, wordlen) = count.modulus_divide(self.class.integer(wordlen)).to_integer

    def two_complement_bits = to_integer & MASK64

    def masked_shift_bits(bits, wordlen)
      if wordlen == 64
        bits
      elsif negative? && (bits & (1 << (wordlen - 1))) != 0
        (bits | (MASK64 << wordlen)) & MASK64
      else
        bits & (MASK64 >> (64 - wordlen))
      end
    end

    def reversed_bytes(wordlen)
      bits = two_complement_bits
      swapped = 0
      (wordlen / 8).times do
        swapped = (swapped << 8) | (bits & 0xFF)
        bits >>= 8
      end
      if !negative?
        swapped
      elsif wordlen != 64 && (swapped & (1 << (wordlen - 1))) != 0
        (swapped | (MASK64 << wordlen)) & MASK64
      else
        swapped
      end
    end

    def factorize_value(budget)
      value = abs
      if value.zero?
        [value]
      elsif value.equals(self.class.integer(1))
        [self]
      elsif value.compare(self.class.unsigned_integer(UINT64_MAX)) <= 0
        signed_factors(factorize_uint64(value.to_integer, budget))
      elsif self.class.probably_prime?(value)
        [value]
      else
        signed_factors(trial_division_factors(value, budget))
      end
    end

    def trial_division_factors(value, budget)
      [].tap do |factors|
        remaining = value
        two = self.class.integer(2)
        dividing = true
        while dividing
          quotient = remaining.divide(two)
          if quotient.integer? && self.class.charge_budget(budget)
            remaining = quotient
            factors << two
          else
            dividing = false
          end
        end
        divisor = self.class.integer(3)
        limit = remaining.sqrt(budget)
        while divisor.compare(limit) <= 0 && self.class.charge_budget(budget)
          quotient = remaining.divide(divisor)
          if quotient.integer?
            remaining = quotient
            limit = remaining.sqrt(budget)
            factors << divisor
          else
            divisor = divisor.add(two)
          end
        end
        if remaining.compare(self.class.integer(1)) > 0
          factors << remaining
        end
      end
    end

    def signed_factors(factors)
      if negative? && !factors.empty?
        [factors.first.invert_sign] + factors[1..]
      else
        factors
      end
    end

end
