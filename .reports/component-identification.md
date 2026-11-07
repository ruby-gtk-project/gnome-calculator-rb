# Component identification — gnome-calculator-rb

Method: `component-identification` skill, run against `origin/main` (Vala +
blueprint) and the `ruby` branch's `lib/`, `exe/`.

This step was already performed in detail and committed as
[`component-inventory.md`](component-inventory.md) in this same directory —
630 lines, 23 numbered upstream units (`src/gnome-calculator.vala` through
`po/`), each with its widget table (type × count, CSS classes, signals,
notes), plus the 15-file engine-only table and a 10-item risk list. That
document satisfies this skill's Step 5 deliverable and is **adopted here
unchanged** rather than re-derived, with the counts re-verified below.

## Re-verified counts (this pass)

```
git ls-tree -r --name-only origin/main | grep -c '^src/.*\.vala$'      -> 14 UI source files
git ls-tree -r --name-only origin/main | grep -c '^src/ui/.*\.blp$'    -> 14 blueprint files
ls lib/*.rb | wc -l                                                     -> 20 (19 engine + application.rb)
ls lib/gnome/calculator/rb/*.rb                                         -> version.rb only
```

Confirms the inventory's headline table: **14 upstream UI source files, 14
blueprint files, 28 component units (template roots) on the upstream side;
on the `ruby` side, 1 port file (`lib/gnome_calculator/application.rb`) and
it is a placeholder — a `Gtk::Application`, one `Adwaita::ApplicationWindow`,
an `Adwaita::ToolbarView`/`HeaderBar`, and an `Adwaita::StatusPage` reading
"Run exe/gcalccmd to evaluate expressions with the ported engine."**

Read directly (`lib/gnome_calculator/application.rb`, 65 lines): it installs
**zero** `win.`/`app.` actions, **zero** accelerators, **zero** menu models,
and holds no `MathEquation` buffer. There is nothing to compare components
against beyond that one window, because nothing else exists.

## Units identified, in the order a user meets them

Reproduced from `component-inventory.md` for traceability — unit name, the
upstream file(s), the port file, present/absent:

| # | Unit | Upstream | Port file | Present |
|---|---|---|---|---|
| 1 | Application (actions, accelerators, About dialog, Close-All dialog) | `src/gnome-calculator.vala` | `lib/gnome_calculator/application.rb` | placeholder only |
| 2 | Main window + `window_menu` + `primary_menu` | `src/math-window.vala` + `.blp` | `lib/math_window.rb` | no |
| 3 | Keyboard shortcuts dialog (44 items / 5 sections) | `src/ui/math-shortcuts.blp` | `lib/shortcuts_dialog.rb` | no |
| 4 | Equation display | `src/math-display.vala` + `.blp` | `lib/math_display.rb` | no |
| 5 | Autocompletion providers (5) | `src/math-display.vala:560-877` | `lib/completion_providers.rb` | no |
| 6 | History view | `src/math-history.vala` (`HistoryView`) + `.blp` | `lib/history_view.rb` | no |
| 7 | History entry row | `src/math-history.vala` (`HistoryEntry`) + `.blp` | `lib/history_entry.rb` | no |
| 8–17 | Basic/Advanced/Financial/Programming/Keyboard/Conversion button panels, bit panel, financial dialogs, preferences, currency favourites | `src/math-buttons.vala` + 6 `.blp` panels + dialogs | — | no |
| 18 | Converter widget | `src/math-converter.vala` + `.blp` | `lib/math_converter.rb` | no |
| 19 | Stylesheet (399 lines, 44 classes) | `src/ui/style.css` | `lib/style.css` | no (not loaded; no UI references it) |
| 20 | Settings (19 keys) | `data/org.gnome.calculator.gschema.xml` | `lib/settings.rb` | **yes** |
| 21 | Shell search provider | `search-provider/search-provider.vala` | — | no |
| 22 | CLI | `src/gcalccmd.vala` | `exe/gcalccmd` | **yes** |
| 23 | Translations (101 languages) | `po/` | — | no |

Supporting, non-UI engine files (`lib/*.vala` → `lib/*.rb`): 19 of 20 are
present and working (`number.rb`, `equation_lexer.rb`, `equation_parser.rb`,
`equation.rb`, `serializer.rb`, `unit.rb`, `currency.rb`,
`currency_provider.rb`, 4 provider files, `financial.rb`,
`function_manager.rb`, `math_function.rb`, `math_variables.rb`,
`evaluation_budget.rb`). The one engine gap is `lib/math_equation.rb`
(`lib/math-equation.vala`, 1809 lines — the `GtkSource.Buffer` subclass every
display widget binds to), which blocks unit 4 and everything downstream of
it.

## Totals

| | Upstream | Port |
|---|---:|---:|
| UI component units | 20 (1–19, 21) | 2 (unit 1 partial, unit 20 Settings) |
| Buttons across the five panels | ~148 | 0 |
| Menu models | 4 | 0 |
| Shortcut items | 44 | 0 |
| CSS classes attached to a widget | 44 | 0 (file exists, never loaded by any built widget) |

See `component-inventory.md` for the full per-unit widget/CSS/signal tables
and the 10-item blocker list (GtkSourceView dependency, `Adw.ApplicationWindow`
binding status, variant-typed actions, the bit-panel's runtime CSS, etc.).
