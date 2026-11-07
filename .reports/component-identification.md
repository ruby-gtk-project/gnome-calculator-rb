# Component identification — gnome-calculator-rb

Third pass. `origin/main` (Vala + blueprint) vs the `ruby` branch at
`9824569e` ("Expand the drive script: history, shortcuts dialog, key
controller").

Method: `component-identification` skill. The detailed per-unit inventory
lives in [`component-inventory.md`](component-inventory.md) (23 numbered
upstream units) and is adopted here, **with one correction this pass makes
to it**: that file's own "State of the port" section was committed at
`6645ebf4`, which is *before* `8cf1a973` (ported `history_entry.rb`,
`history_view.rb`, `math_shortcuts.rb`, wired history into the window) and
`9824569e` landed. Three of its unit tables (§3 shortcuts dialog, §6
history view, §7 history entry) said "no" for files that already existed on
disk. This is now fixed in `component-inventory.md` directly (search
"*(second update)*"); the corrected counts below are current as of
`9824569e`, re-verified by reading `lib/` directly, not by trusting any
prior report.

## Re-verified counts (this pass)

```
ls lib/*.rb | wc -l                     -> 23 (20 engine + application.rb* + math_window.rb + math_display.rb
                                                + basic_button_panel.rb + math_shortcuts.rb + history_view.rb
                                                + history_entry.rb; *lib/gnome_calculator/application.rb)
grep -rc "add_action\|install_action" lib/ exe/ | grep -v ':0' -> no output: still zero anywhere
grep -c "AdwShortcutsItem {" <(git show origin/main:src/ui/math-shortcuts.blp) -> 43 (this file's own
                                                                                    Totals table previously
                                                                                    said 44 — miscounted)
grep -c "\['" lib/math_shortcuts.rb                                            -> 38
```

Confirms: the engine (20/20 files) and a first vertical UI slice are
present. The UI slice now covers, each at least partially: the application
shell, the main window, the display, the basic button panel, the history
view and its rows, and the keyboard-shortcuts dialog. Nothing else upstream
lists exists in `lib/` at all.

## Units identified, in the order a user meets them

Same 23-unit list as `component-inventory.md`, with the three corrections
folded in (unit numbers match that file):

| # | Unit | Port file | Present |
|---|---|---|---|
| 1 | Application (actions, accelerators, About dialog, Close-All dialog) | `lib/gnome_calculator/application.rb` | partial — real window built, zero actions/accelerators/dialogs |
| 2 | Main window + 2 menu models | `lib/math_window.rb` | partial — basic mode only, zero `win.*` actions, zero menus |
| 3 | Keyboard shortcuts dialog (43 items / 5 sections) | `lib/math_shortcuts.rb` | **partial, corrected this pass** — 38/43 items, not reached by an `app.shortcuts` action (none exists), no `msgctxt` |
| 4 | Equation display | `lib/math_display.rb` | partial — plain `Gtk::TextView`, narrow key table |
| 5 | Autocompletion providers (5) | — | no |
| 6 | History view | `lib/history_view.rb` | **partial, corrected this pass** — in-memory only, no tape persistence |
| 7 | History entry row | `lib/history_entry.rb` | **partial, corrected this pass** |
| 8 | Button-panel host (`cal` action group, mode stack) | — | no |
| 9–14 | Basic/Advanced/Financial/Programming/Conversion panels, bit panel, financial dialogs, converter | `lib/basic_button_panel.rb` only | basic: partial; the other 4 panels + converter: no |
| 15–17 | Popover base, function popover, variable popover | — | no |
| 18 | Preferences + favourite-currencies page | — | no |
| 19 | Stylesheet | `lib/style.css` | present as a file, loaded by `Gtk::CssProvider` at application priority — the one unit where "present" and "attached" both hold, confirmed live by the drive script |
| 20 | Settings (19 keys) | `lib/settings.rb` | yes |
| 21 | Shell search provider | — | no |
| 22 | CLI | `exe/gcalccmd` | yes |
| 23 | Translations (101 languages) | — | no — see `translation-parity.md` for the engine-level gap too (currency/unit names carry no `_()` marker at all) |

## Totals (corrected)

| | Upstream | Port |
|---|---:|---:|
| Component units with any port counterpart | 23 | 8 (1,2,3,4,6,7,19,20,22) + 22 CLI, all but 19/20/22 partial |
| Shortcut items | 43 | 38 |
| `win.`/`app.`/`cal.` actions installed anywhere in `lib/` | ~30+ | **0**, unchanged from the previous pass |
| Engine files | 20 | 20 — complete |

See `component-parity.md` for the behavioural check this file's "partial"
tags point to, and `accountability-ensurance.md` for the staleness finding
against `component-inventory.md` itself.
