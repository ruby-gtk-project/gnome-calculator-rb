# Component identification — gnome-calculator-rb

Fifth pass, at `eba4d35e` ("Fix stale drive-script header comment, confirm
DRIVE OK"). Two commits landed between the fourth pass (`da40269a`) and
this one: `8de8a498` ("Port the mode-switching MathButtons host and the
Advanced button panel") and `eba4d35e` itself (drive-script comment only,
no `lib/` change). This pass re-reads `lib/` directly rather than trusting
the fourth pass's table.

`8de8a498` changes unit status materially:

- **Unit 8 (button-panel host / `cal` action group)** moves from **no** to
  **present** — `lib/math_buttons.rb` (277 lines) ports `src/math-buttons.vala`:
  a `Gtk::Stack` holding one panel per mode, and the `cal` action group with
  18 actions (`insert-general`, `insert-digit`, `insert-brackets`,
  `insert-alpha`, `insert-function`, `insert-symbol-before/after`,
  `insert-exponent`, `insert-numeric-point`, `subtract`, `square`,
  `nth-root`, `logarithm`, `factorize`, `undo`, `clear`, `solve`,
  `set-number-mode`). Confirmed by `grep -rn "add_action" lib/`, which for
  four passes returned nothing and now returns 19 lines (18 in
  `math_buttons.rb` + `win.mode` in `math_window.rb`).
- **Units 9–14 (panels)**: Advanced moves from no to **present**
  (`lib/advanced_button_panel.rb`, 511 lines, ports
  `src/buttons-advanced.vala` + `.blp`). Financial, Programming, Conversion,
  the bit panel and the converter are still **no** — `math_buttons.rb`
  itself documents this: `else raise ArgumentError, "MathButtons has no
  panel for #{mode.inspect} yet"` for any mode besides `:basic`/`:advanced`.
- **Unit 2 (main window)**: gains the header bar's Mode Selection menu
  button and the `win.mode` action (`lib/math_window.rb`), so "zero `win.*`
  actions" from the prior pass's totals row is no longer true.

## Re-verified counts (this pass)

```
ls lib/*.rb | wc -l                              -> 28 (23 prior + math_buttons.rb +
                                                         advanced_button_panel.rb;
                                                         math_equation.rb grew +212 lines
                                                         with the editing primitives the
                                                         advanced panel's actions need)
grep -rn "add_action\|install_action" lib/ exe/  -> 19 (18 in math_buttons.rb, 1 win.mode
                                                         in math_window.rb) — was 0 for
                                                         four straight passes
grep -c "AdwShortcutsItem {" <(git show origin/main:src/ui/math-shortcuts.blp) -> 43, unchanged
grep -c "\['" lib/math_shortcuts.rb                                            -> 38, unchanged
```

Live confirmation (not just static grep) via `test/drive_gnome_calculator.rb`,
re-run this pass: the sin button inserts through `cal.insert-function`, the
factorize button replaces the display through `cal.factorize`, the x²
button inserts through `cal.square`, the |x| button wraps via
`cal.insert-brackets`, the inverse toggle flips the sin button's label, and
`win.mode('advanced')`/`('basic')` switches `MathButtons`' visible stack
child both ways. See `component-parity.md` unit 8/9 for the full behavioural
read.

## Units identified, in the order a user meets them

Same 23-unit list as `component-inventory.md`, with this pass's two status
changes folded in:

| # | Unit | Port file | Present |
|---|---|---|---|
| 1 | Application (actions, accelerators, About dialog, Close-All dialog) | `lib/gnome_calculator/application.rb` | partial — real window built, zero app-level actions/accelerators/dialogs |
| 2 | Main window + 2 menu models | `lib/math_window.rb` | partial — **gained `win.mode` this pass**, still zero other `win.*` actions, zero other menus |
| 3 | Keyboard shortcuts dialog (43 items / 5 sections) | `lib/math_shortcuts.rb` | partial — 38/43 items, unchanged |
| 4 | Equation display | `lib/math_display.rb` | partial — plain `Gtk::TextView`, narrow key table, unchanged |
| 5 | Autocompletion providers (5) | — | no |
| 6 | History view | `lib/history_view.rb` | partial — in-memory only, unchanged |
| 7 | History entry row | `lib/history_entry.rb` | partial, unchanged |
| 8 | Button-panel host (`cal` action group, mode stack) | `lib/math_buttons.rb` | **present this pass** — 18 `cal.*` actions, Basic/Advanced panels switchable; Financial/Programming/Conversion raise `ArgumentError` on selection (not silently ignored, but not built either) |
| 9 | Basic panel | `lib/basic_button_panel.rb` | partial, unchanged |
| 10 | Advanced panel | `lib/advanced_button_panel.rb` | **present this pass** — trig/hyperbolic/inverse grid, exponent/log stack, complex-component row, inverse-modifier toggle swapping label+action+target live |
| 11–14 | Financial, Programming, Conversion panels, bit panel, financial dialogs, converter | — | no — explicitly rejected by `math_buttons.rb`'s mode dispatch, not a silent gap |
| 15 | Popover base (`MathPopover<T>`) | `lib/math_popover.rb` | present, unchanged |
| 16 | Function popover | `lib/math_function_popover.rb` | present, unchanged |
| 17 | Variable popover | `lib/math_variable_popover.rb` | present, unchanged |
| 18 | Preferences + favourite-currencies page | — | no |
| 19 | Stylesheet | `lib/style.css` | present, unchanged |
| 20 | Settings (19 keys) | `lib/settings.rb` | yes, unchanged |
| 21 | Shell search provider | — | no |
| 22 | CLI | `lib/gcalccmd.rb` + `exe/gcalccmd` | yes, unchanged |
| 23 | Translations (101 languages) | — | partial — see `translation-parity.md`; file-level parity (101/101 `.po` files present, byte-identical) but **zero functioning translation at runtime** (no `.mo` catalogue anywhere in the tree, confirmed live this pass by forcing `LANG=fr_FR` and `GetText.set_locale("fr")` and still getting the English string back for a msgid `po/fr.po` does carry a French translation for) |

## Totals (corrected this pass)

| | Upstream | Port |
|---|---:|---:|
| Component units with any port counterpart | 23 | 15 (1,2,3,4,6,7,8,9,10,15,16,17,19,20,22) + translations now file-partial |
| Units with zero port counterpart | 23 | 8 (5, 11–14 as a group, 18, 21) + translations' runtime half counts as zero |
| Shortcut items | 43 | 38, unchanged |
| `win.`/`app.`/`cal.` actions installed anywhere in `lib/` | ~30+ | **19** — first non-zero reading across five passes |
| Engine files | 20 | 20 — complete |

8 of 23 units still have zero port counterpart at all (autocomplete, the
three missing panels + bit panel + financial dialogs + converter as a
group, preferences, shell search), and of the 15 that do, only stylesheet
loading, settings storage and the CLI hold full parity — the rest,
including both new units this pass, are explicitly partial. The drive
gate's "13 components, 62 checks" this round covers the live-verifiable
subset of these 15 — it does not and cannot exercise the 8 with zero
counterpart, so treat that gate as confirming what exists, not as
evidence against what the inventory says is still missing.
