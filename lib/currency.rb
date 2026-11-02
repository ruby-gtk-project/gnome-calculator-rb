# frozen_string_literal: true

require_relative 'number'
require_relative 'currency_provider'
require_relative 'providers/imf_provider'
require_relative 'providers/unt_provider'
require_relative 'providers/ecb_provider'
require_relative 'providers/boc_provider'

# One currency: its ISO code, display name and symbol, plus the rate a
# provider gave it and where that rate came from.
#
# Ported from the Currency class in upstream's lib/currency.vala.
class Currency
  attr_reader :name, :display_name, :symbol
  attr_accessor :source, :date, :provider, :value

  def initialize(name, display_name, symbol)
    @name = name
    @display_name = display_name
    @symbol = symbol
    @value = nil
    @source = nil
    @date = nil
    @provider = nil
  end
end

# CurrencyManager owns the currency table and the providers that fill in its
# rates.
#
# Ported from the CurrencyManager class in upstream's lib/currency.vala.
# Upstream's `updated` and `favorites_changed` signals become the on_updated
# and on_favorites_changed callbacks; `dispatch` is what a provider's
# background download hands its parsing step to, so a GUI can set a dispatcher
# that marshals onto the main loop.
class CurrencyManager
  attr_accessor :refresh_interval
  attr_reader :loaded

  class << self
    # Upstream's get_default. The providers are attached on first use, and
    # `default_providers: false` leaves the table bare, which is what gcalccmd
    # and the test suite want.
    def default(async_load: true, default_providers: true)
      @default ||= build_default(async_load, default_providers)
    end

    private

      def build_default(async_load, default_providers)
        new.tap do |manager|
          CURRENCIES.each { |code, name, symbol| manager.add_known_currency(code, name, symbol) }
          if default_providers
            ImfCurrencyProvider.new(manager)
            UnCurrencyProvider.new(manager)
            EcbCurrencyProvider.new(manager)
            BCCurrencyProvider.new(manager, 'TWD', 'fxtwdcad')
            manager.initialize_providers(async_load)
          end
        end
      end
  end

  # The currency table, in upstream's order: ISO code, name, symbol.
  CURRENCIES = [
    ['AED', 'UAE Dirham', 'إ.د'],
    ['AMD', 'Armenian Dram', '֏'],
    ['ARS', 'Argentine Peso', '$'],
    ['AUD', 'Australian Dollar', '$'],
    ['BDT', 'Bangladeshi Taka', '৳'],
    ['BHD', 'Bahraini Dinar', '.ب.د'],
    ['BND', 'Brunei Dollar', '$'],
    ['BRL', 'Brazilian Real', 'R$'],
    ['BWP', 'Botswana Pula', 'P'],
    ['CAD', 'Canadian Dollar', '$'],
    ['CHF', 'Swiss Franc', 'Fr'],
    ['CLP', 'Chilean Peso', '$'],
    ['CNY', 'Chinese Yuan', '¥'],
    ['COP', 'Colombian Peso', '$'],
    ['CZK', 'Czech Koruna', 'Kč'],
    ['DKK', 'Danish Krone', 'kr'],
    ['DZD', 'Algerian Dinar', 'ج.د'],
    ['EGP', 'Egyptian Pound', '£E'],
    ['EUR', 'Euro', '€'],
    ['GBP', 'British Pound Sterling', '£'],
    ['HKD', 'Hong Kong Dollar', '$'],
    ['HUF', 'Hungarian Forint', 'Ft'],
    ['IDR', 'Indonesian Rupiah', 'Rp'],
    ['ILS', 'Israeli New Shekel', '₪'],
    ['INR', 'Indian Rupee', '₹'],
    ['IRR', 'Iranian Rial', '﷼'],
    ['ISK', 'Icelandic Krona', 'kr'],
    ['JPY', 'Japanese Yen', '¥'],
    ['JMD', 'Jamaican Dollar', '$'],
    ['KRW', 'South Korean Won', '₩'],
    ['KWD', 'Kuwaiti Dinar', 'ك.د'],
    ['KZT', 'Kazakhstani Tenge', '₸'],
    ['LKR', 'Sri Lankan Rupee', 'Rs'],
    ['LYD', 'Libyan Dinar', 'د.ل'],
    ['MUR', 'Mauritian Rupee', 'Rs'],
    ['MXN', 'Mexican Peso', '$'],
    ['MYR', 'Malaysian Ringgit', 'RM'],
    ['NGN', 'Nigerian Naira', '₦'],
    ['NOK', 'Norwegian Krone', 'kr'],
    ['NPR', 'Nepalese Rupee', 'Rs'],
    ['NZD', 'New Zealand Dollar', '$'],
    ['OMR', 'Omani Rial', 'ع.ر.'],
    ['PEN', 'Peruvian Nuevo Sol', 'S/.'],
    ['PHP', 'Philippine Peso', '₱'],
    ['PKR', 'Pakistani Rupee', 'Rs'],
    ['PLN', 'Polish Złoty', 'zł'],
    ['QAR', 'Qatari Riyal', 'ق.ر'],
    ['RON', 'New Romanian Leu', 'L'],
    ['RUB', 'Russian Ruble', '₽'],
    ['RSD', 'Serbian Dinar', 'дин'],
    ['SAR', 'Saudi Riyal', 'س.ر'],
    ['SEK', 'Swedish Krona', 'kr'],
    ['SGD', 'Singapore Dollar', '$'],
    ['THB', 'Thai Baht', '฿'],
    ['TND', 'Tunisian Dinar', 'ت.د'],
    ['TRY', 'Turkish Lira', '₺'],
    ['TTD', 'T&T Dollar', '$'],
    ['TWD', 'New Taiwan Dollar', 'NT$'],
    ['UAH', 'Ukrainian Hryvnia', '₴'],
    ['USD', 'US Dollar', '$'],
    ['UYU', 'Uruguayan Peso', '$'],
    ['VND', 'Vietnamese Dong', '₫'],
    ['XAF', 'Central African CFA Franc', 'F.CFA'],
    ['XOF', 'West African CFA Franc', 'F.CFA'],
    ['ZAR', 'South African Rand', 'R'],
  ].freeze

  def initialize
    @currencies = []
    @providers = []
    @favorites = []
    @refresh_interval = 0
    @loaded = false
    @updated_handlers = []
    @favorites_changed_handlers = []
    @dispatcher = nil
  end

  def on_updated(&block) = @updated_handlers << block

  def on_favorites_changed(&block) = @favorites_changed_handlers << block

  # How a provider's background thread hands work back. Without a dispatcher
  # the work runs on the calling thread, which is what a command-line run
  # wants; a GUI sets one that marshals onto the main loop.
  attr_writer :dispatcher

  def dispatch(&block)
    if @dispatcher
      @dispatcher.call(block)
    else
      block.call
    end
  end

  def favorite_currencies=(codes)
    @favorites = codes.dup
    @favorites_changed_handlers.each(&:call)
  end

  def favorite?(name) = @favorites.include?(name)

  # The attribution each provider asks for, as the markup the preferences show.
  def provider_links
    @providers.map { |provider| format('<a href="%s">%s</a>', provider.attribution_link, provider.provider_name) }
  end

  def add_provider(provider)
    @providers << provider
  end

  def refresh_sync
    @loaded = false
    @providers.each do |provider|
      provider.refresh_interval = @refresh_interval
      if @refresh_interval.positive?
        provider.update_rates(false)
      end
    end
  end

  def refresh_async(force = false)
    @loaded = false
    @providers.each do |provider|
      provider.refresh_interval = @refresh_interval
      if force || @refresh_interval.positive?
        provider.update_rates(true, force)
      end
    end
  end

  # Starts each provider, which downloads its rates if its cached copy is out
  # of date.
  def initialize_providers(async_load = true)
    @providers.each do |provider|
      provider.on_updated { |symbol| provider_updated(symbol) }
      provider.update_rates(async_load)
    end
  end

  def currencies = @currencies.dup

  # The currency `name`, but only once it has a usable rate.
  def currency(name)
    found = @currencies.find { |c| c.name == name }
    if found.nil?
      nil
    else
      value = found.value
      if value.nil? || value.negative? || value.zero?
        nil
      else
        found
      end
    end
  end

  def value(name) = currency(name)&.value

  def known_currency?(short_name) = @currencies.any? { |c| c.name == short_name }

  # Adds the currency a provider just supplied a rate for. One that is not in
  # the table is added anyway, so a new ISO code still converts.
  def add_currency(short_name, source)
    existing = @currencies.find { |c| c.name == short_name }
    if existing
      existing.source = source
      existing
    else
      warn "Currency #{short_name} is not in the currency table"
      Currency.new(short_name, short_name, short_name).tap do |currency|
        currency.source = source
        @currencies << currency
      end
    end
  end

  # Used by get_default to fill the table before any provider runs.
  def add_known_currency(code, display_name, symbol)
    @currencies << Currency.new(code, display_name, symbol)
  end

  # Every currency whose code starts with `text`, split by whether it is one of
  # the user's favourites, for the completion popup.
  def currencies_eligible_for_autocompletion(text, favorite)
    prefix = text.upcase
    @currencies.select do |currency|
      currency.name.upcase.start_with?(prefix) && favorite == favorite?(currency.name)
    end
  end

  private

    def provider_updated(symbol)
      @loaded = false
      first = @providers.first
      if first
        @loaded = first.loaded
      end
      @updated_handlers.each { |handler| handler.call(symbol) }
    end
end
