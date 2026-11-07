# frozen_string_literal: true

require 'gettext'

# Translations wires the app into gettext: it binds the
# "gnome-calculator" domain to the po/ directory this repo carries over
# unchanged from upstream, and gives every other file `_()` and `n_()`
# with upstream's byte-identical msgids.
#
# Ported from upstream's use of gettext() / ngettext() throughout the Vala
# sources (there is no single translations.vala — every file calls the C
# library directly); this module is the one place that mechanism needed in
# Ruby, via the `gettext` gem's GetText module.
module Translations
  extend GetText

  DOMAIN = 'gnome-calculator'
  LOCALE_DIR = File.join(__dir__, '..', 'po')

  bindtextdomain(DOMAIN, path: LOCALE_DIR)

  # Mirrors upstream's _() macro (gettext()).
  def self._(msgid) = gettext(msgid)

  # Mirrors upstream's ngettext(), for plural msgids.
  def self.n_(msgid, msgid_plural, n) = ngettext(msgid, msgid_plural, n)
end

# Every file that marks strings includes this to get `_` and `n_` as plain
# method calls, the same shape as upstream's C macros.
module Gettext
  def _(msgid) = Translations._(msgid)

  def n_(msgid, msgid_plural, n) = Translations.n_(msgid, msgid_plural, n)
end
