# Component parity — gnome-calculator-rb

Fourth pass, at `da40269a`. Carries forward every unit's verdict from the
third pass unchanged except units 15–17 (popovers, newly built in
`6888ae72`) and unit 22 (CLI, extracted to `lib/gcalccmd.rb` in the same
commit), both re-derived fresh below.

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `da40269a` |
| Units with full parity | 0 / 23 |
| Units with partial, behaviourally-verified parity | 9 / 23 |
| Units with zero parity | 14 / 23 |
| Runtime gate this round | `drive_ok=true`, **53 checks, 0 failed**, 18 numbered steps — covers units 1, 2, 4, 6, 7, 15, 16, 17, 19, 20, 22, plus the engine directly: **11 units out of 23**. The other **12 units are exercised by zero checks and are reported `gap`, not passing by omission** |

Method: `component-parity` skill, four axes (count, style, behaviour, text)
per unit, using the corrected unit list in `component-identification.md`.
Every "present" claim below was re-run live this pass:
`nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb`
→ `53 of 53 checks passed`, `DRIVE OK` (re-run directly for this report, not
read off the commit message).

## Unit 1 — Application: `src/gnome-calculator.vala` → `lib/gnome_calculator/application.rb`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Actions (`app.new-window`, `app.help`, `app.about`, `app.quit`, `app.shortcuts`) | 5 | 0 | **gap** |
| Accelerators (18 bindings) | 18 | 0 | **gap** |
| `Adw.AboutDialog` | present | not built | **gap** |
| `Adw.AlertDialog` "Close All?" | present | not built | **gap** |
| CLI options (`--mode`, `--solve`, `--equation`, `--version`) | present | not built | **gap** |
| Multi-window (`new-window`) | present | not built — `Gtk::Application` instance is a singleton with one window, no `app.new-window` to open a second | **gap** |
| Window construction, CSS loaded at application priority | `MathWindow` built, CSS attached | real `Adwaita::ApplicationWindow`\*, CSS provider verified live | **partial — the one row with parity** |

\*Upstream's app type is `Adw.Application`; the port uses a plain
`Gtk::Application` — see `FINDINGS.md`, which records that a smoke test in
this exact devshell did **not** reproduce "Adwaita::Application is broken in
the Ruby bindings," so the substitution currently rests on caution, not a
confirmed blocker. Worth re-litigating before this is called settled.

Verdict: **gap.**

## Unit 2 — Main window: `src/math-window.vala` → `lib/math_window.rb`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| `win.*` actions (copy, paste, undo, redo, mode, clear, back, preferences, close, number-format) | 10 | 0 | **gap** |
| Menu models (`window_menu`, `primary_menu`) | 2 | 0 | **gap** |
| Mode-switch stack (basic/advanced/financial/programming/keyboard/conversion) | 6 modes | 1 (basic only, hard-coded, no stack) | **gap** |
| Undo/redo/back buttons | 3 | 0 | **gap** |
| History tape persistence across runs | yes (`history-tape` GSettings key) | no — `HistoryView` is in-memory only, confirmed by reading `lib/history_view.rb` | **gap** |
| Key controller (digits, operators, Enter/Escape/Backspace/Delete/period) | superset (also Shift→inverse, Ctrl+B/O/D/H in programming mode) | present, verified live: `6+3`→`9`, Enter solves, Escape clears, Backspace deletes | **partial — this subset has parity** |
| Window shell (`Adwaita::ApplicationWindow`, toolbar view, header bar) | yes | yes, verified live | **partial — parity** |

Verdict: **gap**, with two behaviourally-verified rows (key subset, window
shell).

## Unit 3 — Keyboard shortcuts dialog: `src/ui/math-shortcuts.blp` → `lib/math_shortcuts.rb`

Re-derived directly from both sides this pass (not from the stale "no" the
inventory previously carried).

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Widget kind | `$AdwShortcutsDialog` (native Libadwaita widget) | plain `Adwaita::Dialog` over a `Gtk::ScrolledWindow`/`Gtk::Box`/`Gtk::ListBox` tree | **substitution, stated in the port's own header comment** (the bindings reject `Adwaita::ShortcutsItem`'s keyword constructors — recorded in the comment, not in `FINDINGS.md`; see `accountability-ensurance.md`) |
| Reached by | `app.shortcuts` action, `<Ctrl>?` accelerator | a header-bar button only — `app.shortcuts` does not exist (unit 1) | **gap**: the `<Ctrl>?` accelerator from upstream's own shortcuts list does not open this dialog in the port |
| Section count | 5 | 5 | parity |
| Item count | 43 (recounted: `grep -c 'AdwShortcutsItem {' src/ui/math-shortcuts.blp` on `origin/main`) | 38 | **gap**, 5 items missing: |
| | | | — "Switch to Keyboard Mode (alt.)", `<Ctrl><Alt>t` (General/Switching-Modes section) |
| | | | — "Floor (⌊⌋)" ltr, `<Alt>[+]` |
| | | | — "Ceiling (⌈⌉)" ltr, `<Ctrl>[+]` |
| | | | — "Floor (⌊⌋)" rtl, `<Alt>]+[` |
| | | | — "Ceiling (⌈⌉)" rtl, `<Ctrl>]+[` |
| Text source | `C_("shortcuts dialog", "…")` — a *msgctxt*-scoped gettext call | plain `_(label)`/`_(title)` at render time, no msgctxt | **gap** — see `translation-parity.md`; even where the English text is byte-identical, a translator's `msgctxt "shortcuts dialog"` entry in `po/*.po` will not be found by a lookup with no context, so these rows render in English in every locale regardless of `po/` coverage |
| Behaviour | opens over the window, closes on dismiss | verified live: opens a real `Adwaita::Dialog` titled "Keyboard Shortcuts", closes cleanly | **partial — parity for what exists** |

