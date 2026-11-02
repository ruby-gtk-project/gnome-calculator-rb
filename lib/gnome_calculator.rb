# frozen_string_literal: true

# The engine, in dependency order: the number tower first, then the parser it
# feeds, then the models the window and the converter read.
require_relative "number"
require_relative "serializer"
require_relative "evaluation_budget"
require_relative "equation_lexer"
require_relative "equation_parser"
require_relative "equation"
require_relative "math_function"
require_relative "function_manager"
require_relative "math_variables"
require_relative "currency_provider"
require_relative "currency"
require_relative "unit"
require_relative "financial"
require_relative "settings"

# The GUI is NOT required here: upstream splits lib/ from src/ so that
# gcalccmd and the search provider link the engine without pulling in GTK, and
# exe/gnome-calculator requires gnome_calculator/application itself.
