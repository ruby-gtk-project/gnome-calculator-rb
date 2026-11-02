# gnome-calculator — upstream component inventory

Survey of `origin/main` (upstream Vala + blueprint) against `lib/` on the
`ruby` branch, for the full-parity port. No app code written in this step.

Method: `component-identification` skill. Upstream has blueprint files for
every widget tree (`src/ui/*.blp`), so those are the primary inventory; the
matching `src/*.vala` supplies the callbacks, the action groups and the
widgets built at runtime. **The component is the pair**, and both halves are
unioned into one port file below.

## State of the port

`lib/` on `ruby` contains three files:

| File | What it is |
|---|---|
| `lib/gnome_calculator.rb` | one `require_relative` |
| `lib/gnome_calculator/application.rb` | `Gtk::Application` + an `Adwaita::StatusPage` that says the port is not written |
| `lib/gnome/calculator/rb/version.rb` | gem version |

**No user-facing component of gnome-calculator exists in the port yet.** The
application file is a placeholder shell: window, `Adwaita::ToolbarView`,
`Adwaita::HeaderBar`, status page. It installs no actions, no accelerators, no
menus, and holds no equation.

## Totals

| | Upstream | Port |
|---|---:|---:|
| UI source files (`src/*.vala`) | 14 | 1 (placeholder) |
| Blueprint files (`src/ui/*.blp`) | 14 | 0 (by design — house style builds in Ruby) |
| Component units (template / named root) | 28 | 1 |
| Button widgets across the five panels | ~148 | 0 |
| Distinct CSS classes in `style.css` | 44 | 0 |
| GSettings keys | 19 | 0 |
| Menu models | 4 (`window_menu`, `primary_menu`, `context_menu_model`, `base_menu`, `word_size_menu`) | 0 |
| Shortcut items in the shortcuts dialog | 44 across 5 sections | 0 |
| `po/` languages | 101 | 0 |
| Engine files (`lib/*.vala`, the maths) | 22 | 0 |

---

## Components, in the order a user meets them

### 1. `src/gnome-calculator.vala` — the application

→ **`lib/gnome_calculator/application.rb`** · application · **present (placeholder only)**

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

→ **`lib/math_window.rb`** · window · **no**

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

→ **`lib/shortcuts_dialog.rb`** · dialog · **no**

A standalone `$AdwShortcutsDialog` with no backing source file; reached by
`app.shortcuts`. Five `$AdwShortcutsSection`s, 44 `$AdwShortcutsItem`s:

| Section | Items |
|---|---:|
| General | 8 (new window, close window, quit, help, F10 open menu, preferences, shortcuts, clear history) |
| Switching Modes | 7 (the six modes, keyboard twice: `<control><alt>k` and `<control><alt>t`) |
| Programming Mode | 4 (Ctrl+B/O/D/H → binary/octal/decimal/hex) |
| Keyboard Entry | 17 (×, ÷, ², √, ⁻¹, π, τ, °, floor/ceiling in ltr and rtl, scientific, sub/superscript digits, superscript minus) |
| Equation | 8 (copy, paste, undo, redo, previous/next equation, clear, factorize) |

### 4. `src/math-display.vala` + `src/ui/math-display.blp` — the equation display

→ **`lib/math_display.rb`** · widget · **no**

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

→ **`lib/history_view.rb`** · widget · **no**

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

→ **`lib/history_entry.rb`** · row · **no**

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

→ **`lib/basic_button_panel.rb`** · panel · **no**

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

→ **`lib/settings.rb`** · settings · **no**

4 enums (`NumberFormat`, `ButtonMode`, `AngleUnit`, `CurrencyDisplay`) and
19 keys: `history-tape` `a(ss)`, `accuracy`, `word-size`, `base`,
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

→ **`exe/gcalccmd`** · CLI · **no**

