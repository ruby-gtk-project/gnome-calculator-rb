# Component parity — gnome-calculator-rb

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `da4eed8c` |
| Units with parity | **1 / 23** |

Method: `component-parity` skill, four axes (count, style, behaviour, text)
per unit, using the unit list from `.reports/component-identification.md`.

## Unit-by-unit

### Unit 1 — Application: `src/gnome-calculator.vala` → `lib/gnome_calculator/application.rb`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Actions (`app.new-window`, `app.help`, `app.about`, `app.quit`) | 4 | 0 | **gap** |
| Accelerators (18 bindings) | 18 | 0 | **gap** |
| `Adw.AboutDialog` | present, 5 developers + translator credits + provider legal section | not built | **gap** |
| `Adw.AlertDialog` "Close All?" | present | not built | **gap** |
| CLI options (`--mode`, `--solve`, `--equation`, `--version`) | present | not built (the engine CLI, `exe/gcalccmd`, is separate and is the one thing ported) | **gap** |
| `GtkSource.init`, settings delay, currency refresh on startup | present | not built | **gap** |
| Window construction (an `Adwaita::ApplicationWindow`, one toplevel, titled) | `MathWindow` | a bare window present and buildable | **partial** — this is the one row with any parity: the port's window is a real `Adwaita::ApplicationWindow` and is the only toplevel, same as upstream, verified by `test/drive_gnome_calculator.rb` |

Verdict: **gap**, with one surviving row (window construction mechanics).

### Units 2–19, 21, 23 — main window, shortcuts dialog, display, completion, history view/entry, six button panels + bit panel + financial/preferences dialogs, converter, stylesheet, shell search provider, translations

Every one of these upstream units builds zero counterpart in the port. There
is no `lib/math_window.rb`, `lib/math_display.rb`, `lib/history_view.rb`,
`lib/math_buttons*.rb`, `lib/math_converter.rb`, `lib/shortcuts_dialog.rb`,
`lib/completion_providers.rb`, `lib/shell_search_provider.rb`, or `locale/`.
`lib/style.css` exists as a file (copied in full, confirmed byte range —
399 lines, 44 classes) but is **not loaded by any built widget**: no
`Gtk::CssProvider.load_from_path` call anywhere outside
`application.rb`'s own provider for `style.css`, and that provider's rules
have nothing to attach to because no widget the stylesheet targets is ever
built.

For each of these units, all four axes fail identically:

| Axis | Status |
|---|---|
| Count | 0 vs upstream's (see `component-inventory.md` per-unit tables, ~148 buttons, 44 shortcut items, 4 menus, etc.) |
| Style | n/a — no widget exists to carry a class |
| Behaviour | n/a — no signal/action exists to fire |
| Text | n/a — see `translation-parity.md`: 0 of 831 in-scope upstream messages are marked anywhere in the port |

Verdict: **gap**, 21 of 23 units.

### Unit 20 — Settings: `data/org.gnome.calculator.gschema.xml` → `lib/settings.rb`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Key count | 19 | 19 | parity |
| Defaults/ranges | per schema | matches (read `lib/settings.rb`) | parity |
| Mechanism | `Gio::Settings` / GSettings, `Settings.delay()` batching | JSON file under `XDG_CONFIG_HOME` | **correspondence** — a real mechanism substitution, not a gap, because the 19 keys and their defaults are reproduced and round-trip (verified live: `test/drive_gnome_calculator.rb` step "Settings reads and writes the same 19 JSON-backed keys") |
| `Gio::Settings.bind()` to any widget | 7+ bindings (equation properties, preferences rows, `favorite-currencies`, window geometry, history tape) | **none** — there is nothing on the port side to bind to | **gap**, scoped to "no widget consumes these settings yet", not to the key storage itself |

Verdict: the storage layer has parity; the bindings it exists to serve do
not, because their targets (units 2–19) are not built. Counted as the one
unit with partial parity, same caveat as unit 1.

### Unit 22 — CLI: `src/gcalccmd.vala` → `exe/gcalccmd`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Single-expression argv mode | yes | yes (verified live: `2^10` → `1024`, clean exit, empty stderr) | parity |
| REPL on stdin until blank line | yes | yes (verified live: `3 + 4\n\n` → `7`, clean exit) | parity |
| Error on unknown variable → stderr, not an exception | yes | yes (verified live) | parity |
| Man page (`data/gcalccmd.1`) | present | not carried over | **gap** (small, stated plainly rather than silently) |

Verdict: **parity** for the functional CLI, one small documentation gap.

## Totals

| | Count |
|---|---:|
| Units with full parity | 1 (`exe/gcalccmd`, modulo the man page) |
| Units with partial/mechanism-only parity | 2 (Application's window shell; Settings storage) |
| Units with zero parity (nothing built) | 20 |

## Stylesheet check (Step 4)

`lib/style.css` vs upstream `src/ui/style.css`: byte-for-byte diff shows the
file was copied in full (same 399 lines, same 44 classes, same dark-mode and
high-contrast blocks). This is **not** evidence of style parity per the
skill's own rule — a copied stylesheet with nothing to attach the classes to
is a dormant file. Confirmed dormant: `grep -rn 'add_css_class\|css_classes'
lib/ exe/` returns nothing. 0 of 44 classes are attached to any widget.

## Behaviour check (Step 5)

Only one unit has any live signal/action to drive: the application's
`activate` handler, exercised by `test/drive_gnome_calculator.rb` and
confirmed to build the real window, toolbar view, header bar and status
page, and to load the CSS provider without raising. No other signal,
accelerator or action exists anywhere in the port to drive.

## Rules check

- No parity is reported from the scan/inventory alone; the two running
  checks above (CLI subprocess calls, the drive script) are what Steps 4–5
  require, and both were re-run live for this report (see
  `accountability-ensurance.md` for the exact command and output).
- No app-wide total is used as the pass condition; every row above is a
  named unit.
- Nothing is marked "extra" — the port builds strictly less than upstream,
  not differently.
