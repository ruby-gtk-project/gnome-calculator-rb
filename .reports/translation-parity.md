# Translation parity — gnome-calculator-rb

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `9824569e` |
| Upstream messages (source, in scope) | **797** distinct `(msgctxt, msgid)` keys (recounted this pass over `lib/`, `src/`, `data/`, `search-provider/`) |
| Port messages | **33** distinct keys |
| Ported (present in both) | **17** |
| Gaps (upstream key with no port match) | **780** |
| Port languages | **0** |
| Parity | **false** |

Method: `translation-parity` skill,
`.claude/skills/translation-parity/scripts/msgid-census.sh` run against a
disposable archive of `origin/main` and against the `ruby` branch's `lib/`
and `exe/`. This pass differs from the prior one: the prior report found
**zero** markers on the port side at all ("the scan found no `_()`, `N_()`,
gettext or any other marker anywhere under lib/ or exe/"). That is no
longer true — `lib/translations.rb` and the UI files built since then
(`math_window.rb`, `basic_button_panel.rb`, `math_shortcuts.rb`, etc.) do
call `_()`. The gap is still almost total, but for a different reason now:
coverage, not absence of mechanism.

## Census

```
bash .claude/skills/translation-parity/scripts/msgid-census.sh \
  <upstream-archive>/lib <upstream-archive>/src <upstream-archive>/data <upstream-archive>/search-provider
  -> 1000 rows (script's own output cap hit; see caveat below)

bash .claude/skills/translation-parity/scripts/msgid-census.sh lib exe
  -> 34 rows, 33 unique (msgctxt, msgid) keys
```

797 unique upstream keys (after dedup) vs 33 unique port keys. **Caveat**:
the upstream-side row count hit the census script's practical row ceiling
at exactly 1000 lines in this run, so 797 is a lower bound on upstream's
true key count, not an exact figure — the true gap is at least as large as
reported here, never smaller.

```
comm -23 <(upstream keys) <(port keys) | wc -l   # => 780  (upstream keys missing from the port)
comm -12 <(upstream keys) <(port keys) | wc -l   # => 17   (keys present on both sides, by text)
```

## What the 17 overlapping keys actually are

Cross-checking the overlap against where each side's text lives: the 17
matches are UI strings from the one vertical slice that is built (basic
button labels/tooltips, "Keyboard Shortcuts", a handful of error strings
like "Malformed expression", "Unknown variable"). None of them carry
`msgctxt`; see the shortcuts-dialog finding below for why that still
produces a miss at the catalogue level even for text that matches
byte-for-byte.

## New finding this pass: the engine itself marks nothing

```
grep -n "_(" lib/currency.rb lib/unit.rb lib/financial.rb lib/number.rb
  -> no output, any of the four files
```

`lib/currency.rb`, `lib/unit.rb`, `lib/financial.rb` and `lib/number.rb`
have **zero** gettext calls. Upstream's `lib/currency.vala`,
`lib/unit.vala` and `lib/financial.vala` are explicitly in `po/POTFILES.in`
and carry the translated display names for every currency ("Algerian
Dinar", "Argentine Peso", …, dozens more), every unit category ("Acres",
"Astronomical Units", "Atomic Mass Unit", …), and the ten financial
function names/descriptions. `component-inventory.md` calls the engine
"20 of 20 in scope — complete," and functionally that is accurate (the
numbers compute correctly), but **none of these user-visible names are
translatable in the port**, independent of and in addition to the UI gap —
this is a gap inside a component this port's own documents call done, not
inside one already flagged as missing.

## New finding this pass: `po/POTFILES.in` cannot be regenerated from this branch

`po/POTFILES.in` on `ruby` is byte-identical to `origin/main`'s (confirmed
by diff): it still lists `src/*.vala`, `src/ui/*.blp`,
`lib/*-provider.vala`, etc. — files that **do not exist on the `ruby`
branch at all** (this branch is an orphan branch holding only the Ruby
port; CLAUDE.md states this plainly). Running `xgettext -f po/POTFILES.in`
(or `ninja gnome-calculator-pot`, upstream's actual command) from this
checkout would fail to find every listed file and would not scan a single
`.rb` file, because none is listed. The `.pot`/`.po` pipeline is not merely
behind — it points at a source tree this branch does not contain, so it
cannot be used to extract or verify port strings at all until `POTFILES.in`
is rewritten to list the `.rb` files that now carry the markers.

## The shortcuts-dialog `msgctxt` gap (detail)

`lib/math_shortcuts.rb`'s `SECTIONS` constant calls `_(title)`/`_(label)`
with no context. Upstream's `src/ui/math-shortcuts.blp` wraps every row in
`C_("shortcuts dialog", "…")`. gettext's lookup key is `(msgctxt, msgid)`,
confirmed in `po/de.po` et al. (`msgctxt "shortcuts dialog"` entries exist
for these exact strings). A plain `_("Copy")` looks up the bare-context
entry, which may not exist or may carry a different translation than the
context-scoped one — so even the 38 shortcut rows the port does build
(see `component-parity.md`) will not reliably pick up the upstream
translation for any of the 101 languages, even once `po/POTFILES.in` is
fixed and the catalogues are wired in.

## Languages

| | Upstream | Port |
|---|---:|---:|
| `.po` files | 101 | 0 wired in — `po/*.po` exist as files on disk (carried over unchanged) but nothing in `lib/`/`exe/` requires `gettext` against them or sets a text domain |
| `.mo` built/installed | yes | no |

Checked: `grep -rn "bindtextdomain\|GetText.bindtextdomain\|textdomain" lib/
exe/` → no output. `lib/translations.rb`'s `Gettext` module is confirmed to
define `_`/`n_` but not confirmed to bind them to `po/`'s actual catalogues
at runtime — read directly, it is a thin wrapper and the binding step was
out of scope to re-verify fully this pass; flagged, not claimed clean.

## Conclusion

Translation parity is **17/797 at best, 0/101 languages**, up from 0/831 in
the prior pass only because a UI slice now exists to carry the matching
17 strings — not because any systematic translation work has happened.
Three independent problems compound rather than one gap shrinking: (1) the
UI that does exist covers at most 38 of 43 shortcut-dialog strings and a
double-digit handful of button/error strings, with no `msgctxt`, so even a
perfect `po/` wire-up would under-translate; (2) the engine files the
port's own documents call "complete" mark zero of their currency/unit/
financial display names for translation, which is a silent regression
against a component this port is not tracking as a translation gap at all;
(3) `po/POTFILES.in` cannot be run from this branch's own source tree, so
there is currently no mechanical way to regenerate a `.pot` and discover
*any* of the above without a manual audit like this one.
