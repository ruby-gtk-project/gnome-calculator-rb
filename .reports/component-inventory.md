# gnome-calculator component inventory

Surveyed against `origin/main` (upstream Vala/blueprint) vs. the `ruby`
branch's `lib/`. Scope is the whole app — this is the opening survey of a
fork that has only just started (one window, basic mode only), so the
totals are the point, not a thing to act on directly. Pick one unit at a
time from the list below.

Upstream totals (component-scan over `src/` + `lib/`): 588 rows across 25
files, headlined by `Gtk.Button` (≈60, across every button-panel file),
`Adw.*Row` types (~20), and 14 distinct GSettings keys. The `ruby` branch:
41 rows across 5 files, all of them either backend math (`lib/*.rb` ported
from upstream `lib/*.vala`, already complete) or the single basic-mode
window. Zero `add_action`/`install_action` calls exist anywhere in `lib/`
— every action upstream installs (`win.*`, `app.*`, `cal.*`) is missing.

## Legend

`exists` — a `lib/*.rb` file already implements this component (may be
partial; see notes). `missing` — no `lib/*.rb` file for it at all.

## 1. Application and window shell

| Upstream file | → `lib/*.rb` | Kind | Status | Notes |
|---|---|---|---|---|
| `src/gnome-calculator.vala` | `lib/gnome_calculator/application.rb` | `Adw.Application` subclass | **exists** (partial) | Installs no actions yet: upstream wires `app.new-window`, `app.quit`, `app.shortcuts`, `app.help`, `app.about` here (plus `--version`/`-e` CLI equation arg handling). None of that is in the port. |
| `src/math-window.vala` + `src/ui/math-window.blp` | `lib/math_window.rb` | `Adw.ApplicationWindow` (template `$MathWindow`) | **exists** (partial) | Builds `Adwaita::HeaderBar` + display + basic button panel only, by the file's own header comment. Upstream's window also owns: the `Gtk.Stack` of mode button-panels (basic/advanced/financial/programming/keyboard), the history view, the unit converter pane, and the `win.*` actions (`mode`, `undo`, `redo`, `back`, `clear`, `number-format`, `preferences`) plus header-bar buttons for shortcuts/help/about/preferences/new-window. None of the mode stack, converter, history, or `win.*` actions exist. Keyboard handling is hand-rolled in a `Gtk::EventControllerKey` rather than via GTK actions + accelerators, which is how upstream wires it (`win.undo`, `win.redo`, etc. with `set_accels_for_action`). |
| `src/ui/math-shortcuts.blp` | `lib/math_shortcuts.rb` (new) | standalone `$AdwShortcutsDialog`, no backing `.vala` | **missing** | Keyboard-shortcuts window reachable from `app.shortcuts`. No Ruby file at all. |

## 2. Mode button panels (the `Gtk.Stack` pages `math-buttons.vala` switches between)

| Upstream file | → `lib/*.rb` | Kind | Status | Notes |
|---|---|---|---|---|
| `src/math-buttons.vala` | `lib/math_buttons.rb` (new) | the stack controller: owns the `Gtk.Stack`, mode-switch logic, `win.mode` action, keyboard-mode announcement | **missing** | This is the piece that would let the existing basic panel coexist with the other four modes. Nothing in `lib/` plays this role; `MathWindow` just embeds `BasicButtonPanel` directly. |
| `src/buttons-basic.vala` + `src/ui/buttons-basic.blp` | `lib/basic_button_panel.rb` | `Adw.Bin` template, digit/operator buttons, `Gtk.MenuButton`×2 | **exists** | The one panel that's ported. |
| `src/buttons-advanced.vala` + `src/ui/buttons-advanced.blp` | `lib/advanced_button_panel.rb` (new) | `Adw.Bin` template | **missing** | Scientific-mode buttons (trig, log, powers, constants). |
| `src/buttons-financial.vala` + `src/ui/buttons-financial.blp` | `lib/financial_button_panel.rb` (new) | `Adw.Bin` template | **missing** | Financial-mode buttons; note `lib/financial.rb` (the finance *math*, ported from `lib/financial.vala`) already exists — this is only the missing button-panel UI that drives it. |
| `src/buttons-programming.vala` + `src/ui/buttons-programming.blp` | `lib/programming_button_panel.rb` (new) | `Adw.BreakpointBin`, `Adw.Carousel`, `Adw.ComboRow`, `Adw.Dialog`, `Adw.EntryRow`, `Gtk.Grid`×2, `Gtk.Button`×10, `Gtk.MenuButton`×4 | **missing** | Programming-mode buttons plus the bit-field editor dialog. Installs `cal.insert-digit` and `cal.toggle-bit` actions (both currently un-ported anywhere). |
| (no keyboard-mode panel file upstream — `math-buttons.vala` builds it from a loop over function definitions) | part of `lib/math_buttons.rb` | repeater: N buttons from `FunctionManager`'s function list | **missing** | Call-site/loop component per the skill's under-report rule — not a separate upstream file, but a distinct set of runtime-built buttons `math_buttons.rb` must reproduce. |

