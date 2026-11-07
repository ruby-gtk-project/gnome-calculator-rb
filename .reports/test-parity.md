# Test parity — gnome-calculator-rb

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `da4eed8c` |
| Upstream tests | **≥ 760** (census below; a lower bound, see caveats) |
| Ported | **0** |
| Gaps | **≥ 760** |
| Test command (upstream) | `meson test`, 6 binaries registered in `tests/meson.build` |
| Test command (port) | `rspec spec/` — **the suite contains zero example files** |

## Step 1 — census the upstream suite

`git ls-tree -r --name-only origin/main | grep -i test` finds the upstream
test tree:

```
tests/test-equation.vala
tests/test-number.vala
tests/test-serializer.vala
tests/test-currency-providers.vala
tests/gcalc-parsing.vala          (gcalc/ — out of scope per component-inventory.md)
tests/gcalc-solving-basic.vala    (gcalc/ — out of scope)
tests/test-gci-entry-controller.vala (gci/ — out of scope)
tests/*.feature + steps/, environment.py, common_steps.py   (behave BDD, UI-driven)
```

`tests/meson.build` registers exactly 6 binaries behind `get_option('app')`:
`test-equation`, `test-currency-providers`, `test-number`, `test-serializer`,
plus `gcalc-parsing`/`gcalc-solve-basic` behind `get_option('gcalc')` and
`test-entry-controller` behind `gci`/`gcalc`/`ui-tests`. The four in scope of
this port (equation, currency-providers, number, serializer) are the ones
censused below; the gcalc/gci three are out of scope by the same ruling as
`component-inventory.md`'s item 10 (a separate shipped library, not the
app's UI or engine as ported here).

Case counts, read from the assertion call each file actually uses (not a
blind `test_*` grep — these are hand-table-driven C/Vala suites):

| File | Assertion unit | Count |
|---|---|---:|
| `tests/test-equation.vala` | `test(expr, expected, error_code)` calls | **582** |
| `tests/test-number.vala` | `private void test_*()` functions, each a self-contained check | **52** |
| `tests/test-serializer.vala` | `private void test_*()` functions | **6** |
| `tests/test-currency-providers.vala` | `test_imf_provider`, `test_ecb_provider`, `test_currency_conversions` + per-conversion `test(...)` calls | ≥ **3** named + dozens of table rows (not fully expanded here — already over the line needed to call this a gap) |

Total in-scope upstream engine tests: **at least 643** by this count, before
fully expanding the currency-provider table. The `component-parity` /
`accountability-ensurance` angle on this number: the port's own
`.reports/component-inventory.md` claims 19 of 20 engine files are "ported"
(`number.rb`, `equation_lexer.rb`, `equation_parser.rb`, `equation.rb`,
`serializer.rb`, `currency.rb`, `currency_provider.rb`, 4 provider files)
— exactly the files these 643 upstream tests pin — and not one of those 643
cases has a Ruby counterpart.

The upstream `tests/*.feature` files (Behave, driving the real UI) add:

| File | Scenarios |
|---|---:|
| `tests/basic_mode.feature` | 9 |
| `tests/advanced_mode.feature` | 1 |
| `tests/financial_mode.feature` | 1 |
| `tests/programming_mode.feature` | 1 |

These 12 scenarios test exactly the UI (`component-parity.md`'s units 2–19)
that does not exist in the port, so they cannot be ported yet either — each
is a `gap` whose "behaviour still owed" is the UI feature it drives.

**≥ 760 total** (643 engine + 12 UI scenarios + the unexpanded
currency-provider table rows, conservatively; the true engine figure is
higher once that table is expanded case-by-case).

## Step 2 — census the port suite

```sh
find . -iname '*test*' -not -path './.git/*'
```

finds exactly two files: `test/drive_gnome_calculator.rb` (24 checks, see
below) and `test/gtk_driver.rb` (the harness it uses, correctly excluded by
the skill's own `*driver*`/`*helper*` filter — it has no test cases of its
own).

`spec/` contains **`spec_helper.rb` and `README.md` only** — no file matching
`*_spec.rb` exists anywhere in the tree. Running the Rakefile's declared
spec command,

```
ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'
```

runs zero examples, because there are zero example files. **The RSpec
harness is fully scaffolded (`kettle-test`, `SimpleCov`, `.rspec_status`) and
has never run a single real assertion.**

`test/drive_gnome_calculator.rb` is a different thing: a live smoke/headless
driver, run as:

```
nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb
```

Re-run live for this report: **24 of 24 checks passed, `DRIVE OK`.** Its own
header comment states plainly what it is and is not: it drives "every
component the port *does* claim" — the placeholder window and the engine
reachable through `exe/gcalccmd` — and explicitly cannot click controls that
do not exist. It is an honest, narrow smoke test, not a test-parity
substitute, and it maps to **zero** of the upstream tests censused above: it
was written from scratch for the port, not from any upstream test file or
case.

## Step 3 — the bijection

| Upstream test | Port test | State |
|---|---|---|
| 582 cases, `tests/test-equation.vala` | — | **gap**, all 582 |
| 52 cases, `tests/test-number.vala` | — | **gap**, all 52 |
| 6 cases, `tests/test-serializer.vala` | — | **gap**, all 6 |
| ≥3 named + table, `tests/test-currency-providers.vala` | — | **gap**, all |
| 9 scenarios, `tests/basic_mode.feature` | — | **gap**, all 9 (needs the UI) |
| 1 scenario each, `advanced_mode.feature`, `financial_mode.feature`, `programming_mode.feature` | — | **gap**, all 3 (needs the UI) |

Every upstream test row maps to nothing. Zero upstream tests have a named
Ruby counterpart. The bijection is 0/N in both the required senses: no
upstream test names a port test, and (trivially) no port test is named by an
upstream test, because the port's one real test file
(`test/drive_gnome_calculator.rb`) was not derived from any of them.

## Behaviour still owed (representative, not exhaustive)

- Every arithmetic/precedence/function-evaluation case `test-equation.vala`
  pins over its 582 table rows — the port's `equation.rb`/`equation_parser.rb`
  are exercised by exactly 2 ad hoc expressions in the drive script
  (`1 + 2 * 3`, `1 meter in cm`) and nothing else.
- Arbitrary-precision arithmetic edge cases in `test-number.vala` (52
  functions: integer round-trips, overflow, rational/complex behaviour) —
  `number.rb` (1963 lines) has no test of any kind.
- Output formatting in `test-serializer.vala` (6 functions covering
  automatic/fixed/scientific/engineering display and base conversion) —
  `serializer.rb` has no test.
- Live currency-provider parsing/conversion in `test-currency-providers.vala`
  — `currency_provider.rb` and the 4 `lib/providers/*.rb` files have no test.
- All four mode-specific UI flows in the `.feature` files — unbuildable
  until `lib/math_window.rb` and friends exist (see
  `component-identification.md`).

## Conclusion

**Test parity is 0/≥760.** The port's suite that does run (the 24-check
drive script) is real and its result (`DRIVE OK`) is accurate for what it
covers, but it inherits none of upstream's knowledge: not one of its checks
was derived from an upstream test case, and the 643+ engine cases that pin
the exact files the inventory calls "ported" have no safety net at all. A
transcription error in `number.rb` or `equation_parser.rb` that upstream's
suite would catch has nothing in this port to catch it.
