# frozen_string_literal: true

require 'fileutils'
require 'soup3'

require_relative 'number'

# The behaviour every exchange-rate source shares: a cached copy of the source
# file, a refresh interval that decides when to download it again, and the
# parsing step each subclass fills in.
#
# Ported from upstream's lib/currency-provider.vala, which declares the
# CurrencyProvider interface and the AbstractCurrencyProvider that implements
# the shared half. Ruby needs no separate interface, so the two become one
# class; the methods a subclass must supply raise NotImplementedError.
#
# Upstream downloads with libsoup and its `updated` signal; this port downloads
# with the `soup3` gem (a GObject-Introspection binding over the same libsoup)
# and the signal becomes the on_updated callbacks. An async refresh runs on a
# thread and hands the parsing step back through the manager's dispatcher, so
# a GUI can marshal it onto the main loop.
class AbstractCurrencyProvider
  MONTHS_ABBREVIATED = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
  MONTHS_FULL = %w[
    January February March April May June
    July August September October November December
  ].freeze

  attr_accessor :refresh_interval
  attr_reader :currency_manager, :base_currency_symbol, :loaded

  def initialize(currency_manager, base_currency_symbol: nil)
    @currency_manager = currency_manager
    @base_currency_symbol = base_currency_symbol
    @refresh_interval = 0
    @loaded = false
    @loading = false
    @waiting_for_base = false
    @currencies = []
    @updated_handlers = []
    currency_manager.add_provider(self)
  end

  def on_updated(&block) = @updated_handlers << block

  # What a subclass must supply.
  def rate_filepath = raise(NotImplementedError, "#{self.class} must supply rate_filepath")

  def rate_source_url = raise(NotImplementedError, "#{self.class} must supply rate_source_url")

  def attribution_link = raise(NotImplementedError, "#{self.class} must supply attribution_link")

  def provider_name = raise(NotImplementedError, "#{self.class} must supply provider_name")

  def source_name = raise(NotImplementedError, "#{self.class} must supply source_name")

  def clear
    FileUtils.rm_f(rate_filepath)
  end

  def register_currency(symbol, source, value, date)
    @currency_manager.add_currency(symbol, source).tap do |currency|
      currency.value = value
      currency.date = date
      currency.provider = self
      @currencies << currency
      notify_updated(symbol)
    end
  end

  # The date a rate carries, in the format this source writes it. Subclasses
  # that publish a date override this.
  def parse_date(_date) = nil

  def update_rates(async_load = true, force = false)
    @loaded = false
    unless @loading
      @loading = true
      if !force && !file_needs_update?(rate_filepath, refresh_interval)
        @loading = false
        do_load_rates
      else
        start_download(async_load)
      end
    end
  end

  protected

    # Where the downloaded source files are kept, which is upstream's
    # g_get_user_cache_dir()/gnome-calculator.
    def cache_dir
      File.join(
        ENV.fetch('XDG_CACHE_HOME', File.expand_path('~/.cache')),
        'gnome-calculator',
      )
    end

    def currency(name) = @currency_manager.currency(name)

    # The currency this source's rates are quoted against. When it has not
    # arrived yet the load is retried once it does, which is how a source
    # quoted in EUR waits for the source that supplies EUR.
    def base_currency
      if @base_currency_symbol.nil?
        nil
      else
        rate = currency(@base_currency_symbol)
        if rate.nil?
          retry_when_base_arrives
          nil
        else
          rate
        end
      end
    end

    # Reads the cached file and registers what it holds. Subclasses override
    # this, parse their file and then call super.
    def do_load_rates
      @loaded = true
      notify_updated(nil)
      @loaded
    end

    def read_rate_file
      if File.exist?(rate_filepath)
        File.read(rate_filepath, encoding: 'UTF-8', invalid: :replace, undef: :replace)
      end
    end

  private

    def notify_updated(symbol)
      @updated_handlers.each { |handler| handler.call(symbol) }
    end

    def retry_when_base_arrives
      unless @waiting_for_base
        @waiting_for_base = true
        @currency_manager.on_updated do |symbol|
          if symbol == @base_currency_symbol
            @loading = false
            do_load_rates
          end
        end
      end
    end

    def start_download(async_load)
      if async_load
        Thread.new do
          download_to_cache
          @currency_manager.dispatch do
            @loading = false
            do_load_rates
          end
        end
      else
        download_to_cache
        @loading = false
        do_load_rates
      end
    end

    # A file needs downloading again when it is missing, empty or older than
    # the refresh interval. An interval of zero means never.
    def file_needs_update?(filename, max_age)
      if max_age.zero?
        false
      elsif !File.file?(filename)
        true
      else
        File.size(filename).zero? || (Time.now - File.mtime(filename)) > max_age
      end
    end

    def download_to_cache
      FileUtils.mkdir_p(File.dirname(rate_filepath))
      body = fetch(rate_source_url)
      if body
        File.binwrite(rate_filepath, body)
      end
    rescue StandardError => e
      warn "Couldn't download #{source_name} currency rate file: #{e.message}"
    end

    # Soup::Session follows redirects on its own, so this needs no retry loop.
    def fetch(url)
      message = Soup::Message.new('GET', url)
      bytes = session.send_and_read(message)
      if message.status_code == 200
        bytes.to_s
      else
        warn "Couldn't download #{source_name} currency rate file: #{message.status_code}"
        nil
      end
    end

    def session
      @session ||= Soup::Session.new.tap { |s| s.user_agent = 'gnome-calculator-rb' }
    end
end