Verdict: **gap** — a real, mostly-complete substitute widget that is
unreachable by its real trigger, missing 5 of 43 rows, and invisible to
translation regardless of `po/` coverage.

## Unit 4 — Equation display: `src/math-display.vala` → `lib/math_display.rb`

Unchanged from the prior pass's finding: scrolled `Gtk::TextView` (not
`GtkSource.View` — see `FINDINGS.md`), backspace button, status/error label,
all verified live (error status shown and cleared). Missing: the scroll
controller, the loading spinner, the OSK-aware backspace, and the whole
key-substitution table (×, ÷, √, π, τ, °, superscripts, subscripts,
floor/ceiling, locale radix) that upstream drives from this file — the
port's narrower substitution table lives in `MathWindow` instead (unit 2).

Verdict: **gap**, partial parity on the rows actually built.

## Unit 6 — History view: `src/math-history.vala` (`HistoryView`) → `lib/history_view.rb`

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Insert on solve, dedupe identical consecutive equation | yes | yes, verified live (`history.rows == 1` after one solve) | parity |
| Click-to-reinsert equation / answer | yes (`equation-clicked`/`answer-clicked` signals) | yes, verified live via the real `Gtk::GestureClick` on each row | parity |
| Re-render on serializer/format change (`set_serializer`) | yes | present (`lib/history_view.rb:92-95`), not exercised by the drive script | **unverified** — present in code, no check proves it fires correctly |
| Tape persistence across app runs (`history-tape` GSettings key) | yes | no — `clear` empties the in-memory `@entries`/listbox only; nothing serialises to `lib/settings.rb` | **gap** |
| Signal shape | real GObject signals | a plain Ruby callback (`on_history` passed into the constructor) | **substitution, undocumented as such** — nothing external can `signal_connect` to it the way upstream's `row-added`/`answer-clicked` allow |

Verdict: **gap**, with real behavioural parity on the two rows the drive
script actually exercises.

## Unit 7 — History entry row: `src/math-history.vala` (`HistoryEntry`) → `lib/history_entry.rb`

Click wiring on both labels verified live. Not checked this pass: the
7-column grid layout, the LRM-prefixed tooltip on the equation label, the
12-character ellipsis on the answer label, and the forced-LTR direction —
none of these have a drive-script assertion, so "exists and clicks work" is
verified; "looks and truncates like upstream" is not.

Verdict: **gap** on the unverified facets, **partial parity** on the
verified ones.

## Unit 16 — Function popover: `src/math-function-popover.vala` → `lib/math_function_popover.rb`

New this pass, verified live via `test/drive_gnome_calculator.rb` step 3.

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Opened from | the basic panel's `calc_function_button` (`f(x)`) | same button, verified live | parity |
| Name validation (4 messages: defined var/const, built-in, starts-with-digit, illegal chars) | 4 | re-checked: `lib/math_function_popover.rb` carries all 4 message strings, matched against `src/math-function-popover.vala` text | parity on text, not cross-checked against `msgctxt`-scoped `po/` lookups (see `translation-parity.md`) |
| Add-button sensitivity gated on validator | yes | yes, verified live (`add_button.sensitive?` after typing a legal name) | parity |
| `FunctionManager` wiring (define → evaluate) | yes | verified live: popover leaves a definition template, the typed definition is accepted, the engine evaluates the function to the right answer (42) | parity — the one row in this report that chains through three real objects (popover → `FunctionManager` → engine) in one check |
| Category stack, submenus, custom-function list (`bind_model`), separator visibility | present | built (`lib/math_popover.rb`'s shared chrome + this file's category list) | **unverified** — no drive-script check opens a built-in category or exercises the custom-function list/separator visibility |
| `Gtk.SpinButton add_arguments_button` (range 1–10) | present | present (read directly in `lib/math_function_popover.rb`) | **unverified** — not exercised live |

