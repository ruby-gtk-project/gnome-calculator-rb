# frozen_string_literal: true

require_relative '../currency_provider'

# The International Monetary Fund's representative exchange rates.
#
# Ported from upstream's lib/providers/imf-provider.vala. The source file is a
# tab-separated table whose rows name currencies in English, so the table below
# maps those names to their ISO codes.
class ImfCurrencyProvider < AbstractCurrencyProvider
  NAME_MAP = {
    'Euro'                => 'EUR',
    'Japanese yen'        => 'JPY',
    'U.K. pound'          => 'GBP',
    'U.S. dollar'         => 'USD',
    'Algerian dinar'      => 'DZD',
    'Australian dollar'   => 'AUD',
    'Botswana pula'       => 'BWP',
    'Brazilian real'      => 'BRL',
    'Brunei dollar'       => 'BND',
    'Canadian dollar'     => 'CAD',
    'Chilean peso'        => 'CLP',
    'Chinese yuan'        => 'CNY',
    'Czech koruna'        => 'CZK',
    'Danish krone'        => 'DKK',
    'Indian rupee'        => 'INR',
    'Israeli New Shekel'  => 'ILS',
    'Korean won'          => 'KRW',
    'Kuwaiti dinar'       => 'KWD',
    'Malaysian ringgit'   => 'MYR',
    'Mauritian rupee'     => 'MUR',
    'Mexican peso'        => 'MXN',
    'New Zealand dollar'  => 'NZD',
    'Norwegian krone'     => 'NOK',
    'Omani rial'          => 'OMR',
    'Peruvian sol'        => 'PEN',
    'Philippine peso'     => 'PHP',
    'Polish zloty'        => 'PLN',
    'Qatari riyal'        => 'QAR',
    'Saudi Arabian riyal' => 'SAR',
    'Singapore dollar'    => 'SGD',
    'Swedish krona'       => 'SEK',
    'Swiss franc'         => 'CHF',
    'Thai baht'           => 'THB',
    'Trinidadian dollar'  => 'TTD',
    'U.A.E. dirham'       => 'AED',
    'Uruguayan peso'      => 'UYU',
  }.freeze

  def rate_filepath = File.join(cache_dir, 'rms_five.xls')

  def rate_source_url = 'https://exchange-api.gnome.org/imf/rms_five.xls'

  def attribution_link = 'https://www.imf.org/external/np/fin/data/rms_five.aspx'

  def provider_name = 'International Monetary Fund'

  def source_name = 'IMF'

  # The IMF writes its dates as "January 2, 2026".
  def parse_date(date)
    if date.nil?
      nil
    else
      parts = date.split(' ')
      month = MONTHS_FULL.index(parts[0])
      if month.nil? || parts.length < 3
        nil
      else
        Time.new(parts[2].to_i, month + 1, parts[1].chop.to_i)
      end
    end
  end

  protected

    def do_load_rates
      data = read_rate_file
      if data.nil?
        false
      else
        load_table(data)
        super
      end
    end

  private

    # The table starts after the first blank line and stops at the next one.
    # The row whose first cell is "Currency" is the header, and carries the
    # date of each column.
    def load_table(data)
      headers = nil
      in_data = false
      finished = false
      data.split("\n").each do |line|
        unless finished
          line = line.lstrip
          if line.empty?
            if in_data
              finished = true
            else
              in_data = true
            end
          elsif in_data
            tokens = line.split("\t", -1)
            if tokens[0] != 'Currency' && headers
              load_row(tokens, headers)
            elsif tokens[0] == 'Currency' || headers.nil?
              headers = tokens
            end
          end
        end
      end
    end

    # The rates are quoted per currency unit in SDR, and the most recent
    # non-blank column is the one wanted.
    def load_row(tokens, headers)
      index = tokens[1..].each_index.find { |i| !tokens[i + 1].to_s.strip.empty? }
      if index
        value_index = index + 1
        symbol = NAME_MAP[tokens[0]]
        if symbol.nil?
          warn "Unknown currency '#{tokens[0]}'"
        else
          register_rate(symbol, tokens[value_index], headers[value_index])
        end
      end
    end

    def register_rate(symbol, text, date)
      value = Number.from_string(text.strip)
      if currency(symbol).nil? && value && !value.zero?
        register_currency(
          symbol,
          source_name,
          value.reciprocal,
          date,
        )
      end
    end
end

# An IMF provider that reads its table from a local file instead of the
# network, which is how the test suite supplies known rates.
#
# Ported from upstream's OfflineImfCurrencyProvider.
class OfflineImfCurrencyProvider < ImfCurrencyProvider
  def initialize(currency_manager, source_file)
    super(currency_manager)
    @source_file = source_file
  end

  private

    def download_to_cache
      FileUtils.mkdir_p(File.dirname(rate_filepath))
      FileUtils.cp(@source_file, rate_filepath)
    rescue StandardError => e
      warn "Couldn't copy #{source_name} currency rate file: #{e.message}"
    end
end
