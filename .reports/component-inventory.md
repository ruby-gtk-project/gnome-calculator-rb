# gnome-calculator-rb — upstream component inventory

Surveyed against `origin/main` (upstream Vala/blueprint GNOME Calculator).
This is a survey only — no app code was written in this pass.

Legend for **Exists?**: `yes` = a `lib/*.rb` already covers this component
(fully or partially — see Notes); `no` = nothing in `lib/` builds it;
`partial` = some of the component's behaviour/widgets are ported but not all.

## Application shell

| Upstream file | → `lib/*.rb` | Kind | Exists? | Notes |
|---|---|---|---|---|
| `src/gnome-calculator.vala` (`Calculator : Adw.Application`) | `lib/gnome_calculator/application.rb` | app class | partial | Port builds `Gtk::Application` (not `Adw::Application` — see FINDINGS.md) with a single `activate` handler that presents `MathWindow`. Missing: `--mode`, `--solve`, `--equation`, `--version` CLI option entries; app actions `new-window`, `help`, `about`, `quit`; multi-window support (upstream allows `NON_UNIQUE` + multiple `MathWindow`s, tracks `last_opened_window`). |
| `src/gcalccmd.vala` (CLI one-shot solver, `gcalccmd` binary) | — | CLI entry point | no | No port equivalent at all. Separate binary from the GUI; nothing in `lib/` or `bin/` builds it. |
| `data/org.gnome.calculator.gschema.xml` | `lib/settings.rb` | GSettings schema | yes (re-implemented) | Port deliberately does not use GSettings (no schema compile/install step); backs the same keys (`history-tape`, `accuracy`, `word-size`, `base`, `show-thousands`, `show-zeroes`, `number-format`, `angle-units`, `refresh-interval`, `currency-display`, `enabled-completions`, `favorite-currencies`, `button-mode`, `unit-category`, `source-units`, `target-units`, `precision`, `window-position`, `window-maximized`, `window-size`) with a JSON file under `XDG_CONFIG_HOME`. All keys accounted for. |
| `data/org.gnome.Calculator.metainfo.xml.in`, `.desktop.in` | — | packaging metadata | no | Not part of widget surface; no port equivalent, not required for app behavior. |
| `po/*.po`, `po/POTFILES.in` (translation catalogue) | `lib/translations.rb` | i18n | partial | Port provides a `Gettext` shim module used by every widget class (`_()`, `include Gettext`), but there is no `.po` catalogue and no `po/` directory in the port — strings are untranslated / English-only. See the `translation-parity` skill for the dedicated audit. |
| `src/ui/gnome-calculator.gresource.xml` (GResource manifest) | — | build manifest | n/a | No GResource bundling in the port; each `.rb` widget file builds its own tree instead of loading a `.ui` resource. Listed here only to anchor the one-to-one file map below (every entry in it is one of the rows that follow). |
| `src/ui/style.css` | `lib/style.css` | stylesheet | yes | Loaded at `GTK_STYLE_PROVIDER_PRIORITY_APPLICATION` by `Application#css_provider`. |

## Main window and panes

