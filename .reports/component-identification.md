# Component identification — gnome-calculator-rb

Fourth pass, at `da40269a` ("Fix two screenshot races in the drive
script"), re-reading `lib/` directly rather than trusting the third pass's
table below. One commit landed between the third pass (`9824569e`) and
this one that changed unit status: `6888ae72` ("Port math_popover,
math_variable_popover, math_function_popover; extract gcalccmd"). Units
15–17 (popover base, function popover, variable popover) move from **no**
to **partial/present**; unit 22 (CLI) gains a backing `lib/gcalccmd.rb`
behind the unchanged `exe/gcalccmd`, matching house style's one-file rule
for the first time (previously the executable held the class body
directly). `da40269a` itself only touched the drive script, not `lib/`.

Third-pass header, unchanged below: `origin/main` (Vala + blueprint) vs the
`ruby` branch at `9824569e` ("Expand the drive script: history, shortcuts
dialog, key controller").

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
| 15 | Popover base (`MathPopover<T>`) | `lib/math_popover.rb` (204 lines) | **present this pass** — name-entry validation, add-button sensitivity, error revealer, `make_item_row`/`make_category_row` all built; reserved-name list (`_`, `rand`) and the operator list both carried over |
| 16 | Function popover | `lib/math_function_popover.rb` (215 lines) | **present this pass** — reached from the basic panel's function button, verified live (see `component-parity.md` unit 16) |
| 17 | Variable popover | `lib/math_variable_popover.rb` (203 lines) | **present this pass** — reached from the basic panel's memory button, verified live |
| 18 | Preferences + favourite-currencies page | — | no |
| 19 | Stylesheet | `lib/style.css` | present as a file, loaded by `Gtk::CssProvider` at application priority — the one unit where "present" and "attached" both hold, confirmed live by the drive script |
| 20 | Settings (19 keys) | `lib/settings.rb` | yes |
| 21 | Shell search provider | — | no |
| 22 | CLI | `lib/gcalccmd.rb` (108 lines) behind `exe/gcalccmd` (6 lines) | yes — **extracted this pass** to match house style; same behaviour, verified live |
| 23 | Translations (101 languages) | — | no — see `translation-parity.md` for the engine-level gap too (currency/unit names carry no `_()` marker at all) |

## Totals (corrected)

| | Upstream | Port |
|---|---:|---:|
| Component units with any port counterpart | 23 | 13 (1,2,3,4,6,7,15,16,17,19,20,22) + the basic panel folded into 9–14, all but 19/20/22 partial |
| Units with zero port counterpart | 23 | 10 (5, 8, 11, 12, 13, 14, 18, 21, 23, plus the 4 non-basic panels folded into 9–14 as a group) |
| Shortcut items | 43 | 38, unchanged |
| `win.`/`app.`/`cal.` actions installed anywhere in `lib/` | ~30+ | **0**, unchanged across four passes — re-checked this pass: `grep -rn "add_action\|install_action" lib/ exe/` still returns nothing |
| Engine files | 20 | 20 — complete |

More than half of upstream's 23 units (10 of 23) still have zero port
counterpart, and of the 13 that do, only 3 (stylesheet loading, settings
storage, the CLI) hold full parity — the rest are explicitly partial. See
`component-parity.md` for the behavioural check this file's "partial"
tags point to, and `accountability-ensurance.md` for the staleness finding
against `component-inventory.md` itself (not yet re-synced with this
pass's popover/`gcalccmd.rb` changes as of this writing).
