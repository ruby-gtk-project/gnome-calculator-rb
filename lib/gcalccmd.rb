# frozen_string_literal: true

require_relative "gnome_calculator"

# Gcalccmd solves one expression given as an argument, or reads expressions
# from standard input until end of stream, "exit", "quit" or a blank line.
#
# Ported from upstream's src/gcalccmd.vala. It reads the same settings the
# window does so a rate refresh honours the user's interval, and it asks the
# currency manager for a synchronous refresh because there is no main loop to
# finish an asynchronous one.
class Gcalccmd
  def run(argv)
    refresh_rates
    if argv.length == 1
      solve(argv[0])
    else
      read_loop
    end
  end

  private

    def serializer
      @serializer ||= Serializer.new(DisplayFormat::AUTOMATIC, 10, 9)
    end

    def settings = @settings ||= Settings.new

    def refresh_rates
      CurrencyManager.default(async_load: false).tap do |manager|
        manager.refresh_interval = settings["refresh-interval"]
        manager.refresh_sync
      end
    end

    def read_loop
      requires_new_line = false
      reading = true
      while reading
        $stdout.print("> ")
        $stdout.flush
        line = $stdin.gets
        if line.nil?
          requires_new_line = true
          reading = false
        else
          line = line.strip
          if ["", "exit", "quit"].include?(line)
            reading = false
          else
            solve(line)
          end
        end
      end
      if requires_new_line
        $stdout.puts
      end
    end

    def solve(text)
      equation = Equation.new(normalise(text))
      equation.base = 10
      equation.wordlen = 32
      equation.angle_units = AngleUnit::DEGREES

      result = equation.parse
      serializer.representation_base = result.representation_base
      report(result)
    end

    # The thousands separators come out and the radix becomes a plain '.', so
    # an expression typed the way the display shows it still parses.
    #
    # Upstream guards against stripping a '.' separator; this port guards
    # against stripping whitespace too. Where upstream reads the separator from
    # nl_langinfo, the serializer falls back to a space (what nl_langinfo
    # answers in the C locale), and stripping spaces would run the words of
    # "1 meter in cm" together.
    def normalise(text)
      separator = serializer.thousands_separator
      stripped = text
      unless separator.strip.empty?
        stripped = text.gsub(separator, "")
      end
      stripped.tr(serializer.radix, ".")
    end

    def report(result)
      if result.value
        print_value(result.value)
      elsif result.error_code == ErrorCode::MP
        warn("Error #{Number.error || result.error_token}")
      else
        warn("Error #{result.error_code}")
      end
    end

    def print_value(value)
      text = serializer.to_string(value)
      if serializer.error
        warn(serializer.error)
        serializer.error = nil
      else
        $stdout.puts(text)
      end
    end
end
