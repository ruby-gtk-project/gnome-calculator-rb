# Translation parity — gnome-calculator-rb

Fourth pass, at `da40269a`. This pass corrects a false claim in the third
pass's own report (see "Correction" below) in addition to re-running the
census against the popovers built since then.

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `da40269a` |
| Upstream messages (source, in scope) | **797** distinct `(msgctxt, msgid)` keys (unchanged census; see below) |
| Port messages | **47** distinct keys (up from 33 — `math_function_popover.rb`/`math_variable_popover.rb`'s validation strings and `math_popover.rb`'s shared chrome add markers) |
| Ported (present in both) | **~20** (not recounted exactly against the full 797-row upstream set this pass; the new popover validation strings match upstream's `src/math-function-popover.vala`/`math-variable-popover.vala` text byte-for-byte, same no-`msgctxt` caveat as the shortcuts dialog below) |
| Gaps (upstream key with no port match) | **≥ 777** |
| Port languages | **0** |
| Parity | **false** |

## Correction to the third pass's own report

The third pass's "Languages" section claimed: "Checked: `grep -rn
'bindtextdomain\|GetText.bindtextdomain\|textdomain' lib/ exe/` → no
output." **That is false, and was already false when it was written** —
`lib/translations.rb:20` has called `bindtextdomain(DOMAIN, path:
LOCALE_DIR)` since commit `e0ed3935`, which landed before the third pass
(`9824569e`) was written. Re-run verbatim this pass:

```
$ grep -rn "bindtextdomain\|GetText.bindtextdomain\|textdomain" lib/ exe/
lib/translations.rb:20:  bindtextdomain(DOMAIN, path: LOCALE_DIR)
```

This is exactly the kind of claim `accountability-ensurance.md` exists to
catch — a report asserting a command's output without the output actually
being what was asserted — except here the error runs in the direction of
*overstating* the gap rather than hiding one, since the binding call does
exist. It is flagged in `accountability-ensurance.md` as well, because an
inaccurate command transcript is a documentation-integrity problem
independent of which direction it errs in: the next reader who trusts it
and doesn't re-run the grep carries the wrong fact forward either way.
The substantive point the third pass used it to support — that the
`bindtextdomain` call is not confirmed to actually bind against real,
loadable `.mo` catalogues at runtime — stands; only the specific "no
output" transcript was wrong.

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
| `.po` files | 101 | 101, byte-identical to upstream (confirmed: `diff <(git show origin/main:po/POTFILES.in) po/POTFILES.in` and a full `git diff --stat origin/main -- po/` both empty) — **not wired in**: carried over as files only |
| `.mo` built/installed | yes | no — no build step compiles any `.po` to `.mo`, and `bindtextdomain` points at `po/` (raw `.po` sources), not an installed `.mo` locale tree |

`lib/translations.rb`'s `Gettext` module does call
`bindtextdomain(DOMAIN, path: LOCALE_DIR)` (see the correction above), but
this still was not confirmed this pass to produce a translated string for
any non-English locale end to end — no `.mo` exists for `bindtextdomain` to
find regardless of the call being present, so the net effect for every one
of the 101 languages is the same as if the call were absent: English only.
Flagged, not claimed clean.

## New this pass: the two popovers' validation strings

`lib/math_popover.rb`, `lib/math_function_popover.rb` and
`lib/math_variable_popover.rb` all `include Gettext` and wrap their
placeholder text and the 8 validation messages (4 per popover) in `_()`,
matching upstream's text byte-for-byte where compared
(`src/math-function-popover.vala`/`src/math-variable-popover.vala`). Same
caveat as every other string in this port: no `msgctxt`, and these two
files were not in upstream's `po/POTFILES.in` under their Ruby names (they
can't be — that file still lists `.vala`/`.blp` paths, see below), so
nothing currently extracts these new markers into any catalogue.

## Conclusion

Translation parity is **roughly 20/797 at best, 0/101 languages**, up
slightly from the third pass's 17/797 because the two new popovers add
validation strings that happen to match upstream's text — not because any
systematic translation work has happened across four passes now. Four
independent problems compound rather than one gap shrinking: (1) the UI
that does exist covers at most 38 of 43 shortcut-dialog strings, 8
popover-validation strings, and a double-digit handful of button/error
strings, with no `msgctxt` anywhere, so even a perfect `po/` wire-up would
under-translate; (2) the engine files the port's own documents call
"complete" mark zero of their currency/unit/financial display names for
translation; (3) `po/POTFILES.in` cannot be run from this branch's own
source tree, so there is no mechanical way to regenerate a `.pot`; (4) even
where `bindtextdomain` is correctly called (corrected finding, this pass),
no `.mo` catalogue exists for it to find, so the call changes nothing
observable yet. None of these four has been fixed across four audit
passes — only found, and in the third pass's case, half-misreported.
