# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's org.gnome.calculator GSettings
# schema (data/org.gnome.calculator.gschema.xml).
#
# Upstream uses GSettings, which needs a compiled schema installed into the
# system's glib-2.0/schemas directory. Requiring an install step to run the app
# from a checkout is worse than the alternative, so the same keys, defaults and
# semantics are backed by a small JSON file under XDG_CONFIG_HOME instead.
#
# The enumerated keys keep upstream's nicks — 'automatic', 'degrees', 'basic'
# and so on — rather than their numeric values, so a settings file reads the
# way the schema does.
class Settings
  DEFAULTS = {
    'history-tape'        => [],
    'accuracy'            => 9,
    'word-size'           => 64,
    'base'                => 10,
    'show-thousands'      => false,
    'show-zeroes'         => false,
    'number-format'       => 'automatic',
    'angle-units'         => 'degrees',
    'refresh-interval'    => 604_800,
    'currency-display'    => 'name',
    'enabled-completions' => %w[builtin function currency favorite variable],
    'favorite-currencies' => [],
    'button-mode'         => 'basic',
    'unit-category'       => 'angle',
    'source-units'        => ['degree'],
    'target-units'        => ['radian'],
    'precision'           => 2000,
    'window-position'     => [-1, -1],
    'window-maximized'    => false,
    'window-size'         => [-1, -1],
  }.freeze

  # The ranges the schema puts on its numeric keys.
  RANGES = {
    'word-size' => (8..64),
    'base'      => (2..16),
  }.freeze

  NUMBER_FORMATS = { 'automatic' => 0, 'fixed' => 1, 'scientific' => 2, 'engineering' => 3 }.freeze
  BUTTON_MODES = {
    'basic'       => 0,
    'advanced'    => 1,
    'financial'   => 2,
    'programming' => 3,
    'keyboard'    => 4,
    'conversion'  => 5,
  }.freeze
  ANGLE_UNITS = { 'radians' => 0, 'degrees' => 1, 'gradians' => 2 }.freeze
  CURRENCY_DISPLAYS = { 'code' => 0, 'name' => 1, 'both' => 2 }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = clamp(key.to_s, value)
    write
    @values[key.to_s]
  end

  def location = @path

  # Named accessors for every key, so callers do not repeat the strings.
  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key] == false
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # The angle unit the parser wants, from the 'angle-units' nick.
  def angle_unit
    case self['angle-units']
    when 'radians' then AngleUnit::RADIANS
    when 'gradians' then AngleUnit::GRADIANS
    else AngleUnit::DEGREES
    end
  end

  # The display format the serializer wants, from the 'number-format' nick.
  def display_format
    case self['number-format']
    when 'fixed' then DisplayFormat::FIXED
    when 'scientific' then DisplayFormat::SCIENTIFIC
    when 'engineering' then DisplayFormat::ENGINEERING
    else DisplayFormat::AUTOMATIC
    end
  end

  # Restores the window geometry recorded by the previous run.
  def apply_to(window)
    width, height = self['window-size']
    if width.positive? && height.positive?
      window.set_default_size(width, height)
    end
    if self['window-maximized']
      window.maximize
    end
  end

  # Records the window geometry, skipping the size while maximized so the
  # restored size is the one the user actually chose.
  def remember(window)
    self['window-maximized'] = window.maximized?
    unless window.maximized?
      @values['window-size'] = [window.default_width, window.default_height]
      write
    end
  end

  private

    def clamp(key, value)
      range = RANGES[key]
      if range.nil? || !value.is_a?(Integer)
        value
      else
        value.clamp(range.first, range.last)
      end
    end

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-calculator',
        'settings.json',
      )
    end

    def read
      if File.exist?(@path)
        JSON.parse(File.read(@path))
      else
        {}
      end
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
