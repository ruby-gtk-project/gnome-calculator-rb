# frozen_string_literal: true

require_relative 'number'
require_relative 'equation'
require_relative 'currency'

# One unit: its name, the name shown to the user, the symbols that stand for it
# in an expression, and the two expressions that convert a value to and from
# the category's base unit.
#
# Ported from the Unit class in upstream's lib/unit.vala.
class Unit
  attr_reader :name, :display_name

  def initialize(name, display_name, from_function, to_function, symbols)
    @name = name
    @display_name = display_name
    @from_function = from_function
    @to_function = to_function
    @symbols = symbols.split(',')
  end

  def symbols = @symbols.dup

  def matches_symbol?(symbol, case_sensitive = true)
    if case_sensitive
      @symbols.include?(symbol)
    else
      @symbols.any? { |s| s.downcase == symbol.downcase }
    end
  end

  # Into the category's base unit. A unit with no conversion expression is a
  # currency, whose rate stands in for one.
  def convert_from(x)
    if @from_function
      solve_function(@from_function, x)
    else
      rate = CurrencyManager.default.value(name)
      if rate.nil?
        nil
      else
        x.divide(rate)
      end
    end
  end

  # Out of the category's base unit.
  def convert_to(x)
    if @to_function
      solve_function(@to_function, x)
    else
      rate = CurrencyManager.default.value(name)
      if rate.nil?
        nil
      else
        x.multiply(rate)
      end
    end
  end

  private

    def solve_function(function, x)
      equation = UnitSolveEquation.new(function, x)
      equation.base = 10
      equation.wordlen = 32
      value = equation.parse.value
      if value.nil?
        warn "Failed to convert value: #{function}"
      end
      value
    end
end

# The equation a unit's conversion expression is solved as: every name in it is
# the value being converted.
#
# Ported from upstream's UnitSolveEquation in lib/unit.vala.
class UnitSolveEquation < Equation
  def initialize(function, x)
    super(function)
    @x = x
  end

  def variable_is_defined(_name) = true

  def get_variable(_name) = @x
end

# A group of units that convert between each other, such as Length.
#
# Ported from the UnitCategory class in upstream's lib/unit.vala.
class UnitCategory
  attr_reader :name, :display_name

  def initialize(name, display_name)
    @name = name
    @display_name = display_name
    @units = []
  end

  def add_unit(unit)
    @units << unit
  end

  def units = @units.dup

  # A unit of this category by name. Answers nil when the name is ambiguous,
  # which is what lets the manager fall back to a case-insensitive search.
  def unit_by_name(name, case_sensitive = true)
    matches = @units.select do |unit|
      if case_sensitive
        unit.name == name
      else
        unit.name.downcase == name.downcase
      end
    end
    if matches.length == 1
      matches.first
    end
  end

  def unit_by_symbol(symbol, _case_sensitive = true)
    matches = @units.select { |unit| unit.matches_symbol?(symbol) }
    if matches.length == 1
      matches.first
    elsif matches.empty?
      insensitive_match(symbol)
    end
  end

  def convert(x, x_units, z_units)
    value = x_units.convert_from(x)
    if value.nil?
      nil
    else
      z_units.convert_to(value)
    end
  end

  private

    def insensitive_match(symbol)
      matches = @units.select { |unit| unit.matches_symbol?(symbol, false) }
      if matches.length == 1
        matches.first
      end
    end
end