Reads equations on stdin, prints answers; `data/gcalccmd.1` is its man page.
Distinct from `gnome-calculator --solve`, which is in the application file.

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
| `lib/number.vala` (2170 lines, MPFR/MPC arbitrary precision) | `lib/number.rb` | no |
| `lib/equation-lexer.vala` (821) | `lib/equation_lexer.rb` | no |
| `lib/equation-parser.vala` (2463) | `lib/equation_parser.rb` | no |
| `lib/equation.vala` | `lib/equation.rb` | no |
| `lib/math-equation.vala` (1809, the `Gtk.TextBuffer` subclass the display binds to) | `lib/math_equation.rb` | no |
| `lib/serializer.vala` | `lib/serializer.rb` | no |
| `lib/unit.vala` (`Unit`, `UnitCategory`, `UnitManager`) | `lib/unit.rb` | no |
| `lib/currency.vala` (`Currency`, `CurrencyManager`) | `lib/currency.rb` | no |
| `lib/currency-provider.vala` | `lib/currency_provider.rb` | no |
| `lib/providers/{boc,ecb,imf,unt}-provider.vala` | `lib/providers/*.rb` | no |
| `lib/financial.vala` (the 10 financial functions) | `lib/financial.rb` | no |
| `lib/function-manager.vala` (built-in function categories) | `lib/function_manager.rb` | no |
| `lib/math-function.vala` | `lib/math_function.rb` | no |
| `lib/math-variables.vala` | `lib/math_variables.rb` | no |
| `lib/evaluation-budget.vala` | `lib/evaluation_budget.rb` | no |
| `gcalc/*.vala` (49 files — the standalone GCalc expression library) | — | out of scope: a separate shipped library, not part of the app's UI |
| `gci/gci-entry-controller.vala` | — | out of scope with GCalc |

## Blockers and risks for the port

1. **`MathEquation` is a `GtkSource.Buffer` subclass.** The display binds the
   equation object directly as the source view's buffer, and undo/redo,
   selection, the cursor-offset arithmetic and the superscript/subscript tags
   all run through it. Subclassing `GtkSource::Buffer` in Ruby needs checking
   before any of the display work starts.
2. **GtkSourceView is a hard dependency.** `GtkSource.init`, `GtkSource.View`,
   `GtkSource.Completion` and five `GtkSource.CompletionProvider`
   implementations. Confirm the `gtk_source` typelib is in the fork's dev shell
   and that implementing the `CompletionProvider` interface from Ruby works.
3. **Arbitrary-precision maths.** Upstream uses MPFR and MPC at a 2000-bit
   default precision and leans on them for complex numbers, so Ruby's `BigDecimal`
   is not a drop-in. Decide early between an FFI binding and accepting reduced
   precision, and record the choice.
4. **Adwaita widgets the port has not exercised yet.** `Adw.BreakpointBin`,
   `Adw.Breakpoint`, `Adw.MultiLayoutView` / `Adw.Layout` / `Adw.LayoutSlot`,
   `Adw.Carousel`, `Adw.CarouselIndicatorDots`, `Adw.ButtonRow`,
   `Adw.ShortcutsDialog`, `Adw.EnumListModel`, `Adw.Spinner`. Each needs a
   constructor check against the `ruby-gtk` skill's quirks reference; three of
   the five button panels are unbuildable without the first four.
5. **`Adwaita::ApplicationWindow` is flagged broken in the bindings**, yet
   upstream's `MathWindow` is an `Adw.ApplicationWindow` and the current
   placeholder already uses `Adwaita::ApplicationWindow`. Resolve which it is
   before `lib/math_window.rb` is written.
6. **Stateful and parameterised `GLib` actions everywhere.** `win.mode "s"`,
   `win.number-format` from GSettings, `cal.insert-brackets "(ss)"`,
   `cal.set-number-mode` with state. Variant-typed action targets from Ruby need
   a spike.
7. **The bit panel re-parents grid children at a breakpoint** via
   `Gtk.GridLayoutChild`, and loads a `Gtk.CssProvider` from a string inside
   `size_allocate`. Both are unusual enough to verify in isolation.
8. **GSettings schema.** Nineteen keys with enums and `(ii)` / `a(ss)` tuple
   types. The schema has to be compiled and findable at runtime, or every
   settings read fails.
9. **101 `po/` catalogues.** A parity decision is needed: carry the catalogues
   over, or declare the port English-only for now and say so.
