# Component parity — gnome-calculator-rb

Fifth pass, at `eba4d35e`. Builds on `component-identification.md`'s fifth
pass. Live drive re-run this pass: `nix develop --command xvfb-run -a ruby
test/drive_gnome_calculator.rb` → **62 of 62 checks passed, DRIVE OK**
(13 components exercised, per the harness's own count in step numbering
`[0]`–`[20]`). Every "verified live" claim below cites a specific step
number from that run, re-executed just now, not read off a prior report.

## Units with live-verified behavioural parity (partial or full)

| # | Unit | Verified | Still missing from parity |
|---|---|---|---|
| 1 | Application shell | step `[0]`: real `Adwaita::ApplicationWindow`, sole toplevel, titled correctly, toolbar view/header bar/body wired, CSS loaded | zero app-level actions, no About dialog, no Close-All-confirmation dialog |
| 2 | Main window | steps `[0]`, `[8]`: header bar present; `win.mode('advanced')`/`('basic')` switches `MathButtons`' stack child both directions | no other `win.*` action, no menu besides the new Mode Selection popover |
| 3 | Shortcuts dialog | steps `[11]`–`[13]`: shortcuts button on header bar, opens real `Adwaita::Dialog` titled "Keyboard Shortcuts", closes clean | 38/43 items (5 missing), not reached by `app.shortcuts` (no such action exists) |
| 4 | Display | steps `[1]`, `[4]`: solves through real buttons, shows/clears an error status | plain `Gtk::TextView`, no `GtkSource.Buffer`-dependent styling (documented binding gap, `FINDINGS.md`) |
| 6/7 | History view + entry | step `[5]`: starts empty, solving adds one row, row is a real `Gtk::ListBoxRow` with equation/=/answer labels, clicking either label re-inserts text | in-memory only — no tape persistence across restarts (upstream persists history) |
| 8 | Button-panel host (`cal` action group) | steps `[8]`, `[9]`: mode switch; sin/factorize/square/|x| buttons dispatch through `cal.insert-function`/`cal.factorize`/`cal.square`/`cal.insert-brackets`; inverse toggle flips the sin button's label live | Financial/Programming/Conversion modes raise instead of switching — a loud, not silent, gap |
| 9 | Basic panel | steps `[1]`–`[3]`, `[7]`: digit/operator entry, clear, memory popover round-trip, function popover round-trip, super/subscript toggles | — (this unit holds full behavioural parity for what it covers) |
| 10 | Advanced panel | step `[9]`: sin/factorize/square/abs buttons verified live; inverse toggle verified live | log/exp stack, nth-root, complex-component row, angle-unit menu, π/e/i constant buttons are built (confirmed by reading `lib/advanced_button_panel.rb`) but **not exercised by the drive script** — present in source, unverified at runtime this pass |
| 15–17 | Popover base + function/variable popovers | steps `[2]`, `[3]`: legal-name sensitivity, reserved-name rejection, store/delete round-trip (variables); legal-name sensitivity, template insertion, `FunctionManager` acceptance, engine evaluation of the defined function (functions) | — |
| 19 | Stylesheet | step `[0]`: `Gtk::CssProvider` loads `style.css` without raising | dormant classes for units 11–14/18/21, which don't exist to use them |
| 20 | Settings | step `[17]`: base defaults to 10, round-trips | `Gio::Settings.bind()` targets upstream makes (preferences, favourite currencies, history tape) have no consumer |
| 22 | CLI | steps `[18]`–`[20]`: argv mode, stderr-only error reporting, stdin REPL to blank line | man page not carried over (stated, small) |
| 14 (engine) | Equation solving, unit conversion | steps `[14]`–`[16]`: precedence, real `ErrorCode` on bad input, unit table conversion (1 m = 100 cm) | error-message text for most `ErrorCode` values does not match upstream's wording or interpolate the offending token — see `translation-parity.md`, this is a user-visible parity gap as well as a translation one: upstream shows `Unknown variable "x"`, the port shows the fixed string `Unknown variable` with no token |

## Units with zero behavioural parity (unchanged from identification)

Autocompletion providers (5), Financial/Programming/Conversion panels + bit
panel + financial dialogs + converter, preferences + favourite-currencies
page, shell search provider. None of these have any file in `lib/`, so
there is nothing to drive and nothing the 62-check gate exercises for them.
**A component with zero port counterpart is not "N/A" — it is a gap**, and
is reported as one here rather than silently excluded from the totals.

## New finding this pass: the error-message mapping was invented, not ported

`lib/math_equation.rb#error_message` maps `ErrorCode` to displayed text.
Reading it against upstream's `lib/math-equation.vala` line by line:

| ErrorCode | Port text | Upstream text |
|---|---|---|
| `UNKNOWN_VARIABLE` | `"Unknown variable"` | `_("Unknown variable “%s”").printf(error_token)` |
| `UNKNOWN_FUNCTION` | `"Unknown function"` | `_("Function “%s” is not defined").printf(error_token)` |
| `UNKNOWN_CONVERSION` | `"No conversion possible"` | `_("Unknown conversion")` |
| `UNKNOWN_UNIT` | `"Unknown unit"` | `_("Unknown unit “%s”").printf(error_token)` |
| `UNKNOWN_RATE` | `"No sane value to convert"` | `_("Exchange rate for “%s” is not available").printf(error_token)` |
| `MP` | `"Calculation error"` | not found under this mapping upstream; no matching upstream string |
| `TIMED_OUT` | `"Calculation took too long"` | not found upstream in this function |
| default | `"The result of the calculation is undefined"` | not found upstream in this function |
| `INVALID` | `"Malformed expression"` | `_("Malformed expression")` — **this one matches exactly** |

Only 1 of 9 branches matches upstream's actual wording; the rest are
plausible-sounding English invented for the port, several drop the
offending token (`%s`) entirely, and none of the 8 mismatched strings
exist as a `msgid` anywhere in `po/`. This is a behavioural parity gap
(the user sees different text than upstream for most error states) that
is also the root cause of the translation gap flagged in
`translation-parity.md`.

## Totals

| | Count |
|---|---:|
| Units with full, unqualified parity | 3 (basic panel's covered behaviours, popovers, settings storage/CLI's functional half) |
| Units with partial, live-verified parity | 10 |
| Units with source present but unverified by the drive gate | 1 (Advanced panel's log/exp/nth-root/complex/angle-unit controls) |
| Units with zero parity | 8 |
| Behavioural mismatch found independent of file presence | 1 (error-message text, 8/9 branches wrong) |

The runtime gate (62/62, DRIVE OK, 13 components) is accurate for what it
tests and is treated here as confirming, not substituting for, the
per-unit read above — it covers roughly half of the Advanced panel's own
button grid and none of the 8 zero-parity units.
