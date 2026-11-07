# gnome-calculator — upstream component inventory

Survey of `origin/main` (upstream Vala + blueprint) against `lib/` on the
`ruby` branch, for the full-parity port. No app code written in this step.

Method: `component-identification` skill. Upstream has blueprint files for
every widget tree (`src/ui/*.blp`), so those are the primary inventory; the
matching `src/*.vala` supplies the callbacks, the action groups and the
widgets built at runtime. **The component is the pair**, and both halves are
unioned into one port file below.

## State of the port

**Updated 2026-11-07, re-surveying after commit `e0ed3935` ("Port
math_equation.rb, math_display.rb, basic_button_panel.rb and
math_window.rb"), which landed after the previous version of this file was
written and was never reflected in it.** The four rows below marked
"*(updated)*" are the only status changes from that prior version; nothing
else in `lib/` changed. Re-verified by reading each file directly, not by
trusting the old doc or a commit message.

**Second update, same day, later pass: this file was itself stale.** Two
more commits landed after the paragraph above was written and committed
(`6645ebf4`) and were never reflected here either — `8cf1a973` ("Port
history_entry, history_view and math_shortcuts; wire history into the
window") and `9824569e` ("Expand the drive script: history, shortcuts
dialog, key controller"). Sections 3, 6 and 7 below, and the "Shortcut
items"/history rows in the Totals table, still said "no" for
`lib/history_view.rb`, `lib/history_entry.rb` and `lib/math_shortcuts.rb`
after those three files existed and were wired into `lib/math_window.rb`.
Corrected in place below (search "*(second update)*"); this is exactly the
kind of document drift `accountability-ensurance.md` flags this pass —
see that report.

`lib/` on `ruby` now holds the whole engine, plus a first (partial, basic-mode
only) slice of UI:

| File | Upstream | What it is |
|---|---|---|
| `lib/gnome_calculator.rb` | — | requires the engine in dependency order; deliberately does **not** require the GUI |
| `lib/number.rb` | `lib/number.vala` | arbitrary-precision complex number on BigDecimal + a Rational shadow |
| `lib/serializer.rb` | `lib/serializer.vala` | number formatting |
| `lib/evaluation_budget.rb` | `lib/evaluation-budget.vala` | |
| `lib/equation_lexer.rb` | `lib/equation-lexer.vala` | |
| `lib/equation_parser.rb` | `lib/equation-parser.vala` | |
| `lib/equation.rb` | `lib/equation.vala` | `ErrorCode` and the equation facade |
| `lib/math_equation.rb` *(updated — now exists, 537 lines)* | `lib/math-equation.vala` | the equation buffer every display/button panel binds to. Upstream subclasses `GtkSource.Buffer`; this port wraps a plain `Gtk::TextBuffer` instead because neither gtksourceview4 nor gtksourceview5 load in this fork's toolchain (recorded in `FINDINGS.md`). The answer-highlighting tag, undo-by-snapshot history, and the insert/solve/clear state machine are carried over; GtkSource-specific features (syntax highlighting, style-scheme theming) are not, by the same toolchain gap. |
| `lib/math_function.rb` | `lib/math-function.vala` | |
| `lib/function_manager.rb` | `lib/function-manager.vala` | |
| `lib/math_variables.rb` | `lib/math-variables.vala` | |
| `lib/currency_provider.rb` | `lib/currency-provider.vala` | |
| `lib/currency.rb` | `lib/currency.vala` | |
| `lib/providers/{boc,ecb,imf,unt}_provider.rb` | `lib/providers/*.vala` | |
| `lib/unit.rb` | `lib/unit.vala` | |
| `lib/financial.rb` | `lib/financial.vala` | the ten financial functions |
| `lib/settings.rb` | `data/org.gnome.calculator.gschema.xml` | the same 19 keys and defaults, JSON-backed under `XDG_CONFIG_HOME` instead of GSettings |
| `lib/math_display.rb` *(updated — now exists, 95 lines)* | `src/math-display.vala` + `src/ui/math-display.blp` | **partial**: scrolled `Gtk::TextView` (not `GtkSource.View`, same toolchain reason as above) bound to `MathEquation#buffer`, a flat backspace button, and a status/error label (`info_view`). Missing against row 4 of this file's own section 4 below: the `Gtk.EventControllerScroll`, the loading spinner, the on-screen-keyboard-aware backspace visibility, and the whole key-press substitution table (×, ÷, √, π, τ, °, superscripts, subscripts, floor/ceiling, locale radix) — key handling instead lives in `MathWindow`'s own `Gtk::EventControllerKey`, a narrower set (digits, 4 operators, Enter/Escape/Backspace/Delete/period). |
| `lib/basic_button_panel.rb` *(updated — now exists, 376 lines)* | `src/buttons-basic.vala` + `src/ui/buttons-basic.blp` | **partial**: the basic-mode grid of digit/operator/function buttons. Not yet verified against section 10's detailed widget/CSS table below (recorded there as a follow-up for `component-parity`, not re-litigated here) — built through the `cal` action group or through direct `MathEquation` calls is the open question for that check. |
| `lib/gnome_calculator/application.rb` *(updated — no longer a placeholder)* | `src/gnome-calculator.vala` | **partial**: a real `Gtk::Application` (not `Adwaita::ApplicationWindow`'s application type — see `FINDINGS.md`) that builds `MathWindow`, presents it on `activate`, and loads `lib/style.css` at `GTK_STYLE_PROVIDER_PRIORITY_APPLICATION`. Still installs **no actions** (`app.new-window`, `app.help`, `app.about`, `app.quit` all absent), no accelerators, no CLI option handling (`--mode`, `--solve`, `--equation`, `--version`), no multi-window support, and neither of the two dialogs section 1 below lists (`Adw.AboutDialog`, the "Close All?" `Adw.AlertDialog`). |
| `lib/math_window.rb` *(updated — now exists, 111 lines)* | `src/math-window.vala` + `src/ui/math-window.blp` | **partial, by its own header comment**: an `Adwaita::ApplicationWindow` with an `Adwaita::ToolbarView`/`HeaderBar` over the display and the basic button panel, plus a hand-rolled `Gtk::EventControllerKey` for digit/operator/Enter/Escape/Backspace/Delete/period. Everything else in section 2 below is absent: the mode-switch stack (and so every mode but basic), the history view, the converter, every `win.*` action, both menu models, the undo/redo/back buttons, and the Shift/Ctrl+B/O/D/H key handling. |
| `lib/gnome/calculator/rb/version.rb` | — | gem version |
| `exe/gcalccmd` | `src/gcalccmd.vala` | the CLI, working |
| `exe/gnome-calculator` | — | `GnomeCalculator::Application.new.build.run` |

So: **the engine is fully ported; the UI has its first vertical slice (basic
mode only) and nothing past it.** `gcalccmd` is user-facing and complete.
Every item in sections 1–2 marked "no action group installed" above is a real
gap, not a simplification — the window and application objects that exist
build real widgets but wire none of upstream's `win.*`/`app.*`/`cal.*`
actions, menus, or accelerators.

## Totals

| | Upstream | Port |
|---|---:|---:|
| UI source files (`src/*.vala`) | 14 | 4 of 14, each partial (`gnome-calculator.vala`, `math-window.vala`, `math-display.vala`, `buttons-basic.vala`) |
| Blueprint files (`src/ui/*.blp`) | 14 | 0 (by design — house style builds in Ruby) |
| Component units (template / named root) | 28 | 4, each partial |
| Button widgets across the five panels | ~148 | ~14 (basic panel only; not yet counted against upstream's table in section 10) |
| Distinct CSS classes in `style.css` | 44 | not yet audited rule-by-rule against `lib/style.css` — flag for `component-parity` |
| GSettings keys | 19 | 19 (JSON-backed, `lib/settings.rb`) |
| Menu models | 4 (`window_menu`, `primary_menu`, `context_menu_model`, `base_menu`, `word_size_menu`) | 0 |
| Shortcut items in the shortcuts dialog | 43 (`$AdwShortcutsItem` count in `src/ui/math-shortcuts.blp`, not the 44 this table previously said — recounted this pass) across 5 sections | **38** *(second update — `lib/math_shortcuts.rb` now exists; missing the "Switch to Keyboard Mode (alt.)" row and all 4 floor/ceiling ltr/rtl rows; see `component-parity.md`)* |
| `po/` languages | 101 | not yet audited — see `translation-parity` |
| `win.`/`app.`/`cal.` actions installed anywhere in `lib/` | ~30+ across the app and window action groups | **0** — `grep -rn "add_action\|install_action" lib/` returns nothing |
| Engine files (`lib/*.vala`, the maths) | 22 | 20 of 20 in scope — **complete**, `math-equation.vala` no longer outstanding |

---

## Components, in the order a user meets them

### 1. `src/gnome-calculator.vala` — the application

→ **`lib/gnome_calculator/application.rb`** · application · **present, partial** *(updated — builds a real `MathWindow` and loads `style.css`; still installs none of the actions/dialogs below)*

`Calculator : Adw.Application`, `NON_UNIQUE` flags, resource base path
`/org/gnome/calculator`.

| Facet | Detail |
|---|---|
| Actions (`app.`) | `new-window`, `help`, `about`, `quit` |
| Accels set here | `win.mode::{basic,advanced,financial,programming,keyboard,conversion}` (`<control><alt>{B,A,F,P,K/T,C}`), `win.copy`, `win.paste`, `win.undo`, `win.redo`, `win.clear` (`<control>Escape`), `win.preferences` (`<control>comma`), `win.close` (`<control>W`), `app.quit`, `app.new-window`, `app.help` (F1), `app.shortcuts` (`<control>question`) |
| Startup | `GtkSource.init`, `Settings("org.gnome.calculator").delay()`, first window, `CurrencyManager.refresh_async`, binds `favorite-currencies` |
| Shutdown | persists `button-mode`, `unit-category`, `source-units`, `target-units`, `base`, `window-maximized`, `window-size` |
| CLI options | `--mode`, `--solve`, `--equation`, `--version` (`handle_local_options` solves headlessly and prints) |
| Multi-window | `new-window` opens another `MathWindow` against the same settings |

Two dialogs live in this file and are their own components:

| Component | Target | Kind | Present |
|---|---|---|---|
| `Adw.AboutDialog` — app name/icon/version, developers (5), documenters, GPL-3.0, website, issue URL, translator credits, plus an added legal section "Exchange Rate Data Providers" listing the provider links | `lib/about_dialog.rb` | dialog | no |
| `Adw.AlertDialog` "Close All?" — responses `cancel` / `close-all` (destructive), shown by `app.quit` only when more than one window is open | `lib/close_all_dialog.rb` | dialog | no |

### 2. `src/math-window.vala` + `src/ui/math-window.blp` — the main window

→ **`lib/math_window.rb`** · window · **partial** *(updated — now exists: header bar, display, basic button panel, a hand-rolled key controller; everything else in the table and action list below is still missing)*

`MathWindow : Adw.ApplicationWindow`, `height-request: 616`, title "Calculator".

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` | 1 | — | — | `top-bar-style: raised` |
| `Adw.HeaderBar` `headerbar` | 1 | — | — | |
| `Gtk.MenuButton` `menu_button` | 1 | — | menu `window_menu` | in `[title]`; `always-show-arrow`, `can-shrink`, tooltip "Mode Selection"; label set per mode to Basic/Advanced/Financial/Programming/Keyboard/Conversion |
| `Gtk.Button` `undo_button` | 1 | — | `win.undo` | hidden in conversion mode |
| `Gtk.Button` `redo_button` | 1 | — | `win.redo` | hidden in conversion mode |
| `Gtk.Button` `back_button` | 1 | — | `win.back` | tooltip "Financial"; shown only after the Financial panel's currency-conversion button |
| `Gtk.MenuButton` `primary_menu_button` | 1 | — | menu `primary_menu`, `primary: true` | `[end]`, "Main Menu" |
| `Adw.Clamp` | 1 | — | — | `maximum-size`/`tightening-threshold` 700px |
| `Gtk.Box` `display_box` | 1 | `card`, `display-container`, + `programming` (dynamic, programming mode only) | — | hidden in conversion mode |
| `$HistoryView history` | 1 | — | `row-added` | |
| `$MathDisplay _display` | 1 | — | — | `equation` bound to the template |
| `$MathConverter _converter` | 1 | `card`, `display-container` | — | visible only in conversion mode |
| `$MathButtons _buttons` | 1 | — | — | hidden in keyboard mode |
| `Gtk.EventControllerKey` | 1 | — | `key-pressed`, `key-released` | Shift toggles `buttons.inverse`; in programming mode Ctrl+B/O/D/H set base 2/8/10/16 |

Window actions (`win.`): `copy`, `paste`, `undo`, `redo`, `mode` (`"s"`,
default `"basic"`), `clear`, `back`, `preferences`, `close`, plus
`number-format` created from GSettings. `undo`/`redo` enabled from
`equation.has_undo_action` / `has_redo_action`; `copy` and `clear` disabled in
conversion mode. Settings bound to the equation: `number-format`, `accuracy`,
`show-zeroes`, `show-thousands`, `angle-units`, `word-size`.

Behaviour that is a component in its own right but has no separate file:

- **History tape persistence** — `save_history_tape` / `restore_history_tape` /
  `clear_history_tape` serialise the history rows to the `history-tape`
  GSettings key (`a(ss)`) on close and replay them on an idle callback at
  startup.
- **Equation history navigation** — Alt+Left / Alt+Right walk `forked_row_index`
  through the history view, with `saved_eq` holding the in-progress equation
  and `keynav_failed` at either end.
- **`devel` CSS class** on development builds.

Two menu models sit in the same blueprint:

| Component | Items | Target | Kind | Present |
|---|---|---|---|---|
| `menu window_menu` | 6 — `win.mode` targets basic / advanced / financial / programming / keyboard / conversion | `lib/math_window.rb` | menu | no |
| `menu primary_menu` | `app.new-window`; `win.clear` (hidden-when action-disabled); a "Result Format" section with `win.number-format` targets automatic / fixed / scientific / engineering; a help section with `win.preferences`, `app.shortcuts`, `app.help`, `app.about` | `lib/math_window.rb` | menu | no |

### 3. `src/ui/math-shortcuts.blp` — keyboard shortcuts dialog

→ **`lib/math_shortcuts.rb`** · dialog · **partial** *(second update — now
exists: a plain `Adwaita::Dialog` over a scrolled list of label/accelerator
rows, built because the Ruby bindings reject `Adwaita::ShortcutsItem`'s
constructor — see `FINDINGS.md`. Not reached by `app.shortcuts`, because no
such action exists (see §1); reached instead by a button on the header bar.
38 of 43 items present — missing the alt keyboard-mode binding and all 4
floor/ceiling rows, see `component-parity.md`. No `msgctxt` is applied, so
upstream's `C_("shortcuts dialog", …)` translations do not match the port's
plain `_()` calls even where the English text is identical — see
`translation-parity.md`.)*

A standalone `$AdwShortcutsDialog` with no backing source file; reached by
`app.shortcuts`. Five `$AdwShortcutsSection`s, 43 `$AdwShortcutsItem`s
(recounted this pass; this table previously said 44):

| Section | Items |
|---|---:|
| General | 8 (new window, close window, quit, help, F10 open menu, preferences, shortcuts, clear history) |
| Switching Modes | 7 (the six modes, keyboard twice: `<control><alt>k` and `<control><alt>t`) |
| Programming Mode | 4 (Ctrl+B/O/D/H → binary/octal/decimal/hex) |
| Keyboard Entry | 17 (×, ÷, ², √, ⁻¹, π, τ, °, floor/ceiling in ltr and rtl, scientific, sub/superscript digits, superscript minus) |
| Equation | 8 (copy, paste, undo, redo, previous/next equation, clear, factorize) |

### 4. `src/math-display.vala` + `src/ui/math-display.blp` — the equation display

→ **`lib/math_display.rb`** · widget · **partial** *(updated — now exists: scrolled `Gtk::TextView`, backspace button, status label; the scroll controller, spinner, OSK-aware backspace, and the key-substitution table below are still missing)*

`MathDisplay : Gtk.Box`, CSS name `mathdisplay`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ScrolledWindow` `display_scrolled` | 1 | `display-scrolled` | — | `vscrollbar-policy: never` |
| `GtkSource.View` `source_view` | 1 | `sourceview` (from the stylesheet) | `key-pressed` (capture), `move-cursor` (after), `paste-clipboard` | name `displayitem`, margins 14/14, `input-hints: no-emoji\|no-spellcheck\|inhibit-osk`, buffer is the `MathEquation` |
| `Gtk.EventControllerScroll` | 1 | — | `scroll` | both axes |
| `Gtk.Button` `backspace_button` | 1 | `circular`, `flat` | `clicked` → `backspace_cb` | hidden when the on-screen keyboard is enabled (keyboard mode) |
| `Adw.Spinner` `spinner` | 1 | — | — | shown while solving |
| `Gtk.TextView` `info_view` | 1 | `info-view` | — | errors, status, base label |

Key handling in `key_press_cb` is a large component of its own: Escape clears
(or closes the completion popup), Ctrl+Delete clears, keypad keys are treated
as digits with numlock off, `=`/Enter solves unless the text is a bare variable
name or a function definition, `.`/`,`/KP_Decimal insert the locale radix, and
a long substitution table maps typed characters to `×`, `÷`, `√`, `π`, `τ`, `°`,
superscripts, subscripts and the floor/ceiling brackets.

### 5. `src/math-display.vala` (lines 560–877) — autocompletion providers

→ **`lib/completion_providers.rb`** · popup · **no**

`CompletionProposal`, abstract `CompletionProvider`, and four concrete
providers wired into `GtkSource.Completion`: `builtin`, `function`, `currency`,
`favorite`, `variable`. Which ones are active is driven by the
`enabled-completions` GSettings key; `select_on_show` is on, and the
`completion_visible` flag changes what Escape does in the display.

### 6. `src/math-history.vala` (`HistoryView`) + `src/ui/history-view.blp` — the history tape

→ **`lib/history_view.rb`** · widget · **partial** *(second update — now
exists: `Gtk::ScrolledWindow` → `Gtk::Viewport` → `Gtk::ListBox` of
`HistoryEntry` rows, `insert_entry`/`load_entry`/`clear`/`set_serializer`/
`scroll_bottom` all present and wired into `lib/math_window.rb`. The
`row-added` signal from the table below is not a real GObject signal here —
it is a plain Ruby callback (`@equation.on_history { … }` in
`MathWindow#initialize`) — which is a faithful behavioural substitute but
means nothing external can connect to it the way upstream's signal allows.
History-tape persistence (`history-tape` GSettings key, save/restore across
runs) is not built: `HistoryView#clear` empties the in-memory list only.)*

`HistoryView : Adw.Bin`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ScrolledWindow` `scrolled_window` | 1 | `history-view` | — | `hscrollbar-policy: never` |
| `Gtk.Viewport` `viewport` | 1 | — | — | `scroll-to-focus` |
| `Gtk.ListBox` `listbox` | 1 | — | — | `selection-mode: none`, `tab-behavior: item`, `valign: end` |
| `HistoryEntry` rows | *repeater* | — | per-row `answer-clicked`, `equation-clicked` | one per solved equation; `insert_entry` from a `Number`, `load_entry` from saved strings |

Own signals: `answer-clicked`, `equation-clicked`, `row-added` (which triggers
`scroll_bottom`). `set_serializer` re-renders every row when the number format
changes. `clear` empties it (and is what `win.clear` calls).

### 7. `src/math-history.vala` (`HistoryEntry`) + `src/ui/history-entry.blp` — one history row

→ **`lib/history_entry.rb`** · row · **partial** *(second update — now
exists: a `Gtk::ListBoxRow` with equation/`=`/answer labels and a
`Gtk::GestureClick` per clickable label, verified live by
`test/drive_gnome_calculator.rb` ("clicking the equation label re-inserts
the equation text" / "clicking the answer label re-inserts the answer
text"). The 7-column `Gtk.Grid` layout, the LRM-prefixed tooltip, the
12-character answer ellipsis and the forced-LTR direction are not verified
against upstream row-by-row in this pass — flagged for `component-parity`.)*

`HistoryEntry : Gtk.ListBoxRow`, CSS `history-entry`, `focus-on-click: false`.
Direction forced to LTR on the grid and both labels.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Grid` `grid` | 1 | — | — | column-homogeneous, 7 columns |
| `Gtk.Label` `equation_label` | 1 | `equation-label` | `Gtk.GestureClick` → `equation_clicked_cb` | wraps, xalign 0, spans columns 0–3, tooltip with LRM prefix |
| `Gtk.Label` `equation_symbol` | 1 | `equation-symbol`, `dimmed` | — | literal `=`, column 4 |
| `Gtk.Label` `answer_label` | 1 | `answer-label` | `Gtk.GestureClick` → `answer_clicked_cb` | ellipsized, max 12 chars, columns 5–6 |
| `Gtk.GestureClick` | 2 | — | `pressed` | one per clickable label |

`redisplay(serializer)` re-renders the answer, except for rows restored from the
settings tape, which hold display strings and no `Number`.

### 8. `src/math-converter.vala` + `src/ui/math-converter.blp` — the unit/currency converter

→ **`lib/math_converter.rb`** · widget · **no**

`MathConverter : Gtk.Box`, CSS name `mathconverter`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.DropDown` `category_combo` | 1 | — | `notify::selected` | unit categories |
| `Gtk.Box` `converter_box` | 1 | — | — | visible bound to `box-visible` |
| `Gtk.TextView` `from_entry`, `to_entry` | 2 | — | `notify::has-focus`, buffer `changed` | `wrap-mode: char`, no emoji/spellcheck, inhibit OSK |
| `Gtk.DropDown` `from_combo`, `to_combo` | 2 | — | `notify::selected` (to only) | `search-match-mode: substring`; expression switches between `display_name`, `name` and both per the `currency-display` setting; favourites sorted to the top; `Gtk.SignalListItemFactory` list factory for currencies |
| `Gtk.GestureClick` | 2 | — | `pressed` → context menu | button 0, exclusive, capture |
| `Gtk.ShortcutController` + 2 `Gtk.Shortcut` | 2 | — | `Menu`, `<Shift>F10` → `context-menu.popup` | one controller per entry |
| `Gtk.PopoverMenu` `from_context_menu`, `to_context_menu` | 2 | — | — | `has-arrow: false`, model `context_menu_model` |
| `Gtk.EventControllerKey` | 2 | — | `key-pressed` (capture) | digit/radix/`°` entry |
| `Gtk.Stack` `status_stack` | 1 | — | — | visible when `box-visible` is false |
| `Adw.StatusPage` | 1 | `compact` | child label `activate-link` → `refresh_rates` | **error state**: "Exchange Rates Not Loaded", with a markup link "Refresh rates or change refresh interval in preferences" |
| `Adw.Spinner` | 1 | — | — | **loading state**, page 1 of the stack |

Action group `context-menu`: `popup`, `copy`, `paste`. Own signal `changed`.
Public surface used by the window and the conversion panel: `source_units`,
`target_units`, `set_category`, `get_category`, `get_focus_unit`,
`insert_text`, `insert_numeric_point`, `insert_dms`, `change_sign`, `clear`,
`swap_units`, `backspace`, `paste`, `refresh_rates`, `get_conversion`.

| Component | Items | Target | Kind | Present |
|---|---|---|---|---|
| `menu context_menu_model` | 2 — `context-menu.copy`, `context-menu.paste` | `lib/math_converter.rb` | menu | no |

### 9. `src/math-buttons.vala` — the button panel host

→ **`lib/math_buttons.rb`** · widget · **no**

`MathButtons : Adw.Bin` holding a `Gtk.Stack` `panel_stack`
(non-homogeneous both ways) that lazily instantiates one panel per mode.
Defines `enum ButtonMode { BASIC, ADVANCED, FINANCIAL, PROGRAMMING, KEYBOARD,
CONVERSION }`, properties `mode`, `programming_base`, `inverse`, and the signal
`currency_conversion`.

The **`cal` action group** installed here is what every button in every panel
targets, and none of its names appear as literals in a scan of the port side:

`insert-general "s"`, `insert-digit "i"`, `insert-brackets "(ss)"`,
`insert-alpha "s"`, `insert-function "s"`, `insert-symbol-before "s"`,
`insert-symbol-after "s"`, `insert-exponent "s"`, `insert-numeric-point`,
`subtract`, `square`, `nth-root`, `logarithm`, `undo`, `clear`, `solve`,
`set-number-mode "s"` (stateful, default `'normal'`).

Announces the result through `Gtk.AccessibleAnnouncementPriority.MEDIUM` when a
solve came from a button.

### 10. `src/buttons-basic.vala` + `src/ui/buttons-basic.blp` — Basic panel

→ **`lib/basic_button_panel.rb`** · panel · **partial** *(updated — now exists, 376 lines; not yet checked widget-by-widget and CSS-class-by-CSS-class against the table below — that check belongs to `component-parity`, not restated here)*

`BasicButtonPanel : Adw.Bin`, one `Gtk.Grid` `basic` forced to LTR.
10 `Gtk.Button`, 2 `Gtk.ToggleButton`, 2 `Gtk.MenuButton`.
CSS: `math-buttons`, `buttons`, `number-button`, `operator-button`,
`clear-button`, `function-button`, `parenthesis-button`, `percent-button`,
`numeric-point-button`, `suggested-action`.
The radix button's label comes from `equation.serializer.get_radix()`;
`calc_memory_button` gets a `MathVariablePopover`, `calc_function_button` a
`MathFunctionPopover`.

### 11. `src/buttons-advanced.vala` + `src/ui/buttons-advanced.blp` — Advanced panel

→ **`lib/advanced_button_panel.rb`** · panel · **no**

`AdvancedButtonPanel : Adw.BreakpointBin` with an `Adw.Breakpoint`, an
`Adw.MultiLayoutView` with 4 `Adw.Layout`/`Adw.LayoutSlot`s, an `Adw.Carousel`
+ `Adw.CarouselIndicatorDots` for the narrow layout, and a `Gtk.SizeGroup`
across the `basic` and `advanced` grids.
44 `Gtk.Button`, 3 `Gtk.ToggleButton`, 2 `Gtk.MenuButton`, 2 `Gtk.Grid`.
Extra CSS: `accent` (on the inverse modifier).
Own `cal` actions: `factorize`, `set-angle-units`.
`calc_angle_units_button` cycles Rad/Deg/Grad with label and tooltip
"Angle Unit: %s" (Radians/Degrees/Gradians); `inverse` is bound bidirectionally
to `calc_inverse_modifier_button.active`; the carousel scrolls to page 1 on map
and on mode change; all five sub-widgets forced to LTR.

### 12. `src/buttons-financial.vala` + `src/ui/buttons-financial.blp` — Financial panel

→ **`lib/financial_button_panel.rb`** · panel · **no**

Same `Adw.BreakpointBin` / `Adw.MultiLayoutView` / `Adw.Carousel` shape as
Advanced, plus a third `finc_buttons` grid.
48 `Gtk.Button`, 3 `Gtk.ToggleButton`, 2 `Gtk.MenuButton`, 3 `Gtk.Grid`.
Own `cal` actions: `launch-finc-dialog "s"`, `currency-conversion` (switches to
conversion mode, sets category `currency`, emits `currency_conversion` so the
window shows its back button).

→ **`lib/financial_dialogs.rb`** · dialogs · **no**

Ten `Adw.Dialog`s, each `Adw.ToolbarView` + `Adw.HeaderBar` +
`Adw.PreferencesPage` + `Adw.PreferencesGroup` with 2–4 `Adw.EntryRow`s
(30 rows in total) and a calculate button:

| Dialog | Entry rows |
|---|---|
| `ctrm_dialog` | `ctrm_pint`, `ctrm_fv`, `ctrm_pv` |
| `ddb_dialog` | `ddb_cost`, `ddb_life`, `ddb_period` |
| `fv_dialog` | `fv_pmt`, `fv_pint`, `fv_n` |
| `gpm_dialog` | `gpm_cost`, `gpm_margin` |
| `pmt_dialog` | `pmt_prin`, `pmt_pint`, `pmt_n` |
| `pv_dialog` | `pv_pmt`, `pv_pint`, `pv_n` |
| `rate_dialog` | `rate_fv`, `rate_pv`, `rate_n` |
| `sln_dialog` | `sln_cost`, `sln_salvage`, `sln_life` |
| `syd_dialog` | `syd_cost`, `syd_salvage`, `syd_life`, `syd_period` |
| `term_dialog` | `term_pmt`, `term_fv`, `term_pint` |

Each row is reset to `"0"` when the dialog opens, Enter advances to the next
row and the last row calculates, and a `Gtk.EventControllerFocus` on every row
(**10 repeaters, 30 live controllers**) normalises blank or sign-only text back
to `"0"` on leave.

### 13. `src/buttons-programming.vala` + `src/ui/buttons-programming.blp` — Programming panel

→ **`lib/programming_button_panel.rb`** · panel · **no**

Largest unit upstream (2650 blueprint lines). `Adw.BreakpointBin` +
`Adw.Breakpoint` + `Adw.MultiLayoutView` (6 `Adw.LayoutSlot`s) +
`Adw.Carousel` + `Adw.CarouselIndicatorDots`, 38 `Gtk.Button`,
4 `Gtk.MenuButton`, 3 `Gtk.ToggleButton`, 4 `Gtk.Grid`, a `Gtk.SizeGroup`.
Extra CSS: `bit-panel`, `bit-toggle-button`, `bit-toggle-separator`,
`bit-marker-label`, `card`, `flat`, `dimmed`, `accent`, `title-1`,
`action-dialog`, `action-button`.
Own `cal` actions: `set-base "s"`, `set-word-size "s"`, `toggle-bit "i"`,
`insert-character`.

The **bit panel** is a component inside this file: a `Gtk.Grid` of 64
`Gtk.Button` bit toggles plus marker labels, re-laid-out between a wide and a
narrow arrangement by `set_bit_panel_wide` / `set_bit_panel_narrow` (breakpoint
callbacks that move grid children), with per-bit sensitivity from
`equation.word_size`, dynamic `accent`/`dimmed` classes on the IEEE-754 sign
and exponent bits for 32- and 64-bit floats, and a `Gtk.CssProvider` loaded at
runtime in `size_allocate` to scale `.bit-toggle-separator` margin to
`width / 40`. Also writes `equation.base_label` with the octal/decimal/hex
renderings of the current value.

| Component | Detail | Target | Kind | Present |
|---|---|---|---|---|
| `Adw.Dialog character_code_dialog` | CSS `action-dialog`; `Adw.PreferencesPage` with a `title-1` label, `Adw.EntryRow character_entry` (max-length 1, activates-default), `Adw.ComboRow convert_to_combo` with a `Gtk.StringList` of "Unicode Code Point" / "UTF-8 Encoding" / "UTF-16 Encoding", and cancel/insert buttons (`action-button`, `suggested-action`) | `lib/character_code_dialog.rb` | dialog | no |
| `menu base_menu` | 4 — `cal.set-base` targets 2 / 8 / 16 / 10, labelled Binary / Octal / Decimal / Hexadecimal | `lib/programming_button_panel.rb` | menu | no |
| `menu word_size_menu` | 4 — `cal.set-word-size` targets 8 / 16 / 32 / 64 | `lib/programming_button_panel.rb` | menu | no |

### 14. `src/buttons-conversion.vala` + `src/ui/buttons-conversion.blp` — Conversion panel

→ **`lib/conversion_button_panel.rb`** · panel · **no**

`ConversionButtonPanel : Adw.Bin`. 8 `Gtk.Button`, 3 `Gtk.Grid`
(`basic`, `dec_buttons`, `hex_buttons`), a `Gtk.Stack` `calc_mutable_button`
whose 5 pages swap the mutable button per category
(angle-degrees/dms → page 0, angle-radian → 1, temperature or numberbase → 2,
currency → 3, otherwise → 4), and 15 hex buttons whose sensitivity follows the
selected number base.
Own `cal` actions: `insert-general "s"`, `insert-digit "i"`,
`insert-numeric-point`, `insert-dms`, `change-sign`, `rate-details`, `clear`,
`swap-units`, `backspace`.

| Component | Detail | Target | Kind | Present |
|---|---|---|---|---|
| `Adw.PreferencesDialog rate_details_dialog` | "Exchange Rate Details", content-width 462; two `Adw.PreferencesGroup`s (`from_group`, `to_group`) each with `Adw.ActionRow` "Updated" and "Source" (CSS `property`, `adw-external-link-symbolic` suffix image, `activated` → `Gtk.UriLauncher` on the provider attribution link); a third group with an `Adw.ButtonRow` "_Refresh Rates". Rows fall back to "Not Available" and the Source row hides when the unit is not a currency | `lib/rate_details_dialog.rb` | dialog | no |

### 15. `src/math-popover.vala` — popover base class

→ **`lib/math_popover.rb`** · popover base · **no**

Abstract `MathPopover<T> : Gtk.Popover`. Holds the name-entry validation
pipeline (spaces → underscores, `error` CSS class and
`Gtk.AccessibleState.INVALID` on the entry, error label inside a
`Gtk.Revealer`, add button sensitivity), the sorted `ListStore`, and two row
factories:

- `make_item_row` — a `Gtk.Box` with a wrapping markup `Gtk.Label` plus, when
  applicable, a flat `document-edit-symbolic` "Edit" button and a flat
  `user-trash-symbolic` "Delete" button. **A repeater: one call site per item.**
- `make_category_row` — a `Gtk.Box` with a label and a
  `go-next-symbolic` `Gtk.Image` (`forward-arrow`), returning a new
  `Gtk.ListBox` submenu whose first row is a `Gtk.CenterBox` back button
  (`back-button`, `back-arrow`, `go-previous-symbolic`).

Reserved names (`_`, `rand`) and the operator list (`mod`, `and`, `nand`, `or`,
`nor`, `xor`, `xnor`, `nxor`, `not`, `in`, `to`) live here.

### 16. `src/math-function-popover.vala` + `src/ui/math-function-popover.blp` — functions popover

→ **`lib/math_function_popover.rb`** · popover · **no**

`MathFunctionPopover : MathPopover<MathFunction>`, CSS `math-popover`.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Stack` `stack` | 1 | — | — | `slide_left_right`, `interpolate-size`, one page per built-in category |
| `Gtk.ScrolledWindow` `function_list_scrolled` | 1 | `undershoot-bottom` | — | max-content-height 250, width-request 250 |
| `Gtk.ListBox` `built_in_list` | 1 | `category-list` | `row-activated` → `open_submenu_cb` | one category row per `FunctionManager.FUNCTION_CATEGORIES` (*repeater*) |
| `Gtk.Separator` `separator` | 1 | — | — | visible only when custom functions exist |
| `Gtk.ListBox` `custom_list` | 1 | — | `row-activated` → `insert_function_cb` | `bind_model` over the custom-function store (*repeater*); hidden when empty |
| `Gtk.ScrolledWindow` per category submenu | *repeater* | — | — | max-content-height 336, added to the stack |
| `Gtk.Entry` `name_entry` | 1 | + `error` (dynamic) | `activate` → `add_function_cb` | placeholder "Function name", a11y error-message → `error_label` |
| `Gtk.SpinButton` `add_arguments_button` | 1 | — | — | range 1–10, tooltip "Select no. of arguments" |
| `Gtk.Button` `add_button` | 1 | — | `clicked` → `add_function_cb` | `list-add-symbolic`, "Add function", insensitive until the name validates |
| `Gtk.Revealer` + `Gtk.Label` `error_label` | 1 | — | — | reveals on a validation error |

Validation messages: "Can not use defined variable or constant names", "Can not
use built-in function or operator names", "Function name can not start with a
digit", "Function name can only contain digits, letters and underscores".
Tracks `function_added` / `function_edited` / `function_deleted` from
`FunctionManager`.

### 17. `src/math-variable-popover.vala` + `src/ui/math-variable-popover.blp` — variables popover

→ **`lib/math_variable_popover.rb`** · popover · **no**

`MathVariablePopover : MathPopover<MathVariable>`, CSS `math-popover`, plus the
plain `MathVariable` value class (name, value, is_custom, comparators).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Stack` `stack` | 1 | — | — | one page per constant category |
| `Gtk.ScrolledWindow` `variable_list_scrolled` | 1 | `undershoot-bottom` | — | max-content-height 290 |
| `Gtk.ListBox` `variable_list` | 1 | — | `row-activated` → `insert_variable_cb` | `bind_model`; includes `rand` and `_` (last answer, updated from the history signal) |
| `Gtk.Separator` | 1 | — | — | |
| `Gtk.Label` "Constants" | 1 | `dimmed` | — | |
| `Gtk.ListBox` `constant_list` | 1 | `category-list` | `row-activated` → `open_submenu_cb` | one row per `Parser.CONSTANT_CATEGORIES` (*repeater*) |
| `Gtk.ListBox` submenu per category | *repeater* | `category-list` | `row-activated` → `insert_constant_cb` | each constant row is a `Gtk.Box` with a name label and a `dimmed` symbol label |
| `Gtk.Entry` `name_entry` | 1 | + `error` (dynamic) | `activate` → `store_variable_cb` | placeholder "Variable name" |
| `Gtk.Button` `add_button` | 1 | — | `clicked` → `store_variable_cb` | `document-save-symbolic`, "Store value into existing or new variable" |
| `Gtk.Revealer` + `Gtk.Label` `error_label` | 1 | — | — | |

Validation messages: "Can not use defined function or operator names", "Can not
use built-in variable or constant names", "Variable name can not start with a
digit", "Variable name can only contain digits, letters and underscores".

### 18. `src/math-preferences.vala` + `src/ui/math-preferences.blp` — preferences

→ **`lib/math_preferences_dialog.rb`** · dialog · **no**

`MathPreferencesDialog : Adw.PreferencesDialog`, reached by `win.preferences`.

| Widget | × | Notes |
|---|---:|---|
| `Adw.PreferencesPage` | 1 | |
| `Adw.PreferencesGroup` "General" | 1 | |
| `Adw.SpinRow` `row_decimals` | 1 | "Number of _Decimals", `Gtk.Adjustment adjustment_decimals` upper 100, step 1, page 10, default 9; bound to `accuracy` |
| `Adw.SwitchRow` `row_trailing_zeroes` | 1 | "Trailing _Zeroes" → `show-zeroes` |
| `Adw.SwitchRow` `row_thousands_separators` | 1 | "_Group Digits" → `show-thousands` |
| `Adw.ComboRow` `row_angle_units` | 1 | "_Angle Units", `Adw.EnumListModel(AngleUnit)` → Degrees / Radians / Gradians |
| `Adw.ComboRow` `row_word_size` | 1 | "_Word Size", enum 8/16/32/64-bit |
| `Adw.PreferencesGroup` "Currency Conversion" | 1 | |
| `Adw.ComboRow` `row_refresh_interval` | 1 | "E_xchange Rate Refresh Interval" → Never / Daily / Weekly |
| `Adw.ComboRow` `row_currency_display` | 1 | "_Currency Display" → Currency Code / Currency Name / Both |
| `Adw.ComboRow` `row_currency_completion` | 1 | "_Show Currencies in Auto-Completion List", `Gtk.StringList` All / Favorite Only / None, mapped onto the `enabled-completions` key |
| `Adw.ActionRow` `row_favorite_currencies` | 1 | "_Favorite Currencies", `go-next-symbolic` suffix `Gtk.Image`, pushes the subpage |

Also carries the `WordSize` and `RefreshInterval` enums and the `devel` CSS
class on development builds.

→ **`lib/favorite_currencies_page.rb`** · page · **no**

`Adw.NavigationPage page_favorite_currencies` "Favorite Currencies", a
standalone named root in the same blueprint:

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` + `Adw.HeaderBar` + `Adw.Clamp` | 1 each | — | — | |
| `Gtk.SearchEntry` `search_entry` | 1 | `currency-search-entry` | `search-changed` | placeholder "Search currencies" |
| `Gtk.Stack` `search_stack` | 1 | — | — | page 0 the list, page 1 the empty state |
| `Adw.PreferencesPage` + `Adw.PreferencesGroup group_favorite_currencies` | 1 each | — | — | |
| `Adw.SwitchRow` per currency | *repeater* | — | `notify::active` | one per unit in the `currency` category, title = display name, subtitle = code; two-way with the `favorite-currencies` key |
| `Adw.StatusPage` | 1 | — | — | **empty state**: `edit-find-symbolic`, "No Results Found", "Try a different search" |

### 19. `src/ui/style.css` — the stylesheet

→ **`lib/style.css`** (loaded by a `Gtk::CssProvider` in the port) · stylesheet · **no**

399 lines, 44 classes, and three custom CSS names registered from source
(`mathdisplay`, `mathconverter`, and the `.math-buttons` family). Includes
dark-mode (`prefers-color-scheme: dark`) and high-contrast
(`prefers-contrast: more`) blocks and the `clamp > .small` adaptive rules that
square off the display container on narrow windows. **A port that drops this
file produces a grey copy of the app**: the number buttons' tinted background,
the history tape's shaded panel, the bit-panel borders, the popover list
styling and the converter's typography all live here and nowhere else.

### 20. `data/org.gnome.calculator.gschema.xml` — settings

→ **`lib/settings.rb`** · settings · **yes**

4 enums (`NumberFormat`, `ButtonMode`, `AngleUnit`, `CurrencyDisplay`) and
19 keys, all of which `lib/settings.rb` carries with upstream's defaults and
ranges (JSON under `XDG_CONFIG_HOME`, not GSettings, so the app runs from a
checkout with no schema install): `history-tape` `a(ss)`, `accuracy`, `word-size`, `base`,
`show-thousands`, `show-zeroes`, `number-format`, `angle-units`,
`refresh-interval`, `currency-display`, `enabled-completions`,
`favorite-currencies`, `button-mode`, `unit-category`, `source-units`,
`target-units`, `precision`, `window-position`, `window-maximized`,
`window-size`.

### 21. `search-provider/search-provider.vala` — GNOME Shell search provider

→ **`lib/shell_search_provider.rb`** · service · **no**

`SearchProvider` (D-Bus `org.gnome.Shell.SearchProvider2`) and
`SearchProviderApp`, plus
`search-provider/org.gnome.Calculator-search-provider.ini` and the
`.service.in`. User-facing: typing a sum into the Shell overview returns the
answer as a result.

### 22. `src/gcalccmd.vala` — the CLI

→ **`exe/gcalccmd`** · CLI · **yes**

Reads equations on stdin, prints answers; `data/gcalccmd.1` is its man page.
Distinct from `gnome-calculator --solve`, which is in the application file.
Ported: `exe/gcalccmd` solves one argument or loops on stdin, exits on `exit`,
`quit` or a blank line, and refreshes currency rates synchronously because
there is no main loop. The man page itself is not carried over.

### 23. `po/` — translations

→ **`locale/`** + a gettext helper (`lib/translations.rb`) · i18n · **no**

101 languages in `po/LINGUAS`, and `po/POTFILES.in` lists 46 translatable
source files. `help/` ships the user manual in 34 languages across 29 pages
(`help/C/*.page`), which `app.help` opens.

---

## Supporting engine (`lib/*.vala` upstream) — not user-facing, but nothing works without it

One upstream file to one port file, same convention:

| Upstream | → | Present |
|---|---|---|
| `lib/number.vala` (2170 lines, MPFR/MPC arbitrary precision) | `lib/number.rb` (1963) | **yes** |
| `lib/equation-lexer.vala` (821) | `lib/equation_lexer.rb` (723) | **yes** |
| `lib/equation-parser.vala` (2463) | `lib/equation_parser.rb` (2199) | **yes** |
| `lib/equation.vala` | `lib/equation.rb` | **yes** |
| `lib/math-equation.vala` (1809, the `GtkSource.Buffer` subclass the display binds to) | `lib/math_equation.rb` (537 lines) | **yes** *(updated — ported since the previous version of this file, as a `Gtk::TextBuffer` wrapper rather than a `GtkSource.Buffer` subclass; GtkSource-specific behaviour not carried over, see the "State of the port" table above)* |
| `lib/serializer.vala` | `lib/serializer.rb` | **yes** |
| `lib/unit.vala` (`Unit`, `UnitCategory`, `UnitManager`) | `lib/unit.rb` | **yes** |
| `lib/currency.vala` (`Currency`, `CurrencyManager`) | `lib/currency.rb` | **yes** |
| `lib/currency-provider.vala` | `lib/currency_provider.rb` | **yes** |
| `lib/providers/{boc,ecb,imf,unt}-provider.vala` | `lib/providers/*.rb` | **yes** (4 of 4) |
| `lib/financial.vala` (the 10 financial functions) | `lib/financial.rb` | **yes** |
| `lib/function-manager.vala` (built-in function categories) | `lib/function_manager.rb` | **yes** |
| `lib/math-function.vala` | `lib/math_function.rb` | **yes** |
| `lib/math-variables.vala` | `lib/math_variables.rb` | **yes** |
| `lib/evaluation-budget.vala` | `lib/evaluation_budget.rb` | **yes** |
| `lib/mpfr-glue.vala`, `libmpfr/mpfr-glue.vala` | — | out of scope: the MPFR C shim; the port uses BigDecimal + Rational instead |
| `gcalc/*.vala` (49 files — the standalone GCalc expression library) | — | out of scope: a separate shipped library, not part of the app's UI |
| `gci/gci-entry-controller.vala` | — | out of scope with GCalc |

## Blockers and risks for the port

Ordered as the UI work will meet them. Items 1–3 are prerequisites for the
first widget file; the engine blockers from the previous survey are resolved.

1. **`lib/math_equation.rb` does not exist, and everything else waits on it.**
   Upstream's `MathEquation` is a `GtkSource.Buffer` subclass (1809 lines): the
   display binds it as the source view's buffer, and undo/redo, the selection,
   the cursor-offset arithmetic, the superscript/subscript tags, the status and
   base labels, and the `number-format`/`accuracy`/`show-zeroes`/
   `show-thousands`/`angle-units`/`word-size` bindings all run through it.
   Subclassing `GtkSource::Buffer` from Ruby has to be proved in a spike before
   `lib/math_display.rb` or `lib/math_window.rb` is written.
2. **GtkSourceView is a hard dependency.** `GtkSource.init`, `GtkSource.View`,
   `GtkSource.Completion` and five `GtkSource.CompletionProvider`
   implementations. Confirm the `gtk_source` typelib is in the fork's dev shell
   and that implementing the `CompletionProvider` interface from Ruby works; if
   it does not, the display needs a `Gtk::TextView` fallback and the
   completion popup a hand-built `Gtk::Popover`, which changes two units.
3. **Adwaita widgets the port has not exercised yet.** `Adw.BreakpointBin`,
   `Adw.Breakpoint`, `Adw.MultiLayoutView` / `Adw.Layout` / `Adw.LayoutSlot`,
   `Adw.Carousel`, `Adw.CarouselIndicatorDots`, `Adw.ButtonRow`,
   `Adw.ShortcutsDialog`, `Adw.EnumListModel`, `Adw.Spinner`. Each needs a
   constructor check against the `ruby-gtk` skill's quirks reference; the
   Advanced, Financial and Programming panels are unbuildable without the
   first four, so one spike covering them unblocks three of the five panels.
4. **`Adwaita::ApplicationWindow` is flagged broken in the bindings** by the
   `ruby-gtk` skill's quirks reference, yet upstream's `MathWindow` is an
   `Adw.ApplicationWindow` and the placeholder in
   `lib/gnome_calculator/application.rb` already constructs one successfully
   with `Adwaita::ApplicationWindow.new(app)`. Decide — and record in the
   quirks reference — whether `lib/math_window.rb` keeps it or drops to
   `Gtk::ApplicationWindow` with an `Adwaita::ToolbarView` child.
5. **Stateful and parameterised `GLib` actions everywhere.** `win.mode "s"`,
   `win.number-format` from settings, `cal.insert-brackets "(ss)"`,
   `cal.insert-digit "i"`, `cal.set-number-mode` with state. The whole
   button surface — ~148 buttons across five panels — targets the `cal` group
   by name and parameter, so variant-typed action targets from Ruby need a
   spike before any panel is written.
6. **The bit panel re-parents grid children at a breakpoint** via
   `Gtk.GridLayoutChild`, and loads a `Gtk.CssProvider` from a string inside
   `size_allocate` to scale the bit separators to `width / 40`. Both are
   unusual enough to verify in isolation.
7. **`src/ui/style.css` has no owner yet.** 399 lines, 44 classes, three custom
   CSS names, plus dark-mode and high-contrast blocks. It has to be carried
   over verbatim and loaded by a `Gtk::CssProvider`, or the port is a grey copy
   of the app whatever its widget tree says.
8. **Settings diverge from upstream by design.** `lib/settings.rb` is
   JSON-backed rather than GSettings, so there is no `Gio::Settings.bind` to
   lean on: every binding upstream declares (equation properties, the
   preferences rows, `favorite-currencies`, the window geometry, the history
   tape) has to be wired by hand with explicit change notification. This is the
   single largest source of silent parity gaps in the UI work.
9. **101 `po/` catalogues, 34 help languages.** A parity decision is still
   needed: carry the catalogues over behind a gettext helper, or declare the
   port English-only for now and say so. Nothing in `lib/` is marked
   translatable yet.
10. **`gcalc/` (49 files) and `gci/` are out of scope** — a separate shipped
    expression library with its own `.pc` file, not part of the app's UI. Worth
    restating because it is a third of upstream's Vala by file count.

## Binding-gem check (done as part of this 2026-11-07 re-survey, no app code changed)

`soup3` — the one gem this fork's fleet instructions call mandatory — is
already fully wired on `ruby`: declared in `gnome-calculator-rb.gemspec`
(`spec.add_dependency("soup3")`, alongside `gtk4`/`adwaita`/`glib2`), present
in `nix/Gemfile`, `libsoup_3` is in `flake.nix`'s `gtkStack`, and
`lib/currency_provider.rb` calls `Soup::Session`/`Soup::Message` directly for
the ECB/BoC/IMF/UNT rate downloads rather than hand-rolling HTTP. Nothing to
fix here; this item is closed.