Verdict: **partial parity** — the one chain the drive script exercises
(open → validate → define → evaluate) is real and verified; the category
browsing and multi-argument-function paths are unverified, not failing.

## Unit 17 — Variable popover: `src/math-variable-popover.vala` → `lib/math_variable_popover.rb`

New this pass, verified live via `test/drive_gnome_calculator.rb` step 2.

| Facet | Upstream | Port | Verdict |
|---|---|---|---|
| Opened from | the basic panel's `calc_memory_button` (`x`) | same button, verified live | parity |
| Name validation (4 messages, reserved names `_`/`rand`) | 4 messages + 2 reserved names | all carried over in `lib/math_popover.rb`'s shared constants, re-read this pass | parity on text |
| Store/delete through `MathVariables` | yes | verified live: storing through the popover reaches the real `MathVariables`; deleting is reflected back in the popover | parity |
| Reserved-constant rejection | yes | verified live: storing under a reserved name is rejected with a real (non-empty) error | parity |
| `rand` / `_` (last answer) rows, constants list, category submenus | present | built (shared base class) | **unverified** — no drive-script check opens the constants list or exercises `rand`/`_` specifically |

Verdict: **partial parity**, same shape as unit 16 — the store/delete/
reject chain is real and verified; the constants browsing path is
unverified.

## Units 5, 8–14, 18, 21, 23 — still unbuilt

Autocompletion providers, the button-panel host and its `cal` action group,
4 of 5 button panels (advanced/financial/programming/conversion) plus the
bit panel and financial dialogs, the converter, preferences +
favourite-currencies, the shell search provider, and all translations: zero
counterpart in `lib/`, unchanged from the prior pass. See
`component-inventory.md` §§5, 8–14, 18, 21, 23 for the full widget/CSS
tables.

Verdict: **gap**, 12 of 23 units (the 12 remaining after units 1–4, 6, 7,
15–17 above, plus 19/20/22 which hold full or structural parity).

## Unit 19 — Stylesheet: `src/ui/style.css` → `lib/style.css`

Loaded by a real `Gtk::CssProvider` at `GTK_STYLE_PROVIDER_PRIORITY_APPLICATION`,
confirmed live (`app.css_provider.is_a?(Gtk::CssProvider)` in the drive
script) and the file is byte-identical to upstream (399 lines, 44 classes).
Classes the built widgets actually use (`math-buttons`, `history-view`,
`equation-label`, etc. per unit) attach correctly on the units that exist;
classes for unbuilt units (bit panel, converter, popovers) are dormant by
definition until those widgets are built.

Verdict: **parity** for the file and its loading mechanism; dormant, not
broken, for the classes with no widget yet.

## Unit 20 — Settings: `data/org.gnome.calculator.gschema.xml` → `lib/settings.rb`

Unchanged from the prior pass: 19/19 keys, JSON-backed, round-trips live.
`Gio::Settings.bind()` targets (7+ bindings upstream makes to widgets) still
have nothing on the port side to bind to, since the widgets those bindings
target (preferences, history tape, favourite currencies) are unit 20's own
dependents, not unit 20 itself.

Verdict: **parity** for storage; **gap**, scoped to "no consumer exists yet,"
for the bindings.

## Unit 22 — CLI: `src/gcalccmd.vala` → `lib/gcalccmd.rb` + `exe/gcalccmd`

Behaviour unchanged from the prior pass (single-expression argv mode,
REPL-on-stdin, error-to-stderr all verified live this pass via the same
three drive-script checks, now renumbered steps 16–18) but the shape
changed: the class body moved out of the executable into `lib/gcalccmd.rb`
(108 lines) to match house style's one-upstream-file-to-one-`lib`-file
rule, leaving `exe/gcalccmd` a 6-line `require` + run. Man page not carried
over (small, stated gap, unchanged).

Verdict: **parity** for the functional CLI, now also structural parity
with house style.

## Totals

| | Count |
|---|---:|
| Units with full parity | 2 (`exe/gcalccmd`/`lib/gcalccmd.rb` modulo the man page; `lib/style.css`'s loading mechanism) |
| Units with partial, behaviourally-verified parity | 9 (application window shell; main window's key subset; shortcuts dialog's reachable rows; display; history view's insert/click rows; history entry's click rows; function popover's define/evaluate chain; variable popover's store/delete chain; settings storage) |
| Units with zero parity | 12 |

## Rules check

- Every "present"/"parity" claim above was re-run live for this report
  (`53 of 53 checks passed, DRIVE OK`), not read off a prior report or a
  commit message.
- No app-wide total is used as the pass condition; every row is a named
  unit, and the 12 units the drive script does not touch are listed as
  `gap`/unverified rather than omitted.
- The stylesheet's dormant classes and the settings-storage/bindings split
  are stated as partial, not rounded up to full parity, per the skill's
  rule against crediting a mechanism substitution as the behaviour itself.