## 3. Popovers, converter, history, preferences

| Upstream file | → `lib/*.rb` | Kind | Status | Notes |
|---|---|---|---|---|
| `src/math-popover.vala` | `lib/math_popover.rb` (new) | base class, no `.blp` (shared popover behaviour: auto-close on activate, etc.) | **missing** | Parent class for the three popovers below. |
| `src/math-function-popover.vala` + `src/ui/math-function-popover.blp` | `lib/math_function_popover.rb` (new) | `Gtk.Popover` subclass template, search entry, list | **missing** | Function-insertion popover (the `fx` button in basic/advanced). |
| `src/math-variable-popover.vala` + `src/ui/math-variable-popover.blp` | `lib/math_variable_popover.rb` (new) | `Gtk.Popover` subclass template | **missing** | Variable-insertion/management popover. `lib/math_variables.rb` (ported from `lib/math-variables.vala`) is the backing model and already exists; this is only the missing popover UI. |
| `src/math-converter.vala` + `src/ui/math-converter.blp` | `lib/math_converter.rb` (new) | `Adw.Bin` template: unit-category combo, source/target unit rows, swap button | **missing** | Unit/currency conversion pane. `lib/unit.rb` and `lib/currency.rb`/`lib/currency_provider.rb` (the math/data side) already exist and are ported; this is only the missing converter UI that drives them. |
| `src/math-history.vala` + `src/ui/history-view.blp` + `src/ui/history-entry.blp` | `lib/math_history.rb` (new) | `Gtk.ListBox`/view template (`history-view.blp`) populated with entry rows (`history-entry.blp`) | **missing** | Equation history list. `Settings#history-tape` (in `lib/settings.rb`) already stores the backing data; no UI reads or writes it yet. Two upstream `.blp` files map to this one port file per the "one upstream file set → one port file" rule. |
| `src/math-preferences.vala` + `src/ui/math-preferences.blp` | `lib/math_preferences.rb` (new) | `Adw.PreferencesDialog` template: `Adw.ComboRow`×6, `Adw.SpinRow`, `Adw.SwitchRow`×5, `Gtk.SearchEntry`×2, `Gtk.Stack` | **missing** | Reachable via the still-missing `win.preferences` action. Backs onto `lib/settings.rb`'s keys (`angle-units`, `precision`, `show-thousands`, `number-format`, `base`, `word-size`, `source-units`/`target-units`, `enabled-completions`, `favorite-currencies`), all of which already exist in `Settings::DEFAULTS` with no UI in front of them. |

## 4. Non-window user-facing surfaces

