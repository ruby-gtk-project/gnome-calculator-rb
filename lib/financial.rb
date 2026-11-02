# frozen_string_literal: true

require_relative 'number'

# Which financial calculation a dialog in the financial button panel runs.
#
# Ported from the FinancialDialog enum in upstream's lib/financial.vala.
module FinancialDialog
  CTRM = :ctrm
  DDB = :ddb
  FV = :fv
  GPM = :gpm
  PMT = :pmt
  PV = :pv
  RATE = :rate
  SLN = :sln
  SYD = :syd
  TERM = :term

  ALL = [CTRM, DDB, FV, GPM, PMT, PV, RATE, SLN, SYD, TERM].freeze
end

# Financial holds the ten calculations behind the financial button panel.
#
# Ported from upstream's lib/financial.vala. Upstream's do_finc_expression is
# `Financial.do_finc_expression`: it runs the calculation and sets the result
# on the equation, which is the only thing the dialogs need from it. Each
# calc_* method answers a Number, so they can also be used on their own.
module Financial
  module_function

  # Runs `function` and sets the answer on `equation`. `equation` is a
  # MathEquation: do_finc_expression only ever calls set_number on it, plus
  # status= for the one calculation that can complain about its arguments.
  def do_finc_expression(equation, function, arg1, arg2, arg3, arg4)
    equation.set_number(
      solve(
        equation,
        function,
        arg1,
        arg2,
        arg3,
        arg4,
      ),
      false,
    )
  end

  # The calculation `function` names, answered as a Number.
  def solve(equation, function, arg1, arg2, arg3, arg4)
    case function
    when FinancialDialog::CTRM then calc_ctrm(arg1, arg2, arg3)
    when FinancialDialog::DDB then calc_ddb(
      equation,
      arg1,
      arg2,
      arg3,
    )
    when FinancialDialog::FV then calc_fv(arg1, arg2, arg3)
    when FinancialDialog::GPM then calc_gpm(arg1, arg2)
    when FinancialDialog::PMT then calc_pmt(arg1, arg2, arg3)
    when FinancialDialog::PV then calc_pv(arg1, arg2, arg3)
    when FinancialDialog::RATE then calc_rate(arg1, arg2, arg3)
    when FinancialDialog::SLN then calc_sln(arg1, arg2, arg3)
    when FinancialDialog::SYD
      calc_syd(
        arg1,
        arg2,
        arg3,
        arg4,
      )
    when FinancialDialog::TERM then calc_term(arg1, arg2, arg3)
    else Number.integer(0)
    end
  end

  # Compounding term: log(fv ÷ pv) ÷ log(1 + pint)
  def calc_ctrm(pint, fv, pv)
    fv.divide(pv).ln.divide(pint.add(Number.integer(1)).ln)
  end

  # Double-declining depreciation: the allowance for `period`, found by walking
  # the book value forward one period at a time.
  def calc_ddb(equation, cost, life, period)
    allowance = Number.integer(0)
    book_value = Number.integer(0)
    periods = period.to_integer
    periods.times do
      allowance = cost.subtract(book_value).multiply_integer(2).divide(life)
      book_value = book_value.add(allowance)
    end

    if periods >= 0
      equation.status = 'Error: the number of periods must be positive'
    end

    allowance
  end

  # Future value: pmt × ((1 + pint)^n − 1) ÷ pint
  def calc_fv(pmt, pint, n)
    pmt.multiply(pint.add(Number.integer(1)).xpowy(n).add(Number.integer(-1))).divide(pint)
  end

  # Gross profit margin: cost ÷ (1 − margin)
  def calc_gpm(cost, margin)
    cost.divide(Number.integer(1).subtract(margin))
  end

  # Periodic payment: prin × (pint ÷ (1 − (pint + 1)^−n))
  def calc_pmt(prin, pint, n)
    factor = pint.add(Number.integer(1)).xpowy(n.multiply_integer(-1)).multiply_integer(-1)
    prin.multiply(pint.divide(factor.add(Number.integer(1))))
  end

  # Present value: pmt × (1 − (1 + pint)^−n) ÷ pint
  def calc_pv(pmt, pint, n)
    factor = pint.add(Number.integer(1)).xpowy(n.multiply_integer(-1)).multiply_integer(-1)
    pmt.multiply(factor.add(Number.integer(1)).divide(pint))
  end

  # Periodic interest rate: (fv ÷ pv)^(1 ÷ n) − 1
  def calc_rate(fv, pv, n)
    fv.divide(pv).xpowy(Number.integer(1).divide(n)).add(Number.integer(-1))
  end

  # Straight-line depreciation: (cost − salvage) ÷ life
  def calc_sln(cost, salvage, life)
    cost.subtract(salvage).divide(life)
  end

  # Sum-of-the-years'-digits depreciation:
  # (cost − salvage) × (life − period + 1) ÷ (life × (life + 1) ÷ 2)
  def calc_syd(cost, salvage, life, period)
    remaining = life.subtract(period).add(Number.integer(1))
    total = life.multiply(life.add(Number.integer(1))).divide(Number.integer(2))
    cost.subtract(salvage).multiply(remaining.divide(total))
  end

  # Payment period: log(1 + (fv × pint ÷ pmt)) ÷ log(1 + pint)
  def calc_term(pmt, fv, pint)
    numerator = fv.multiply(pint).divide(pmt).add(Number.integer(1)).ln
    numerator.divide(pint.add(Number.integer(1)).ln)
  end
end