| Upstream file(s) | → `lib/*.rb` | Kind | Exists? | Notes |
|---|---|---|---|---|
| `src/math-window.vala` + `src/ui/math-window.blp` | `lib/math_window.rb` | main window | partial | Ported: header bar, `AdwToolbarView`, `MathDisplay`, `BasicButtonPanel`, `HistoryView`, keyboard `EventControllerKey`. **Not ported**: the `window_menu` (mode switch: Basic/Advanced/Financial/Programming/Keyboard/Conversion — `win.mode` action with 6 targets), `primary_menu` (New Window / Preferences / Keyboard Shortcuts / About / Quit), the `MathButtons` mode-switching stack itself, the `MathConverter` pane, win-level actions (`win.mode`, `win.close`, copy/paste, `win.undo`/`win.redo` if present), and window state persistence (position/maximized/size → `settings.rb` keys exist but nothing writes them from this window). |
| `src/math-display.vala` + `src/ui/math-display.ui` (blp not in upstream tree — built from `.ui`) | `lib/math_display.rb` | entry/display widget | yes | — |
| `src/math-buttons.vala` (no own `.blp`; it is the mode-switch container/stack over the five button panels + `MathConverter`) | — | mode-switching container (`Adw.Bin` holding a `Gtk.Stack`-like switch over `ButtonMode`) | no | Not ported. This is the piece that would let the window switch among Basic/Advanced/Financial/Programming/Keyboard/Conversion modes; currently `MathWindow` wires `BasicButtonPanel` directly with no switcher. |
| `src/buttons-basic.vala` + `src/ui/buttons-basic.blp` | `lib/basic_button_panel.rb` | button grid (basic mode) | yes | Digits, operators, percent, grouping, memory/function `MenuButton`s (unpopulated), result button. Comment in file notes memory/function menus deliberately left empty pending popovers below. |
| `src/buttons-advanced.vala` + `src/ui/buttons-advanced.blp` | `lib/advanced_button_panel.rb` (does not exist) | button grid (advanced mode) | no | Trig/log/exponent/constant buttons — entirely unported. |
| `src/buttons-financial.vala` + `src/ui/buttons-financial.blp` | `lib/financial_button_panel.rb` (does not exist) | button grid (financial mode) | no | Financial function buttons (ctrm, ddb, fv, gpm, pmt, pv, rate, sln, syd, term) — unported as a panel; `lib/financial.rb` ports the calculation logic only (see below), not the button grid. |
| `src/buttons-programming.vala` + `src/ui/buttons-programming.blp` | `lib/programming_button_panel.rb` (does not exist) | button grid (programming mode) | no | Hex/oct/bin digit buttons, bitwise ops, word-size selector, base selector — unported. |
| `src/buttons-conversion.vala` + `src/ui/buttons-conversion.blp` | `lib/conversion_button_panel.rb` (does not exist) | button grid (conversion mode) | no | Unit-category buttons feeding `MathConverter` — unported. |
| `src/math-converter.vala` + `src/ui/math-converter.blp` | `lib/math_converter.rb` (does not exist) | unit/currency converter pane | no | `CurrencyDisplay` enum (code/name/both), category/source-unit/target-unit `ComboRow`s or similar, swap button. Entirely unported; `lib/unit.rb`, `lib/currency.rb`, `lib/currency_provider.rb` and the four `lib/providers/*.rb` port the *data/calculation* side only — there is no widget consuming them yet. |
| `src/ui/math-shortcuts.blp` (`AdwShortcutsDialog`) | `lib/math_shortcuts.rb` | keyboard-shortcuts dialog | yes (worked around) | Comment documents that `Adwaita::ShortcutsItem` construction is rejected by the Ruby bindings ("wrong arguments") and substitutes a plain `Adwaita::Dialog` over a label/accelerator list with the same sections/shortcuts. Worth re-checking against current `adwaita` gem version per the `ruby-gtk` skill before assuming it's unfixable. |

## Popovers / dialogs

