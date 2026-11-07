# Translation parity — gnome-calculator-rb

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `da4eed8c` |
| Upstream messages (source, in scope) | **831** distinct `(msgctxt, msgid)` keys |
| Upstream occurrences (call sites, in scope) | **1074** |
| Upstream languages | **101** `.po` files (`po/LINGUAS` matches, 101 = 101) |
| Port messages | **0** |
| Port languages | **0** |
| Ported | **0** |
| Gaps | **831** |
| Parity | **false** |

Method: `translation-parity` skill, `scripts/msgid-census.sh` run against a
disposable worktree of `origin/main` and against the `ruby` branch's working
tree.

## Census (Step 1)

```sh
git worktree add --detach /tmp/upstream-gcalc origin/main
bash .claude/skills/translation-parity/scripts/msgid-census.sh /tmp/upstream-gcalc > upstream-msgids.tsv
bash .claude/skills/translation-parity/scripts/msgid-census.sh .                  > port-msgids.tsv
```

Raw rows: **75,869** on the upstream side (because the scanner also reads
every `.po`/help catalogue it finds) and **0** on the port side — the scan
found no `_()`, `N_()`, `gettext`, `ngettext` or any other marker anywhere
under `lib/` or `exe/`, confirmed independently:

```sh
grep -rn "gettext\|_(\|n_(\|translations" lib/ exe/   # => no output
```

Filtering the upstream rows to source (excluding `po/*.po` and `help/*.page`
translation catalogues, which are scanned for the `languages:` count, not
the message count) gives the per-directory breakdown:

| Directory | Call sites |
|---|---:|
| `lib/` (the engine files, e.g. error strings) | 517 |
| `src/` (the UI — where almost all user-visible text lives) | 423 |
| `data/` (`.desktop.in`, GSettings schema summaries) | 57 |
| `search-provider/` | 3 |
| `gcalc/`, `tests/` (out of scope, per `component-inventory.md` item 10) | 74 |

In-scope total: **1074 call sites, 831 distinct keys**, 0 unresolved
(no dynamic `_(expr)` call sites that the scanner had to flag — every marker
upstream uses is a literal).

Languages: `ls po/*.po | wc -l` = 101, `po/LINGUAS` = 101 lines, and they
match (no `diff`). `help/` ships the user manual in a further 34 languages,
not counted in the 101 above and also not carried by the port.

## The diff

```
comm -23 <(upstream keys) <(port keys) | wc -l   # => 831  (every upstream key)
comm -13 <(upstream keys) <(port keys) | wc -l   # => 0    (port has no extra keys)
comm -12 <(upstream keys) <(port keys) | wc -l   # => 0    (nothing ported)
```

Every one of upstream's 831 messages is a **gap**. There is nothing to
report as "extra" (the port invents no new strings either, because it
builds no UI to put them in) and nothing is reworded or retyped, because
nothing is marked at all — the simplest and most total form of this gap.

## Representative messages owed (by call-site count, i.e. porting priority)

These are drawn directly from `src/*.vala`/`*.blp` (the highest-value,
highest-reuse strings a UI port would need first):

| Message | Uses | Where |
|---|---:|---|
| `"Basic"`, `"Advanced"`, `"Financial"`, `"Programming"`, `"Keyboard"`, `"Conversion"` | mode labels, each reused across the menu button label and the shortcuts dialog | `src/math-window.vala`, `src/ui/math-shortcuts.blp` |
| `"Undo"`, `"Redo"`, `"Copy"`, `"Paste"`, `"Clear"` | menu/shortcut text | `src/ui/math-shortcuts.blp`, `src/ui/math-window.blp` |
| the ~148 button labels/tooltips across the five mode panels | `src/ui/*-buttons.blp` |
| `"No Results Found"`, `"Try a different search"` | the currency-favourites empty state | `src/ui/preferences.blp` |
| the ten financial-function names and descriptions | `src/financial.vala` |

None of these have any Ruby counterpart to compare bytes against, because
none of these labels are built by the port at all (see
`component-parity.md`, units 2–19).

## Languages

| | Upstream | Port |
|---|---:|---:|
| `.po` files | 101 | 0 |
| `LINGUAS` entries | 101 | — |
| `.mo` built/installed | yes (via meson `i18n.gettext`) | no |
| Translated strings (aggregate across all `.po`, not computed exactly here — out of scope for this pass beyond the key-set diff, since the key set is already 0) | thousands | 0 |

**0 of 101 languages are shipped.** The port is English-only, and because it
marks no strings at all, it is not merely missing translations — it has no
mechanism (no `require "gettext"`, no `.mo` loading, no domain) to ever
consume them even once the UI exists.

## Conclusion

Translation parity is **0/831, 0/101 languages**. This is not a case of
reworded or retyped strings losing their translations one at a time — the
port has not yet reached the point where that failure mode would even be
visible, because it has built no UI for any string to live in. The 831-key,
101-language gap is accurate today and will grow message-by-message as
`component-parity.md`'s 20 missing units are built; closing it is
transcription (copy upstream's msgids byte-for-byte, mark with `_()`/`n_()`
via the `gettext` gem, carry `po/` and `po/LINGUAS` over unchanged) and
should happen in the same commit as each widget, not as a follow-up.
