# frozen_string_literal: true

require 'rexml/document'

require_relative '../currency_provider'

# One series from the Bank of Canada's Valet observations, which is how the
# calculator gets a rate for a currency the other providers do not publish.
#
# Ported from upstream's lib/providers/boc-provider.vala. One instance covers
# one series — the currency's code and the file name it is published under —
# and the rate is quoted against the Canadian dollar.
class BCCurrencyProvider < AbstractCurrencyProvider
  attr_reader :currency_code, :currency_filename

  def initialize(currency_manager, currency_code, currency_filename)
    super(currency_manager, base_currency_symbol: 'CAD')
    @currency_code = currency_code
    @currency_filename = currency_filename
  end

  def rate_filepath = File.join(cache_dir, "#{@currency_filename}.xml")

  def rate_source_url = "https://exchange-api.gnome.org/boc/#{@currency_filename}.xml"

  def attribution_link
    "https://www.bankofcanada.ca/valet/observations/#{@currency_filename}/xml?recent=1"
  end

  def provider_name = 'Bank of Canada'

  def source_name = "BC-#{@currency_code}"

  # The Bank of Canada writes its dates as "2026-01-02".
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
      cad_rate = base_currency
      data = read_rate_file
      if cad_rate.nil? || data.nil?
        false
      else
        load_observation(data, cad_rate.value)
        super
      end
    end

  private

    # The file holds a list of observations; the last one is the most recent.
    def load_observation(data, cad_rate)
      observation = last_observation(data)
      if observation.nil?
        false
      else
        value = observation.elements['v']&.text
        if value.nil?
          false
        else
          set_rate(
            @currency_code,
            value,
            cad_rate,
            observation.attributes['d'],
          )
        end
      end
    end

    def last_observation(data)
      document = REXML::Document.new(data)
      observations = []
      collect_named(document.root, 'o', observations)
      observations.last
    rescue REXML::ParseException => e
      warn "Couldn't parse rate file #{rate_filepath}: #{e.message}"
      nil
    end

    def collect_named(element, name, collected)
      if element
        if element.name == name
          collected << element
        end
        element.elements.each { |child| collect_named(child, name, collected) }
      end
    end

    def set_rate(name, value, cad_rate, date)
      rate = Number.from_string(value)
      if rate && !rate.zero?
        register_currency(
          name,
          source_name,
          cad_rate.divide(rate),
          date,
        )
      end
    end
end