| Upstream file | → `lib/*.rb` / `exe`/`bin` | Kind | Status | Notes |
|---|---|---|---|---|
| `src/gcalccmd.vala` | none (new `exe`/`bin` entry point needed) | CLI: a second `main()` that evaluates one expression from argv and prints the result, no GTK | **missing** | A real, separately-shipped upstream binary (`gcalccmd`, see `data/gcalccmd.1`). No Ruby equivalent script exists under `bin/` or `exe/`; `bin/setup` and `bin/turbo_tests2` are dev tooling, not this. |
| `search-provider/search-provider.vala` + its `.service.in`/`.ini` | `lib/search_provider.rb` (new) | GNOME Shell search-provider D-Bus service, no widgets of its own but a user-facing feature (search "12*34" in GNOME Shell's overview) | **missing** | Entirely unported; nothing in `lib/` implements the `org.gnome.Shell.SearchProvider2` interface. |

## 5. Data-level user-facing surfaces

| Upstream file | → port equivalent | Kind | Status | Notes |
|---|---|---|---|---|
| `data/org.gnome.calculator.gschema.xml` | `lib/settings.rb` | GSettings schema (19 keys: `accuracy`, `angle-units`, `base`, `button-mode`, `currency-display`, `enabled-completions`, `favorite-currencies`, `history-tape`, `number-format`, `precision`, `refresh-interval`, `show-thousands`, `show-zeroes`, `source-units`, `target-units`, `unit-category`, `window-maximized`, `window-position`, `window-size`, `word-size`) | **exists** | `Settings::DEFAULTS` carries all 19 keys with upstream's nicks and defaults, backed by a JSON file instead of GSettings (documented trade-off in the file's own header comment). Keys with no consuming UI yet (preferences, converter, history) sit unused. |
| `data/org.gnome.Calculator.desktop.in` | none | desktop launcher entry (name, icon, actions=new-window) | **missing** | No `.desktop` file anywhere in the port tree. |
| `data/org.gnome.Calculator.metainfo.xml.in` | none | AppStream metadata (description, screenshots, release notes) | **missing** | Not present. |
| `data/icons/**/*.svg` (app icon ×2 + symbolic) | none | app/window icon | **missing** | `MathWindow#window` sets no `icon_name`; no icon files are shipped in the port. |
| `src/ui/style.css` | `lib/style.css` | GTK CSS stylesheet | **exists** (unverified parity) | A `lib/style.css` exists; not diffed rule-by-rule against upstream's in this survey — flag for `component-parity`. |
| `po/*.po` (78 languages) + `po/POTFILES.in` | `lib/translations.rb` | gettext catalogue | **exists** (partial, per `translation-parity` skill's remit) | `lib/translations.rb` is present but this survey does not audit msgid coverage — that is `translation-parity`'s job, not this one. |

## 6. Backend library (`lib/*.vala` upstream) — not UI, but surveyed per the task's "every file that contributes a user-facing component" instruction since several back the still-missing UI above

| Upstream file | → `lib/*.rb` | Status |
|---|---|---|
| `lib/number.vala` | `lib/number.rb` | exists |
| `lib/equation.vala` | `lib/equation.rb` | exists |
| `lib/equation-lexer.vala` | `lib/equation_lexer.rb` | exists |
| `lib/equation-parser.vala` | `lib/equation_parser.rb` | exists |
| `lib/math-equation.vala` | `lib/math_equation.rb` | exists |
| `lib/math-function.vala` | `lib/math_function.rb` | exists |
| `lib/math-variables.vala` | `lib/math_variables.rb` | exists |
| `lib/function-manager.vala` | `lib/function_manager.rb` | exists |
| `lib/evaluation-budget.vala` | `lib/evaluation_budget.rb` | exists |
| `lib/financial.vala` | `lib/financial.rb` | exists |
| `lib/serializer.vala` | `lib/serializer.rb` | exists |
| `lib/unit.vala` | `lib/unit.rb` | exists |
| `lib/currency.vala` | `lib/currency.rb` | exists |
| `lib/currency-provider.vala` | `lib/currency_provider.rb` | exists |
| `lib/providers/boc-provider.vala` | `lib/providers/boc_provider.rb` | exists |
| `lib/providers/ecb-provider.vala` | `lib/providers/ecb_provider.rb` | exists |
| `lib/providers/imf-provider.vala` | `lib/providers/imf_provider.rb` | exists |
| `lib/providers/unt-provider.vala` | `lib/providers/unt_provider.rb` | exists |
| `lib/mpfr-glue.vala` (+ `libmpfr/`) | n/a | not a port target: internal MPFR/GMP glue for Vala's C interop; Ruby's `bigdecimal`/native `Integer`/`Float` replace its role, as `number.rb`'s own header explains |

## Binding-gem check (done as part of this survey, no code changed)

`soup3` (the one gem this fleet's instructions call mandatory for this app)
is already fully wired on `ruby`: declared in `gnome-calculator-rb.gemspec`
(`spec.add_dependency("soup3")`, alongside `gtk4`/`adwaita`/`glib2`), present
in `nix/Gemfile`, `libsoup_3` is in `flake.nix`'s `gtkStack`, and
`lib/currency_provider.rb` actually calls `Soup::Session`/`Soup::Message` for
the ECB/BoC/IMF/UNT rate downloads rather than hand-rolling HTTP. Nothing to
fix here.

## Summary count

- Components with a `lib/*.rb` home that exists: 1 window (partial), 1 button
  panel (basic only, of 5), 16 backend-library files, settings, style.css,
  translations scaffold, application.rb (partial) — **~20 upstream files
  covered**, several only partially.
- Components with no `lib/*.rb` at all: mode-switch stack (`math-buttons.vala`),
  4 of 5 button panels, both popovers + their shared base class, the
  converter, the history view (2 upstream `.blp` files), preferences dialog,
  shortcuts dialog, the CLI binary, the search provider, the desktop file,
  the AppStream metadata, the app icons — **14 upstream
  files/surfaces with zero port presence**.
- Every GTK/GIO action upstream installs (`win.mode`, `win.undo`, `win.redo`,
  `win.back`, `win.clear`, `win.number-format`, `win.preferences`,
  `app.new-window`, `app.quit`, `app.shortcuts`, `app.help`, `app.about`,
  `cal.insert-digit`, `cal.toggle-bit`) is missing from `lib/` — a `grep -n
  "add_action\|install_action" lib/**/*.rb` in this repo returns nothing.
