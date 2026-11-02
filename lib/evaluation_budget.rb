# frozen_string_literal: true

# EvaluationBudget caps the work a single evaluation is allowed to do.
#
# Ported from upstream's lib/evaluation-budget.vala. Upstream's methods take
# `out ErrorCode error_code, out string? message` and return a bool; Ruby has
# no out parameters, so each check returns nil when the budget still allows the
# work and a Breach (the same code and message) when it does not. Callers read
# like `if (breach = budget.check)`.
#
# ErrorCode is defined in equation.rb, the port of upstream's lib/equation.vala.
class EvaluationBudget
  # A refused charge: the ErrorCode upstream writes to its out parameter and
  # the message that goes with it.
  Breach = Struct.new(:code, :message)

  LIMITS = %i[
    deadline_usec
    max_input_chars
    max_tokens
    max_output_digits
    max_steps
    max_factorial
    max_power_exponent
    max_modular_exponent
    max_permutation
  ].freeze

  attr_accessor(*LIMITS)

  # Upstream's EvaluationBudget.for_search limits, applied on top of a timeout.
  SEARCH_LIMITS = {
    max_input_chars:      256,
    max_tokens:           256,
    max_output_digits:    256,
    max_steps:            100_000,
    max_factorial:        10_000,
    max_power_exponent:   100_000,
    max_modular_exponent: 1_000_000,
    max_permutation:      10_000,
  }.freeze

  def self.for_search(timeout_msec)
    new(timeout_msec).tap do |budget|
      SEARCH_LIMITS.each { |limit, value| budget.public_send(:"#{limit}=", value) }
    end
  end

  def initialize(timeout_msec = 0)
    LIMITS.each { |limit| instance_variable_set(:"@#{limit}", 0) }
    @steps = 0
    @cancelled = false
    if timeout_msec > 0
      @deadline_usec = self.class.monotonic_usec + (timeout_msec * 1000)
    end
  end

  def self.monotonic_usec = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)

  def cancel
    @cancelled = true
  end

  def cancelled? = @cancelled

  # nil while the evaluation may continue, a Breach once it is cancelled or
  # past its deadline.
  def check
    if @cancelled || (deadline_usec > 0 && self.class.monotonic_usec >= deadline_usec)
      Breach.new(ErrorCode::TIMED_OUT, 'Evaluation timed out')
    end
  end

  # Charges `count` steps against the budget.
  def charge(count = 1)
    breach = check
    if breach
      breach
    else
      @steps += count
      if max_steps > 0 && @steps > max_steps
        Breach.new(ErrorCode::RESOURCE_LIMIT, 'Evaluation requires too many steps')
      end
    end
  end

  def check_input(input)
    check_limit(input.length, max_input_chars, 'Expression is too long')
  end

  def check_tokens(tokens)
    check_limit(tokens, max_tokens, 'Expression is too complex')
  end

  def check_output_digits(digits)
    check_limit(digits, max_output_digits, 'Result is too large')
  end

  # Upstream's check_limit: the deadline first, then `value` against `limit`,
  # where a limit of zero means unlimited.
  def check_limit(value, limit, limit_message)
    breach = check
    if breach
      breach
    elsif limit > 0 && value > limit
      Breach.new(ErrorCode::RESOURCE_LIMIT, limit_message)
    end
  end
end
