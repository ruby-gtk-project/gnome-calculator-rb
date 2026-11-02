# frozen_string_literal: true

require_relative '../currency_provider'

# The United Nations Treasury's operational rates of exchange.
#
# Ported from upstream's lib/providers/unt-provider.vala. The source file is a
# tab-separated table whose rows carry the ISO code directly, quoted against
# the US dollar.
class UnCurrencyProvider < AbstractCurrencyProvider
  SYMBOL_INDEX = 2
  DATE_INDEX = 3
  VALUE_INDEX = 4

  def initialize(currency_manager)
    super(currency_manager, base_currency_symbol: 'USD')
  end

  def rate_filepath = File.join(cache_dir, 'un-daily.xls')

  def rate_source_url = 'https://exchange-api.gnome.org/unt/un-daily.xls'

  def attribution_link = 'https://treasury.un.org/operationalrates/OperationalRates.php'

  def provider_name = 'United Nations Treasury'

  def source_name = 'UNT'

  # The UN writes its dates as "02 Jan 2026".
  def parse_date(date)
    if date.nil?
      nil
    else
      parts = date.split(' ')
      month = MONTHS_ABBREVIATED.index(parts[1])
      if month.nil? || parts.length < 3
        nil
      else
        Time.new(parts[2].to_i, month + 1, parts[0].to_i)
      end
    end
  end

  protected

    def do_load_rates
      usd_currency = base_currency
      data = read_rate_file
      if usd_currency.nil? || data.nil?
        false
      else
        load_table(data, usd_currency.value)
        super
      end
    end

  private

    # The table starts after the first blank line and stops at the next one.
    def load_table(data, usd_rate)
      in_data = false
      finished = false
      data.split("\r\n").each do |line|
        unless finished
          line = line.lstrip
          if line.empty?
            if in_data
              finished = true
            else
              in_data = true
            end
          elsif in_data
            load_row(line.split("\t", -1), usd_rate)
          end
        end
      end
    end

    def load_row(tokens, usd_rate)
      if tokens.length > VALUE_INDEX
        name = tokens[SYMBOL_INDEX]
        value = tokens[VALUE_INDEX].to_s.lstrip
        if currency(name).nil? && @currency_manager.known_currency?(name)
          register_rate(
            name,
            value,
            usd_rate,
            tokens[DATE_INDEX],
          )
        end
      end
    end

    def register_rate(name, value, usd_rate, date)
      rate = Number.from_string(value)
      if rate
        register_currency(
          name,
          source_name,
          usd_rate.multiply(rate),
          date,
        )
      end
    end
end