# UnitManager owns every unit category, and is what resolves a unit name in an
# expression.
#
# Ported from the UnitManager class in upstream's lib/unit.vala. The unit table
# below is upstream's get_default, in the same order; the currency category is
# filled from the CurrencyManager, so a currency converts like any other unit.
class UnitManager
  class << self
    # Upstream's get_default.
    def default = @default ||= build_default

    private

      def build_default
        new.tap do |manager|
          UNITS.each do |category_name, display_name, units|
            category = manager.add_category(category_name, display_name)
            units.each { |unit| category.add_unit(Unit.new(*unit)) }
          end
          manager.add_currency_category
        end
      end
  end

  ANGLE_UNITS = [
    ['degree', 'Degrees (Decimal)', 'π*x/180', '180x/π', 'degree,degrees,deg'],
    ['dms', 'Degrees (D°M′S″)', 'π*x/180', '180x/π', ''],
    ['radian', 'Radians', 'x', 'x', 'radian,radians,rad'],
    ['gradian', 'Gradians', 'π*x/200', '200x/π', 'gradian,gradians,grad'],
  ].freeze

  LENGTH_UNITS = [
    ['parsec', 'Parsecs', '30857000000000000x', 'x/30857000000000000', 'parsec,parsecs,pc'],
    ['lightyear', 'Light Years', '9460730472580800x', 'x/9460730472580800', 'lightyear,lightyears,ly'],
    ['astronomical-unit', 'Astronomical Units', '149597870700x', 'x/149597870700', 'au'],
    ['rack-unit', 'Rack Units', 'x/22.49718785151856', '22.49718785151856x', 'U'],
    ['nautical-mile', 'Nautical Miles', '1852x', 'x/1852', 'nmi'],
    ['mile', 'Miles', '1609.344x', 'x/1609.344', 'mile,miles,mi'],
    ['kilometer', 'Kilometers', '1000x', 'x/1000', 'kilometer,kilometers,km,kms'],
    ['cable', 'Cables', '219.456x', 'x/219.456', 'cable,cables,cb'],
    ['fathom', 'Fathoms', '1.8288x', 'x/1.8288', 'fathom,fathoms,ftm'],
    ['meter', 'Meters', 'x', 'x', 'meter,meters,m'],
    ['yard', 'Yards', '0.9144x', 'x/0.9144', 'yard,yards,yd'],
    ['foot', 'Feet', '0.3048x', 'x/0.3048', 'foot,feet,ft'],
    ['inch', 'Inches', '0.0254x', 'x/0.0254', 'inch,inches,in'],
    ['centimeter', 'Centimeters', 'x/100', '100x', 'centimeter,centimeters,cm,cms'],
    ['millimeter', 'Millimeters', 'x/1000', '1000x', 'millimeter,millimeters,mm'],
    ['micrometer', 'Micrometers', 'x/1000000', '1000000x', 'micrometer,micrometers,um'],
    ['nanometer', 'Nanometers', 'x/1000000000', '1000000000x', 'nanometer,nanometers,nm'],
    [
      'point',
      'Desktop Publishing Points',
      '0.000352777778x',
      'x/0.000352777778',
      'point,pt,points,pts',
    ],
  ].freeze

  SPEED_UNITS = [
    ['kilometers-hour', 'Kilometers per Hour', 'x/3.6', '3.6x', 'kilometers per hour,kmph,kmh,kph'],
    [
      'miles-hour',
      'Miles per Hour',
      'x/2.23693629',
      '2.23693629x',
      'milesph,miles per hour,mi/h,miph,mph',
    ],
    ['meters-second', 'Meters per Second', 'x', 'x', 'meters per second,mps'],
    ['feet-second', 'Feet per Second', 'x/3.28084', '3.28084x', 'fps,feet per second,feetps'],
    ['knot', 'Knots', 'x/1.94384449', '1.94384449x', 'kt,kn,nd,knot,knots'],
  ].freeze

  AREA_UNITS = [
    ['hectare', 'Hectares', '10000x', 'x/10000', 'hectare,hectares,ha'],
    ['acre', 'Acres', '4046.8564224x', 'x/4046.8564224', 'acre,acres'],
    ['square-mile', 'Square Miles', '2589988.110336x', 'x/2589988.110336', 'mi²'],
    ['square-foot', 'Square Feet', 'x/10.763910417', '10.763910417x', 'ft²'],
    ['square-kilometer', 'Square Kilometers', '1000000x', '0.000001x', 'km²'],
    ['square-meter', 'Square Meters', 'x', 'x', 'm²'],
    ['square-centimeter', 'Square Centimeters', '0.0001x', '10000x', 'cm²'],
    ['square-millimeter', 'Square Millimeters', '0.000001x', '1000000x', 'mm²'],
  ].freeze

  VOLUME_UNITS = [
    ['cubic-meter', 'Cubic Meters', '1000x', 'x/1000', 'm³'],
    ['imperial-gallon', 'British Gallons', '4.54609x', 'x/4.54609', 'imp_gallon,imp_gallons,imp_gal'],
    ['gallon', 'US Gallons', '3.785412x', 'x/3.785412', 'gallon,gallons,gal'],
    ['litre', 'Liters', 'x', 'x', 'litre,litres,liter,liters,L'],
    ['quart', 'US Quarts', '0.9463529x', 'x/0.9463529', 'quart,quarts,qt'],
    ['imperial-pint', 'British Pints', '0.56826125x', 'x/0.56826125', 'imp_pint,imp_pints,imp_pt'],
    ['pint', 'US Pints', '0.4731765x', 'x/0.4731765', 'pint,pints,pt'],
    ['cup', 'Metric Cups', '0.25x', '4x', 'cup,cups,cp'],
    [
      'millilitre',
      'Milliliters',
      '0.001x',
      '1000x',
      'millilitre,millilitres,milliliter,milliliters,mL,cm³',
    ],
    ['microlitre', 'Microliters', '0.000001x', '1000000x', 'mm³,μL,uL'],
  ].freeze

  WEIGHT_UNITS = [
    ['tonne', 'Tonnes', '1000x', 'x/1000', 'tonne,tonnes'],
    [
      'kilograms',
      'Kilograms',
      'x',
      'x',
      'kilogram,kilograms,kilogramme,kilogrammes,kg,kgs',
    ],
    ['pound', 'Pounds', '0.45359237x', 'x/0.45359237', 'pound,pounds,lb,lbs'],
    ['ounce', 'Ounces', '0.02834952x', 'x/0.02834952', 'ounce,ounces,oz'],
    ['troy-ounce', 'Troy Ounces', '0.0311034768x', 'x/0.0311034768', 'Troy ounce,Troy ounces,ozt'],
    ['gram', 'Grams', '0.001x', '1000x', 'gram,grams,gramme,grammes,g'],
    [
      'milligram',
      'Milligrams',
      '0.000001x',
      '1000000x',
      'milligram,milligrams,milligramme,milligrammes,mg',
    ],
    [
      'microgram',
      'Micrograms',
      '0.000000001x',
      '1000000000x',
      'microgram,micrograms,microgramme,microgrammes,μg,ug',
    ],
    ['stone', 'Stone', '6.350293x', 'x/6.350293', 'stone,st,stones'],
  ].freeze

  DURATION_UNITS = [
    ['century', 'Centuries', '3155760000x', 'x/3155760000', 'century,centuries'],
    ['decade', 'Decades', '315576000x', 'x/315576000', 'decade,decades'],
    ['year', 'Years', '31557600x', 'x/31557600', 'year,years'],
    ['month', 'Months', '2629800x', 'x/2629800', 'month,months'],
    ['week', 'Weeks', '604800x', 'x/604800', 'week,weeks'],
    ['day', 'Days', '86400x', 'x/86400', 'day,days'],
    ['hour', 'Hours', '3600x', 'x/3600', 'hour,hours'],
    ['minute', 'Minutes', '60x', 'x/60', 'minute,minutes'],
    ['second', 'Seconds', 'x', 'x', 'second,seconds,s'],
    ['millisecond', 'Milliseconds', '0.001x', '1000x', 'millisecond,milliseconds,ms'],
    ['microsecond', 'Microseconds', '0.000001x', '1000000x', 'microsecond,microseconds,us,μs'],
    ['nanosecond', 'Nanoseconds', '0.000000001x', '1000000000x', 'nanosecond,nanoseconds,ns'],
  ].freeze

  TEMPERATURE_UNITS = [
    ['degree-celsius', 'Celsius', 'x+273.15', 'x-273.15', 'degC,°C,˚C,C,c,Celsius,celsius'],
    [
      'degree-fahrenheit',
      'Fahrenheit',
      '(x+459.67)*5/9',
      'x*9/5-459.67',
      'degF,°F,˚F,F,f,Fahrenheit,fahrenheit',
    ],
    ['degree-kelvin', 'Kelvin', 'x', 'x', 'k,K,Kelvin,kelvin'],
    ['degree-rankine', 'Rankine', 'x*5/9', 'x*9/5', 'degR,°R,˚R,°Ra,˚Ra,r,R,Rankine,rankine'],
  ].freeze

  # IEC prefixes throughout: 1 kB is 1000 bytes and 1 KiB is 1024.
  DIGITAL_STORAGE_UNITS = [
    ['bit', 'Bits', 'x/8', '8x', 'bit,bits,b'],
    ['byte', 'Bytes', 'x', 'x', 'byte,bytes,B'],
    ['nibble', 'Nibbles', 'x/2', '2x', 'nibble,nibbles'],
    # The SI symbol for kilo is k, but KB and Kb are widely used and accepted.
    ['kilobit', 'Kilobits', '1000x/8', '8x/1000', 'kilobit,kilobits,kb,Kb'],
    ['kilobyte', 'Kilobytes', '1000x', 'x/1000', 'kilobyte,kilobytes,kB,KB'],
    ['kibibit', 'Kibibits', '1024x/8', '8x/1024', 'kibibit,kibibits,Kib'],
    ['kibibyte', 'Kibibytes', '1024x', 'x/1024', 'kibibyte,kibibytes,KiB'],
    ['megabit', 'Megabits', '1000000x/8', '8x/1000000', 'megabit,megabits,Mb'],
    ['megabyte', 'Megabytes', '1000000x', 'x/1000000', 'megabyte,megabytes,MB'],
    ['mebibit', 'Mebibits', '1048576x/8', '8x/1048576', 'mebibit,mebibits,Mib'],
    ['mebibyte', 'Mebibytes', '1048576x', 'x/1048576', 'mebibyte,mebibytes,MiB'],
    ['gigabit', 'Gigabits', '1000000000x/8', '8x/1000000000', 'gigabit,gigabits,Gb'],
    ['gigabyte', 'Gigabytes', '1000000000x', 'x/1000000000', 'gigabyte,gigabytes,GB'],
    ['gibibit', 'Gibibits', '1073741824x/8', '8x/1073741824', 'gibibit,gibibits,Gib'],
    ['gibibyte', 'Gibibytes', '1073741824x', 'x/1073741824', 'gibibyte,gibibytes,GiB'],
    ['terabit', 'Terabits', '1000000000000x/8', '8x/1000000000000', 'terabit,terabits,Tb'],
    ['terabyte', 'Terabytes', '1000000000000x', 'x/1000000000000', 'terabyte,terabytes,TB'],
    ['tebibit', 'Tebibits', '1099511627776x/8', '8x/1099511627776', 'tebibit,tebibits,Tib'],
    ['tebibyte', 'Tebibytes', '1099511627776x', 'x/1099511627776', 'tebibyte,tebibytes,TiB'],
    ['petabit', 'Petabits', '1000000000000000x/8', '8x/1000000000000000', 'petabit,petabits,Pb'],
    ['petabyte', 'Petabytes', '1000000000000000x', 'x/1000000000000000', 'petabyte,petabytes,PB'],
    ['pebibit', 'Pebibits', '1125899906842624x/8', '8x/1125899906842624', 'pebibit,pebibits,Pib'],
    ['pebibyte', 'Pebibytes', '1125899906842624x', 'x/1125899906842624', 'pebibyte,pebibytes,PiB'],
    ['exabit', 'Exabits', '1000000000000000000x/8', '8x/1000000000000000000', 'exabit,exabits,Eb'],
    [
      'exabyte',
      'Exabytes',
      '1000000000000000000x',
      'x/1000000000000000000',
      'exabyte,exabytes,EB',
    ],
    [
      'exbibit',
      'Exbibits',
      '1152921504606846976x/8',
      '8x/1152921504606846976',
      'exbibit,exbibits,Eib',
    ],
    [
      'exbibyte',
      'Exbibytes',
      '1152921504606846976x',
      'x/1152921504606846976',
      'exbibyte,exbibytes,EiB',
    ],
    [
      'zettabit',
      'Zettabits',
      '1000000000000000000000x/8',
      '8x/1000000000000000000000',
      'zettabit,zettabits,Zb',
    ],
    [
      'zettabyte',
      'Zettabytes',
      '1000000000000000000000x',
      'x/1000000000000000000000',
      'zettabyte,zettabytes,ZB',
    ],
    [
      'zebibit',
      'Zebibits',
      '1180591620717411303424x/8',
      '8x/1180591620717411303424',
      'zebibit,zebibits,Zib',
    ],
    [
      'zebibyte',
      'Zebibytes',
      '1180591620717411303424x',
      'x/1180591620717411303424',
      'zebibyte,zebibytes,ZiB',
    ],
    [
      'yottabit',
      'Yottabits',
      '1000000000000000000000000x/8',
      '8x/1000000000000000000000000',
      'yottabit,yottabits,Yb',
    ],
    [
      'yottabyte',
      'Yottabytes',
      '1000000000000000000000000x',
      'x/1000000000000000000000000',
      'yottabyte,yottabytes,YB',
    ],
    [
      'yobibit',
      'Yobibits',
      '1208925819614629174706176x/8',
      '8x/1208925819614629174706176',
      'yobibit,yobibits,Yib',
    ],
    [
      'yobibyte',
      'Yobibytes',
      '1208925819614629174706176x',
      'x/1208925819614629174706176',
      'yobibyte,yobibytes,YiB',
    ],
  ].freeze

  FREQUENCY_UNITS = [
    ['hertz', 'Hertz', 'x', 'x', 'hertz,Hz'],
    ['kilohertz', 'Kilohertz', '1000x', 'x/1000', 'kilohertz,kHz'],
    ['megahertz', 'Megahertz', '1000000x', 'x/1000000', 'megahertz,MHz'],
    ['gigahertz', 'Gigahertz', '1000000000x', 'x/1000000000', 'gigahertz,GHz'],
    ['terahertz', 'Terahertz', '1000000000000x', 'x/1000000000000', 'terahertz,THz'],
  ].freeze

  ENERGY_UNITS = [
    ['joule', 'Joules', 'x', 'x', 'Joule,J,joule,joules'],
    ['kilojoule', 'Kilojoules', '1000x', 'x/1000', 'KJ,kilojoules,kilojoule'],
    ['megajoule', 'Megajoules', '1000000x', 'x/1000000', 'MJ,megajoules,megajoule'],
    [
      'kilowatthour',
      'Kilowatt-Hours',
      '3600000x',
      'x/3600000',
      'kwh,kWh,kilowatt-hour,kilowatthour',
    ],
    ['btu', 'British Thermal Units', 'x*1054.350264489', 'x/1054.350264489', 'btu,BTU'],
    ['calorie', 'Calories', 'x*4.184', 'x/4.184', 'calories,calorie,cal'],
    ['kilocalorie', 'Kilocalories', 'x*4184', 'x/4184', 'kilocalories,kilocalorie,kcal'],
    ['erg', 'Ergs', 'x/10000000', 'x*10000000', 'ergs,erg'],
    [
      'ev',
      'Electron Volts',
      'x*1.602176634/10000000000000000000',
      'x/1.602176634*10000000000000000000',
      'electronvolt,electronvolts,ev',
    ],
    [
      'ftlb',
      'Foot-Pounds',
      'x*1.3558179483314004',
      'x/1.3558179483314004',
      'foot-pound,foot-pounds,ft-lb,ft-lbs',
    ],
  ].freeze

  PRESSURE_UNITS = [
    ['pascal', 'Pascals', 'x', 'x', 'Pascal,pascal,Pa'],
    ['kilopascal', 'Kilopascals', '1000x', 'x/1000', 'Kilopascal,kilopascal,kPa'],
    ['hectopascal', 'Hectopascals', '100x', 'x/100', 'Hectopascal,hectopascal,hPa'],
    ['bar', 'Bars', '100000x', 'x/100000', 'Bar,bar'],
    [
      'atm',
      'Standard Atmospheres',
      '101325x',
      'x/101325',
      'Standard Atmosphere,Standard atmosphere,standard atmosphere,Atm,atm',
    ],
    [
      'mmhg',
      'Millimeters of Mercury',
      '133.322387415x',
      'x/133.322387415',
      'Millimeter of Mercury,millimeter of mercury,mmHg',
    ],
    [
      'inhg',
      'Inches of Mercury',
      '3386.38x',
      'x/3386.38',
      'Inch of Mercury,inch of mercury,inHg',
    ],
    [
      'psi',
      'Pounds per Square Inch',
      '6894.759x',
      'x/6894.759',
      'Pound per Square Inch,pound per square inch,psi',
    ],
  ].freeze

  NUMBER_BASE_UNITS = [
    ['2', 'Binary', 'x', 'x', ''],
    ['8', 'Octal', 'x', 'x', ''],
    ['10', 'Decimal', 'x', 'x', ''],
    ['16', 'Hexadecimal', 'x', 'x', ''],
  ].freeze

  # Every category, in upstream's order: name, display name, units.
  UNITS = [
    ['angle', 'Angle', ANGLE_UNITS],
    ['length', 'Length', LENGTH_UNITS],
    ['area', 'Area', AREA_UNITS],
    ['volume', 'Volume', VOLUME_UNITS],
    ['weight', 'Mass', WEIGHT_UNITS],
    ['speed', 'Speed', SPEED_UNITS],
    ['duration', 'Duration', DURATION_UNITS],
    ['frequency', 'Frequency', FREQUENCY_UNITS],
    ['temperature', 'Temperature', TEMPERATURE_UNITS],
    ['energy', 'Energy', ENERGY_UNITS],
    ['pressure', 'Pressure', PRESSURE_UNITS],
    ['digitalstorage', 'Digital Storage', DIGITAL_STORAGE_UNITS],
  ].freeze

  def initialize
    @categories = []
  end

  def add_category(name, display_name)
    UnitCategory.new(name, display_name).tap { |category| @categories << category }
  end

  # The currency and number-base categories upstream adds after the fixed
  # table: the currencies come from the CurrencyManager, sorted by name, and a
  # currency has no conversion expression because its rate is its conversion.
  def add_currency_category
    currency_category = add_category('currency', 'Currency')
    currencies = CurrencyManager.default.currencies.sort_by(&:display_name)
    currencies.each do |currency|
      currency_category.add_unit(
        Unit.new(
          currency.name,
          currency.display_name,
          nil,
          nil,
          currency.name,
        ),
      )
    end

    numberbase_category = add_category('numberbase', 'Number Base')
    NUMBER_BASE_UNITS.each { |unit| numberbase_category.add_unit(Unit.new(*unit)) }
  end

  def categories = @categories.dup

  def category(name) = @categories.find { |c| c.name == name }

  # The category a unit belongs to, or nil when the name is ambiguous.
  def category_of_unit(name)
    sole_match(@categories.select { |c| c.unit_by_name(name) }) do
      @categories.select { |c| c.unit_by_name(name, false) }
    end
  end

  def unit_by_name(name)
    sole_match(@categories.filter_map { |c| c.unit_by_name(name) }) do
      @categories.filter_map { |c| c.unit_by_name(name, false) }
    end
  end

  def unit_by_symbol(symbol)
    sole_match(@categories.filter_map { |c| c.unit_by_symbol(symbol) }) do
      @categories.filter_map { |c| c.unit_by_symbol(symbol, false) }
    end
  end

  def defined_unit(name) = unit_by_symbol(name)

  # Converts `x` from one unit symbol to another, in the first category that
  # knows both. Answers [value, from unit, to unit], so a caller can say which
  # half it failed on.
  def convert_by_symbol(x, x_symbol, z_symbol)
    answer = nil
    x_unit = nil
    z_unit = nil
    @categories.each do |category|
      if answer.nil?
        from_unit = category.unit_by_symbol(x_symbol) || category.unit_by_symbol(x_symbol, false)
        to_unit = category.unit_by_symbol(z_symbol) || category.unit_by_symbol(z_symbol, false)
        x_unit = from_unit
        z_unit = to_unit
        if from_unit && to_unit
          answer = category.convert(x, from_unit, to_unit)
        end
      end
    end
    [answer, x_unit, z_unit]
  end

  private

    # A name is only resolved when exactly one unit answers to it; a tie is
    # treated as unknown, and no match at all falls back to the block.
    def sole_match(matches)
      if matches.length == 1
        matches.first
      elsif matches.empty?
        fallback = yield
        if fallback.length == 1
          fallback.first
        end
      end
    end
end
