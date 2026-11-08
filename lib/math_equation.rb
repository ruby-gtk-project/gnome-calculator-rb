# frozen_string_literal: true

require 'gtk4'

require_relative 'equation'
require_relative 'math_variables'
require_relative 'function_manager'
require_relative 'unit'
require_relative 'serializer'
require_relative 'translations'

# The number mode a digit is inserted under — upstream's NumberMode enum at
# the top of lib/math-equation.vala.
module NumberMode
  NORMAL = :normal
  SUPERSCRIPT = :superscript
  SUBSCRIPT = :subscript
end

# MathEquation holds the one expression the calculator is editing: the text
# buffer the display shows, the base/angle/word-size settings it is read
# under, and the solve/insert/clear operations every button panel and
# keyboard accelerator drives it through.
#
# Ported from upstream's lib/math-equation.vala. Upstream subclasses
# GtkSource.Buffer for syntax highlighting and style-scheme theming; neither
# gtksourceview4 nor gtksourceview5 load in this fork's toolchain (see
# FINDINGS.md), so this port wraps a plain Gtk::TextBuffer instead. The
# answer-highlighting tag (`ans_tag`), the undo-by-snapshot history and the
# whole insert/solve/clear state machine are carried over; the style-scheme
# plumbing is not, because there is no GtkSource.Buffer underneath to carry
# it on.
#
# Upstream solves on a worker Thread polled by a GLib.Timeout so the display
# never blocks; this port solves synchronously inside `solve`; the budgeted
# EvaluationBudget check inside Equation still bounds how long a single
# parse can run (see evaluation_budget.rb).
class MathEquation
  include Gettext

  ANS_STRING = '_ '

  Snapshot = Struct.new(
    :text,
    :cursor,
    :ans,
    :ans_base,
    :is_real_ans,
    :status,
    :number_mode,
    keyword_init: true,
  )

  attr_reader :buffer, :variables, :serializer
  attr_accessor :accuracy, :word_size, :angle_units, :base_label

  def initialize
    @buffer = Gtk::TextBuffer.new
    @variables = MathVariables.new
    @serializer = Serializer.new(DisplayFormat::AUTOMATIC, 10, 9)
    @ans_tag = @buffer.create_tag(nil, weight: 700)
    @ans_start_mark = nil
    @ans_end_mark = nil
    @ans = Number.integer(0)
    @ans_base = 10
    @is_real_ans = false
    @status = ''
    @error_token_start = 0
    @error_token_end = 0
    @number_mode = NumberMode::NORMAL
    @can_super_minus = false
    @undo_stack = []
    @redo_stack = []
    @accuracy = 9
    @word_size = 32
    @angle_units = AngleUnit::DEGREES
    @base_label = ''
    @history_handlers = []
    @display_changed_handlers = []
    @number_mode_changed_handlers = []
  end

  def on_history(&block) = @history_handlers << block

  def on_display_changed(&block) = @display_changed_handlers << block

  def on_number_mode_changed(&block) = @number_mode_changed_handlers << block

  # --- settings the preferences dialog and base/word-size menus drive -----

  def number_base = @serializer.number_base

  def number_base=(value)
    @serializer.number_base = value
    @serializer.representation_base = value
  end

  def number_format = @serializer.number_format

  def number_format=(value)
    @serializer.number_format = value
  end

  def show_thousands_separators = @serializer.show_thousands_separators

  def show_thousands_separators=(value)
    @serializer.show_thousands_separators = value
  end

  def show_trailing_zeroes = @serializer.show_trailing_zeroes

  def show_trailing_zeroes=(value)
    @serializer.show_trailing_zeroes = value
  end

  def status = @status

  def status=(value)
    @status = value
  end

  attr_reader :error_token_start, :error_token_end

  # --- buffer-derived state -------------------------------------------------

  def display
    start_iter, end_iter = @buffer.bounds
    @buffer.get_text(start_iter, end_iter, false)
  end

  def is_empty = @buffer.char_count.zero?

  def is_result = equation == ANS_STRING && display != ANS_STRING

  def is_sign_radix
    radix = @serializer.radix
    [
      '+', '-', '−', radix, "+#{radix}", "-#{radix}", "−#{radix}",
    ].include?(display)
  end

  # Upstream substitutes the ans-mark span back to "_ " and folds the
  # thousands separator and radix character out of the literal text, so the
  # parser always sees "1234.5", never "1,234,5".
  def equation
    text = display
    if @ans_start_mark
      ans_start, ans_end = ans_offsets
      chars = text.chars
      if ans_start >= 0
        text = chars[0...ans_start].join + ANS_STRING + chars[ans_end..].to_a.join
      end
    end

    tsep = @serializer.thousands_separator
    radix = @serializer.radix
    chars = text.chars
    result = +''
    chars.each_with_index do |char, index|
      last_is_digit = index.positive? && chars[index - 1] =~ /\d/
      next_is_digit = chars[index + 1] =~ /\d/
      if char == tsep && last_is_digit && next_is_digit
        next
      end

      result << (char == radix && (last_is_digit || next_is_digit) ? '.' : char)
    end
    result
  end

  def number
    if is_result
      answer
    else
      @serializer.from_string(equation)
    end
  end

  def answer = @ans

  def number_mode = @number_mode

  def number_mode=(value)
    if @number_mode == value
      nil
    else
      @can_super_minus = value == NumberMode::SUPERSCRIPT
      @number_mode = value
      @number_mode_changed_handlers.each { |handler| handler.call(value) }
    end
  end

  # --- editing ---------------------------------------------------------------

  def store(name)
    x = number
    if x.nil?
      self.status = _('No sane value to store')
    else
      @variables[name] = x
    end
  end

  def set(text)
    push_undo_stack
    @buffer.text = text
    clear_ans
  end

  def set_number(x, history: true, representation_base: 0)
    unless representation_base.zero?
      @serializer.representation_base = representation_base
    end

    text = @serializer.to_string(x)
    if history
      @history_handlers.each { |handler| handler.call(
        equation.gsub('\\cdot', '×'),
        x,
        number_base,
        representation_base,
      ) }
    end

    push_undo_stack
    @buffer.text = text
    @ans = x
    @is_real_ans = history

    start_iter, end_iter = @buffer.bounds
    clear_ans
    @ans_start_mark = @buffer.create_mark(nil, start_iter, false)
    @ans_end_mark = @buffer.create_mark(nil, end_iter, true)
    @buffer.apply_tag(@ans_tag, start_iter, end_iter)

    @serializer.representation_base = number_base
    if @serializer.error
      self.status = @serializer.error
      @serializer.error = nil
    end
    notify_display_changed
  end

  def set_number_as_input(x)
    format, trailing = number_format, show_trailing_zeroes
    @serializer.number_format = DisplayFormat::FIXED
    @serializer.show_trailing_zeroes = false
    push_undo_stack
    @buffer.text = @serializer.to_string(x)
    @serializer.number_format = format
    @serializer.show_trailing_zeroes = trailing
  end

  # Upstream's `insert`: a handful of digraph substitutions (`××` -> `^`,
  # `>>`/`>>>` -> `≫`/`⋙`, `<<` -> `≪`), then a plain insert at the cursor.
  def insert(text)
    digraph = !@buffer.has_selection? && digraph_replacement(text)

    if digraph
      backspace_one_char
      insert_at_cursor(digraph)
    else
      if '⁰¹²³⁴⁵⁶⁷⁸⁹'.include?(text) || text == '⁻'
        @can_super_minus = false
      end
      unless '⁻⁰¹²³⁴⁵⁶⁷⁸⁹₀₁₂₃₄₅₆₇₈₉'.include?(text)
        self.number_mode = NumberMode::NORMAL
      end

      push_undo_stack
      if @buffer.has_selection?
        @buffer.delete_selection(false, false)
      end
      insert_at_cursor(text)
    end
  end

  def insert_digit(digit)
    if digit >= 16
      nil
    else
      if number_mode == NumberMode::NORMAL || digit >= 10
        text = Serializer::DIGITS[digit]
      elsif number_mode == NumberMode::SUPERSCRIPT
        text = Serializer::SUPER_DIGITS[digit]
      else
        text = Serializer::SUB_DIGITS[digit]
      end
      insert(text)
    end
  end

  def insert_numeric_point = insert(@serializer.radix)

  def insert_number(x) = insert(@serializer.to_string(x))

  # Inserts `text` as an alphabetic token — a variable or constant name —
  # padding it with a space on either side it touches another alphabetic
  # character or underscore, so two names never run together.
  #
  # Ported from upstream's MathEquation.insert_alpha in lib/math-equation.vala.
  def insert_alpha(text)
    before, after = char_before, char_after
    start_space = ''
    if alpha_boundary?(before)
      start_space = ' '
    end
    end_space = ''
    if alpha_boundary?(after)
      end_space = ' '
    end
    insert("#{start_space}#{text}#{end_space}")
  end

  # Inserts a function call. With a selection, or when `force_brackets` is
  # set, the selection (or the cursor) ends up inside `name(...)`; otherwise
  # just `name ` is inserted, ready for the user to type an argument.
  #
  # Ported from upstream's MathEquation.insert_function in
  # lib/math-equation.vala.
  def insert_function(name, force_brackets: false)
    space = ''
    if alpha_boundary?(char_before)
      space = ' '
    end
    if @buffer.has_selection? || force_brackets
      insert_between("#{space}#{name}(", ')')
    else
      insert("#{space}#{name} ")
    end
  end

  def delete_next
    cursor = cursor_offset
    if cursor >= @buffer.char_count
      nil
    else
      push_undo_stack
      @buffer.delete(@buffer.get_iter_at(offset: cursor), @buffer.get_iter_at(offset: cursor + 1))
    end
  end

  def backspace
    if is_empty
      nil
    else
      push_undo_stack
      if @buffer.has_selection?
        @buffer.delete_selection(false, false)
      else
        backspace_one_char
      end
    end
  end

  def clear
    self.number_mode = NumberMode::NORMAL
    push_undo_stack
    @buffer.text = ''
    clear_ans
    self.status = ''
  end

  def undo
    if @undo_stack.empty?
      nil
    else
      @redo_stack.push(current_snapshot)
      restore_snapshot(@undo_stack.pop)
    end
  end

  def redo
    if @redo_stack.empty?
      nil
    else
      @undo_stack.push(current_snapshot)
      restore_snapshot(@redo_stack.pop)
    end
  end

  def has_undo_action = !@undo_stack.empty?

  def has_redo_action = !@redo_stack.empty?

  # Synchronous solve: parses `equation` through an Equation that hands
  # variable/function/unit lookups back to this calculator's managers, then
  # either replaces the display with the result or reports the error.
  #
  # If a result is already showing, "=" repeats the last operation against
  # it instead of re-solving, same as upstream.
  def solve
    if is_empty
      nil
    else
      if is_result
        if @is_real_ans
          undo
        end
        repeat_last_operation
      else
        self.number_mode = NumberMode::NORMAL
        eq = backing_equation(equation)
        eq.base = number_base
        eq.wordlen = word_size
        eq.angle_units = angle_units
        result = eq.parse
        if result.error_code != ErrorCode::NONE || result.value.nil?
          report_error(result)
        else
          @last_token, @last_operand = eq.last_operation
          set_number(result.value, representation_base: result.representation_base)
        end
      end
    end
  end

  def has_selection = @buffer.has_selection?

  # Removes the run of whitespace immediately before the cursor.
  #
  # Ported from upstream's MathEquation.remove_trailing_spaces in
  # lib/math-equation.vala.
  def remove_trailing_spaces
    end_iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
    start_iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
    while start_iter.backward_char
      if !start_iter.char.to_s.match?(/\s/)
        start_iter.forward_char
        break
      end
    end
    @buffer.delete(start_iter, end_iter)
  end

  # Inserts a single `opening`/`closing` bracket pair around the selection,
  # or balances a lone bracket at the cursor otherwise: if the character
  # before the cursor isn't the opening bracket, counts opening vs. closing
  # brackets back to the start of the buffer and inserts whichever one
  # keeps the count balanced.
  #
  # Ported from upstream's MathEquation.insert_brackets in
  # lib/math-equation.vala.
  def insert_brackets(opening, closing)
    if has_selection
      insert_between(opening, closing)
    else
      iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      is_closing = false
      if iter.backward_char
        unless iter.char == opening
          opening_count = 0
          closing_count = 0
          continue = true
          while continue
            if iter.char == opening
              opening_count += 1
            end
            if iter.char == closing
              closing_count += 1
            end
            continue = iter.backward_char
          end
          is_closing = opening_count > closing_count
        end
      end
      insert(is_closing ? closing : opening)
    end
  end

  # Inserts `symbol` around the selection — before it, or after it when
  # `after` is set — or plainly at the cursor with no selection.
  #
  # Ported from upstream's MathEquation.insert_symbol in
  # lib/math-equation.vala.
  def insert_symbol(symbol, after)
    if !has_selection
      insert(symbol)
    elsif after
      insert_between('(', ")#{symbol}", after: true)
    else
      insert_between("#{symbol}(", ')')
    end
  end

  # Wraps the selection in `(...)²`, or inserts a bare `²` at the cursor,
  # with a leading space when another superscript digit sits right before
  # it so the two don't visually run together.
  #
  # Ported from upstream's MathEquation.insert_square in
  # lib/math-equation.vala.
  def insert_square
    if has_selection
      insert_between('(', ')²', after: true)
    else
      iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      space_required = iter.backward_char && '⁰¹²³⁴⁵⁶⁷⁸⁹'.include?(iter.char)
      insert(space_required ? ' ²' : '²')
    end
  end

  # Inserts the √ root symbol, wrapping the selection in brackets first
  # when there is one, and switches to subscript entry for the degree.
  #
  # Ported from upstream's MathEquation.insert_nth_root in
  # lib/math-equation.vala.
  def insert_nth_root
    if has_selection
      insert_between('√(', ')')
    else
      before_mark = @buffer.create_mark(nil, @buffer.get_iter_at(mark: @buffer.get_mark('insert')), true)
      insert('√')
      @buffer.place_cursor(@buffer.get_iter_at(mark: before_mark))
      @buffer.delete_mark(before_mark)
    end
    self.number_mode = NumberMode::SUBSCRIPT
  end

  # Inserts "log", wrapping a selection in brackets first, and switches to
  # subscript entry for the base.
  #
  # Ported from upstream's MathEquation.insert_logarithm in
  # lib/math-equation.vala.
  def insert_logarithm
    if has_selection
      insert_between('(', ')')
    end
    insert('log')
    self.number_mode = NumberMode::SUBSCRIPT
  end

  # Inserts an exponent: with no selection, either the given base switched
  # into superscript entry, or a bare "^" when there is no base. With a
  # selection that is a plain (optionally signed) integer, the selection is
  # replaced by its superscript-digit rendering instead of wrapping it in
  # "^(...)".
  #
  # Ported from upstream's MathEquation.insert_exponent in
  # lib/math-equation.vala.
  def insert_exponent(base_number)
    if !has_selection
      if base_number.empty?
        insert('^')
      else
        insert(base_number)
        self.number_mode = NumberMode::SUPERSCRIPT
      end
    else
      sel_start, sel_end = @buffer.selection_bounds
      text = @buffer.text(sel_start, sel_end, true)
      if !text.match?(/\A[−-]?\d+\z/)
        if base_number.empty?
          insert_between('^(', ')')
        else
          insert_between("#{base_number}^(", ')')
        end
      else
        exponent = +base_number
        digits = text
        if text.start_with?('−', '-')
          exponent << '⁻'
          digits = text[1..]
        end
        digits.each_char { |char| exponent << Serializer::SUPER_DIGITS[char.to_i] }
        before_mark = @buffer.create_mark(nil, sel_start, true)
        @buffer.delete_selection(true, true)
        insert(exponent)
        if base_number.empty?
          @buffer.place_cursor(@buffer.get_iter_at(mark: before_mark))
        end
        @buffer.delete_mark(before_mark)
      end
    end
  end

  # Inserts the minus sign; in superscript entry, a dedicated superscript
  # minus once per exponent, falling back to plain entry after that.
  #
  # Ported from upstream's MathEquation.insert_subtract in
  # lib/math-equation.vala.
  def insert_subtract
    if number_mode == NumberMode::SUPERSCRIPT && @can_super_minus
      insert('⁻')
      @can_super_minus = false
    else
      insert('−')
      self.number_mode = NumberMode::NORMAL
    end
  end

  # Replaces the display with its prime factorization, smallest factor
  # first, joined by "×". Upstream runs this on a worker thread; this port's
  # solve path is already synchronous (see the class comment), so this is
  # too.
  #
  # Ported from upstream's MathEquation.factorize in lib/math-equation.vala.
  def factorize
    if is_empty
      nil
    else
      x = number
      if x.nil? || !x.integer? || is_sign_radix
        self.status = _('Need an integer to factorize')
      else
        text = x.factorize.each_with_index.map { |factor, index|
          rendered = @serializer.to_string(factor)
          index.zero? ? rendered : "×#{rendered}"
        }.join
        set(text)
      end
    end
  end

  def toggle_bit(bit)
    x = number
    if x.nil? || !x.integer?
      nil
    else
      if x.negative?
        bits = x.to_integer
      else
        bits = x.to_unsigned_integer
      end
      bits ^= (1 << bit)
      set_number(x.negative? ? Number.integer(bits) : Number.unsigned_integer(bits))
    end
  end

  private

    # The digraph substitution `insert` makes before a plain insert, or nil
    # when `text` triggers none: `××` -> `^`, `>>`/`>>>` -> `≫`/`⋙`, `<<` ->
    # `≪`.
    def digraph_replacement(text)
      if text == '×' && char_before == '×'
        '^'
      elsif text == '>' && char_before == '>'
        '≫'
      elsif text == '>' && char_before == '≫'
        '⋙'
      elsif text == '<' && char_before == '<'
        '≪'
      end
    end

    # The Equation subclass upstream calls MEquation: it hands variable,
    # function and unit lookups to this calculator's FunctionManager,
    # UnitManager and MathVariables.
    def backing_equation(expression)
      owner = self
      Class.new(Equation) do
        define_method(:variable_is_defined) { |name| name == '_' || !owner.variables[name].nil? }
        define_method(:get_variable) { |name| name == '_' ? owner.answer : owner.variables[name] }
        define_method(:set_variable) do |name, value|
          if name == '_'
            nil
          else
            owner.variables[name] = value
          end
        end
        define_method(:function_is_defined) { |name| FunctionManager.default.function_defined?(name) }
        define_method(:unit_is_defined) { |name| !UnitManager.default.defined_unit(name).nil? }
      end.new(expression)
    end

    def report_error(result)
      if ErrorCode.to_name(result.error_code) == 'ErrorCode.NONE'
        self.status = ''
      else
        self.status = error_message(result.error_code)
      end
      @error_token_start = result.error_start || 0
      @error_token_end = result.error_end || 0
    end

    def error_message(code)
      case code
      when ErrorCode::INVALID then _('Malformed expression')
      when ErrorCode::UNKNOWN_VARIABLE then _('Unknown variable')
      when ErrorCode::UNKNOWN_FUNCTION then _('Unknown function')
      when ErrorCode::UNKNOWN_CONVERSION then _('No conversion possible')
      when ErrorCode::UNKNOWN_UNIT then _('Unknown unit')
      when ErrorCode::UNKNOWN_RATE then _('No sane value to convert')
      when ErrorCode::MP then _('Calculation error')
      when ErrorCode::TIMED_OUT then _('Calculation took too long')
      else _('The result of the calculation is undefined')
      end
    end

    def repeat_last_operation
      if @last_token.nil? || @last_token.empty?
        nil
      else
        eq = backing_equation("#{ANS_STRING}#{@last_token}#{@serializer.to_string(@last_operand)}")
        eq.base = number_base
        eq.wordlen = word_size
        eq.angle_units = angle_units
        result = eq.parse
        if result.error_code == ErrorCode::NONE && result.value
          set_number(result.value)
        end
      end
    end

    def notify_display_changed
      @display_changed_handlers.each { |handler| handler.call(@serializer) }
    end

    def clear_ans
      if @ans_start_mark
        @buffer.remove_tag(@ans_tag, *@buffer.bounds)
      end
      @ans_start_mark = nil
      @ans_end_mark = nil
    end

    def ans_offsets
      if @ans_start_mark
        [
          @buffer.get_iter_at(mark: @ans_start_mark).offset,
          @buffer.get_iter_at(mark: @ans_end_mark).offset,
        ]
      else
        [-1, -1]
      end
    end

    def cursor_offset = @buffer.get_iter_at(mark: @buffer.get_mark('insert')).offset

    def char_before
      iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      iter.backward_char ? iter.char : nil
    end

    def char_after
      iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      iter.char.to_s.empty? ? nil : iter.char
    end

    def alpha_boundary?(char) = !char.nil? && (char.match?(/[[:alpha:]]/) || char == '_')

    # Replaces the selection (or inserts at the cursor, with nothing
    # selected) with `start_text` + the old content + `end_text`, leaving the
    # cursor just before `end_text`.
    def insert_between(start_text, end_text, after: false)
      push_undo_stack
      if @buffer.has_selection?
        sel_start, sel_end = @buffer.selection_bounds
        selected = @buffer.text(sel_start, sel_end, true)
        @buffer.delete(sel_start, sel_end)
        @buffer.insert(sel_start, start_text + selected + end_text)
        cursor = @buffer.get_iter_at(mark: @buffer.get_mark('insert')).offset
        unless after
          cursor -= end_text.length
        end
      else
        insert_at_cursor(start_text + end_text)
        cursor = cursor_offset
        unless after
          cursor -= end_text.length
        end
      end
      @buffer.place_cursor(@buffer.get_iter_at(offset: cursor))
    end

    def backspace_one_char
      iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      start_iter = @buffer.get_iter_at(mark: @buffer.get_mark('insert'))
      if start_iter.backward_char
        @buffer.delete(start_iter, iter)
      end
    end

    def insert_at_cursor(text)
      @buffer.insert_at_cursor(text)
    end

    def current_snapshot
      Snapshot.new(
        text:        display,
        cursor:      cursor_offset,
        ans:         @ans,
        ans_base:    @ans_base,
        is_real_ans: @is_real_ans,
        status:      @status,
        number_mode: @number_mode,
      )
    end

    def push_undo_stack
      @undo_stack.push(current_snapshot)
      @redo_stack.clear
    end

    def restore_snapshot(snapshot)
      @buffer.text = snapshot.text
      @buffer.place_cursor(@buffer.get_iter_at(offset: [snapshot.cursor, @buffer.char_count].min))
      @ans = snapshot.ans
      @ans_base = snapshot.ans_base
      @is_real_ans = snapshot.is_real_ans
      @status = snapshot.status
      @number_mode = snapshot.number_mode
    end
end