| Upstream file(s) | → `lib/*.rb` | Kind | Exists? | Notes |
|---|---|---|---|---|
| `src/math-popover.vala` (generic `MathPopover<T> : Gtk.Popover` base class) | `lib/math_popover.rb` (does not exist) | abstract popover base | no | Shared behaviour: name-entry normalization (spaces→underscores), reserved names, operator keyword list, add/remove row handling. Not ported as a shared base; would need to be either a Ruby module/base class or inlined into each popover below. |
| `src/math-function-popover.vala` + `src/ui/math-function-popover.blp` | `lib/math_function_popover.rb` (does not exist) | function-management popover | no | Built-in vs. custom function lists (`Gtk.Stack`, two `Gtk.ListBox`es), `add_arguments_button` SpinButton, name/add/error controls from the `MathPopover` base. `lib/function_manager.rb` and `lib/math_function.rb` port the data model only; no popover widget. Referenced but left unpopulated from `basic_button_panel.rb`'s function `MenuButton`. |
| `src/math-variable-popover.vala` + `src/ui/math-variable-popover.blp` | `lib/math_variable_popover.rb` (does not exist) | variable-management popover | no | `MathVariable` model (name/value/is_custom) ported in `lib/math_variables.rb` (data only); the popover widget (list box of variables, add/remove, name/value entry) is not ported. Referenced but left unpopulated from `basic_button_panel.rb`'s memory `MenuButton`. |
| `src/math-preferences.vala` + `src/ui/math-preferences.blp` (`Adw.PreferencesDialog`) | `lib/math_preferences.rb` (does not exist) | preferences dialog | no | `WordSize`/`RefreshInterval` enums, `Adw.ComboRow`s for angle units/word size/refresh interval/currency display/currency completion, `Adw.SpinRow` for decimal places. No port file; `app.about`/preferences entry point in `primary_menu` has nothing to open. |
| (upstream has no dedicated About dialog source file — built via `Adw.AboutDialog`/`Gtk.show_about_dialog` from `gnome-calculator.vala`'s `about_cb`) | — | about dialog | no | No port equivalent; `about_cb` itself isn't ported (see Application shell row above). |

## History

| Upstream file(s) | → `lib/*.rb` | Kind | Exists? | Notes |
|---|---|---|---|---|
| `src/math-history.vala` + `src/ui/history-view.blp` | `lib/history_view.rb` | history list view | yes | — |
| `src/ui/history-entry.blp` (presumably backed by a class inside `math-history.vala` or `math-window.vala`; no separate `history-entry.vala`) | `lib/history_entry.rb` | one history row | yes | — |

## Calculation engine / data model (non-widget, for completeness)

These are not GTK components but are listed because they're the files the
ported widgets above depend on, and their port state affects what a widget
port can assume is already available.

| Upstream file | → `lib/*.rb` | Exists? |
|---|---|---|
| `lib/math-equation.vala` | `lib/math_equation.rb` | yes |
| `lib/equation.vala`, `lib/equation-lexer.vala`, `lib/equation-parser.vala` | `lib/equation.rb`, `lib/equation_lexer.rb`, `lib/equation_parser.rb` | yes |
| `lib/number.vala` | `lib/number.rb` | yes |
| `lib/unit.vala` | `lib/unit.rb` | yes |
| `lib/currency.vala`, `lib/currency-provider.vala` | `lib/currency.rb`, `lib/currency_provider.rb` | yes |
| `lib/providers/{boc,ecb,imf,unt}-provider.vala` | `lib/providers/{boc,ecb,imf,unt}_provider.rb` | yes |
| `lib/financial.vala` | `lib/financial.rb` | yes (calc only — no button panel, see above) |
| `lib/function-manager.vala`, `src/math-function-popover.vala`'s `MathFunction`-adjacent model | `lib/function_manager.rb`, `lib/math_function.rb` | yes (data only) |
| `lib/math-variables.vala` / `src/math-variable-popover.vala`'s `MathVariable` | `lib/math_variables.rb` | yes (data only) |
| `lib/serializer.vala` | `lib/serializer.rb` | yes |
| `lib/evaluation-budget.vala` | `lib/evaluation_budget.rb` | yes |
| `lib/mpfr-glue.vala` / `libmpfr/mpfr-glue.vala` | — | no (GLib/MPFR glue; `lib/number.rb` presumably reimplements the needed arithmetic in Ruby — out of scope for this survey, flag for a later numeric-parity pass) |
| `gcalc/*.vala`, `gci/*.vala` (separate `libgcalc`/`libgci` libraries used by the search provider and gcalccmd) | — | no |
| `search-provider/search-provider.vala` + `.service.in` | — | no | GNOME Shell search provider integration — no port equivalent. |

## Summary

- **Fully ported as widgets**: application activation path (partial), main
  window shell (partial), basic-mode button grid, math display, history view
  + history entry row, keyboard-shortcuts dialog (worked around).
- **Not ported at all as widgets**: mode-switcher (`MathButtons`), advanced /
  financial / programming / conversion button panels, the unit/currency
  converter pane (`MathConverter`), the function-management popover, the
  variable-management popover, the preferences dialog, the About dialog, app
  menu actions (`new-window`, `help`, `about`, `quit`) and window actions
  (`mode`, etc.), the `gcalccmd` CLI, the GNOME Shell search provider.
- **Calculation/data layer**: essentially fully ported (equation engine,
  numbers, units, currencies + all four providers, financial formulas,
  function/variable data models, serializer). This is why several "no"
  widget rows above still show a "yes" data-model counterpart — the port has
  invested in the engine but not yet in 5 of 6 button-mode UIs or any of the
  three popovers/dialogs that sit on top of it.
- **Translations**: `Gettext` shim present and used throughout, but no `po/`
  catalogue exists in the port (see `translation-parity` skill for a
  dedicated pass).
