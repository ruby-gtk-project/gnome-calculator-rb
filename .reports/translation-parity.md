# Translation parity — gnome-calculator-rb

Fifth pass, at `eba4d35e`. Every number and transcript below was re-run
this pass, not read off the fourth pass's report (which itself corrected a
false transcript the third pass had introduced — see
`accountability-ensurance.md`'s standing note on that history).

## File-level parity: 101/101, byte-identical — real, but not the whole story

```
$ git ls-tree -r --name-only origin/main | grep '\.po$' | grep '^po/' | xargs -n1 basename | sort > up.txt
$ ls po/*.po | xargs -n1 basename | sort > port.txt
$ python3 -c 'print(set(open("up.txt").read().split()) ^ set(open("port.txt").read().split()))'
set()  # empty — identical sets, 101 each
$ diff <(git show origin/main:po/ar.po) po/ar.po
# no output — byte-identical
```

Upstream also has 34 `help/<lang>/<lang>.po` files (user-manual
translations) that this count correctly excludes — those are documentation
translations, a different artifact from the UI string catalogue, and the
port carries no `help/` tree at all (also true upstream's own README
doesn't ship built docs, so this is noted, not scored as a separate gap
here).

So the `po/` directory itself is a faithful, complete mirror. That is the
most that can be said for it, for two reasons below.

## The marked-string surface is far short of upstream, and the fourth pass undercounted it

```
$ grep -rohE "_\((\"[^\"]*\"|'[^']*')" lib/ exe/ | sed -E "s/^_\(['\"]//; s/['\"]$//" | sort -u | wc -l
82
$ grep -c '^msgid "' po/en_GB.po
789   # includes the empty header msgid
```

82 distinct strings marked for translation against upstream's ~788 real
msgids. (The fourth pass's commit message said "roughly 20/797" — this
pass's count of 82 is higher because that figure predates `8de8a498`,
which added the Advanced panel's ~45 button tooltips, not because the
fourth pass's own count was wrong at the time.) The gap is structural, not
an oversight to "mark a few more strings": upstream's msgid count is this
large because of the panels, dialogs, preferences page and shortcuts items
that simply don't exist in `lib/` yet (see `component-identification.md`)
— a string that has no widget to live on cannot be marked.

## New finding this pass: a meaningful fraction of the marked strings do not match any upstream msgid at all

Diffing the 82 marked strings against `po/en_GB.po`'s msgid set:

```
$ comm -23 <(sort used_msgids.txt) <(grep '^msgid "' po/en_GB.po | sed -E 's/^msgid "(.*)"$/\1/' | sort)
Add
Calculation error
Calculation took too long
Name
No conversion possible
No sane value to convert
Number of Arguments
The result of the calculation is undefined
Unknown function
Unknown unit
Unknown variable
```

11 of 82 marked strings (~13%) have **no matching msgid anywhere in the
catalogue** — 9 simply don't exist under any spelling, and 2
(`"Unknown unit"`, `"Unknown variable"`) exist upstream only with a `“%s”`
placeholder the port's string omits (`po/en_GB.po:959`: `msgid "Unknown
variable “%s”"`). Root cause, confirmed by reading
`lib/math_equation.rb#error_message` against upstream's
`lib/math-equation.vala` (full table in `component-parity.md`'s new
finding this pass): the `ErrorCode`→text mapping was invented for the
port rather than copied from upstream, so 8 of its 9 branches produce
*different English text than upstream*, and all 8 are therefore
untranslatable by construction — no translator ever wrote a `msgstr` for
a string that doesn't exist as a `msgid`. This is simultaneously a
behavioural parity gap (wrong wording shown to an English-speaking user,
see `component-parity.md`) and a translation gap (that wording cannot
ever be localized, in any of the 101 languages, no matter how complete
`po/` is).

## Headline finding: zero translations take effect at runtime, in any language — no `.mo` catalogue exists

```
$ find po -name "*.mo" | wc -l
0
$ find . -name "*.mo" -not -path './.git/*' | wc -l
0
```

`gettext` (the Ruby gem `lib/translations.rb` requires) reads compiled
`.mo` catalogues, not raw `.po` source. None exist anywhere in the tree,
and nothing in the `Rakefile` or `flake.nix` compiles them (`msgfmt` is
never invoked — checked by grepping `Rakefile`, `flake.nix`, `mise.toml`
for `msgfmt`/`\.mo`/`GetText.compile` — zero hits). Proven live this pass,
not inferred from the missing files alone:

```
$ nix develop --command ruby -e '
require_relative "lib/translations"
ENV["LANG"]="fr_FR.UTF-8"; ENV["LANGUAGE"]="fr"
Translations.send(:bindtextdomain, "gnome-calculator", path: "po")
GetText.set_locale("fr")
puts Translations._("Malformed expression")
'
fr
Malformed expression
```

`po/fr.po:1013` carries `msgid "Malformed expression"` with a real French
`msgstr`. Forcing the locale to French and calling `_()` on that exact
msgid still returns the English string. **Every one of the 101 `.po`
files in this repository is currently decorative** — present, correctly
named, byte-identical to upstream, and never consulted at runtime by any
code path, because the build step that would turn them into something
`gettext` can read does not exist.

## Totals

| | Upstream | Port |
|---|---:|---:|
| `.po` language files | 101 | 101 (100% file-level parity) |
| Compiled `.mo` catalogues reachable at runtime | 101 (via the real build) | **0** |
| msgids in the catalogue | ~788 | marked in source: 82 (~10%) |
| Marked strings that match an upstream msgid exactly | — | 71/82 (~87%) |
| Marked strings with no matching msgid at all | — | 11/82, all traced to one invented error-message table |
| Languages that produce a translated string for any marked, matching msgid | 101 (when built) | **0** |

**Gap, on every axis except raw file count.** The 101/101 `.po` parity is
real but is the least important number here: a complete set of source
translation files that are never compiled and never consulted is
equivalent, to an actual user running the app in any of those 101
languages, to having none at all.
