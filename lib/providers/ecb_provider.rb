# frozen_string_literal: true

require 'rexml/document'

require_relative '../currency_provider'

# The European Central Bank's daily reference rates.
#
# Ported from upstream's lib/providers/ecb-provider.vala. The rates are quoted
# against the euro, so the EUR rate another provider supplies is what scales
# them; three currencies the ECB does not publish are pegged to the euro and
# carry fixed rates.
class EcbCurrencyProvider < AbstractCurrencyProvider
  # Currencies pegged to the euro, with the rate the peg fixes.
  FIXED_RATES = {
    'RSD' => '0.0085',
    'XAF' => '0.00152449',
    'XOF' => '0.00152449',
  }.freeze

  def initialize(currency_manager)
    super(currency_manager, base_currency_symbol: 'EUR')
  end

  def rate_filepath = File.join(cache_dir, 'eurofxref-daily.xml')

  def rate_source_url = 'https://exchange-api.gnome.org/ecb/eurofxref-daily.xml'

  def attribution_link = 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml'

  def provider_name = 'European Central Bank'

  def source_name = 'ECB'

  # The ECB writes its dates as "2026-01-02".
  def parse_date(date)
    if date.nil?
      nil
    else
      year, month, day = date.split('-').map(&:to_i)
      Time.new(year, month, day)
    end
  end

  protected

    def do_load_rates
      eur_rate = base_currency
      data = read_rate_file
      if eur_rate.nil? || data.nil?
        false
      else
        load_rates(data, eur_rate.value)
        super
      end
    end

  private

    def load_rates(data, eur_rate)
      cubes = cube_elements(data)
      date = cubes.map { |cube| cube.attributes['time'] }.compact.first
      cubes.each do |cube|
        if cube.attributes['currency'] && cube.attributes['rate']
          set_rate(
            cube.attributes['currency'],
            cube.attributes['rate'],
            eur_rate,
            date,
          )
        end
      end
      FIXED_RATES.each do |name, value|
        set_fixed_rate(
          name,
          value,
          eur_rate,
          date,
        )
      end
    end

    # The file nests Cube elements inside a default namespace, so they are
    # collected by name rather than by XPath.
    def cube_elements(data)
      document = REXML::Document.new(data)
      collected = []
      collect_cubes(document.root, collected)
      collected
    rescue REXML::ParseException => e
      warn "Couldn't parse ECB rate file #{rate_filepath}: #{e.message}"
      []
    end

    def collect_cubes(element, collected)
      if element
        if element.name == 'Cube'
          collected << element
        end
        element.elements.each { |child| collect_cubes(child, collected) }
      end
    end

    def set_rate(name, value, eur_rate, date)
      if currency(name).nil?
        rate = Number.from_string(value)
        if rate
          register_currency(
            name,
            source_name,
            eur_rate.multiply(rate),
            date,
          )
        end
      end
    end

    def set_fixed_rate(name, value, eur_rate, date)
      rate = Number.from_string(value)
      if rate
        register_currency(
          name,
          "#{source_name}#fixed",
          eur_rate.divide(rate),
          date,
        )
      end
    end
end
