# Test parity — gnome-calculator-rb

| | |
|---|---|
| Upstream | `main` @ `1d311e0a` |
| Port | `ruby` @ `9824569e` |
| Upstream tests | **≥ 760** (unchanged census from the prior pass; see below) |
| Ported as RSpec examples | **0** |
| RSpec suite status | **broken** — `require "kettle/test/rspec"` raises `LoadError`, the gem is not installed; 0 examples found regardless |
| Port's own headless driver (`test/drive_gnome_calculator.rb`) | 43 checks, 0 failed, re-run live this pass — real, but derived from none of upstream's test files |

Method: `test-parity` skill. Re-ran the census and, new this pass, actually
executed the dev-shell's own declared spec command rather than trusting
that it would run.

## Step 1 — the upstream suite (unchanged)

`tests/meson.build` registers 6 binaries. In scope of this port (engine +
UI, excluding the separately-shipped `gcalc`/`gci` library per
`component-inventory.md` §10):

| File | Count |
|---|---:|
| `tests/test-equation.vala` | 582 `test(expr, expected, error_code)` calls |
| `tests/test-number.vala` | 52 `test_*()` functions |
| `tests/test-serializer.vala` | 6 `test_*()` functions |
| `tests/test-currency-providers.vala` | ≥3 named + a table of per-conversion cases, not fully expanded |

Plus Behave UI scenarios, gated on the UI existing at all:

| File | Scenarios |
|---|---:|
| `tests/basic_mode.feature` | 9 |
| `tests/advanced_mode.feature` | 1 |
| `tests/financial_mode.feature` | 1 |
| `tests/programming_mode.feature` | 1 |

Total: **≥ 760** engine + UI cases, conservative.

## Step 2 — the port suite, actually run this pass

`find . -iname '*test*' -o -iname '*spec*'` (excluding `.git`) finds:

- `test/drive_gnome_calculator.rb` — the custom headless driver, 43 checks.
- `test/gtk_driver.rb` — its harness, no cases of its own.
- `spec/README.md`, `spec/spec_helper.rb` — **no file matching `*_spec.rb`
  anywhere in the tree.**

The dev shell's own banner (printed by `nix develop`, read before running
anything, per the environment's own instructions) names the spec command as:

```
ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

Run live this pass, inside the same dev shell the banner printed from:

```
$ nix develop --command ruby -e '…'
An error occurred while loading spec_helper. - Did you mean?
                    rspec ./spec/spec_helper.rb

Failure/Error: require "kettle/test/rspec"

LoadError:
  cannot load such file -- kettle/test/rspec
# ./spec/spec_helper.rb:23:in '<top (required)>'

0 examples, 0 failures, 2 errors occurred outside of examples
```

**The suite does not load, independent of having zero examples.** The
`kettle-test` gem `spec/spec_helper.rb` requires is not in the bundle (not
in `Gemfile.lock`/`nix/Gemfile.lock` as an installed gem, confirmed by the
`LoadError`). This is strictly worse than "0 examples": even an empty
`spec/` with a working harness would at least prove the harness itself
runs. Here the harness has never successfully executed once, on this
checkout, in this devshell — which is the dev shell's *own* banner command,
so no one needs to go looking for it to hit this.

`test/drive_gnome_calculator.rb` re-run live this pass:
**43 of 43 checks passed, `DRIVE OK`** (9 numbered steps touching the
application, basic button panel, display error/clear, history view +
entries, superscript/subscript toggle, the key controller, the shortcuts
dialog, the evaluation engine directly, unit conversion, settings, and
`gcalccmd` three ways). This is accurate for what it runs and is not an
RSpec substitute: it is a bespoke script, invoked by `ruby
test/drive_gnome_calculator.rb` under `xvfb-run`, not by `rspec`, not
collected by `rake`, and not derived from any upstream `.vala`/`.feature`
file — none of its 43 checks is named after or ported from an upstream test
case.

## Step 3 — the bijection

| Upstream test | Port test | State |
|---|---|---|
| 582 cases, `test-equation.vala` | — | **gap**, all 582 |
| 52 cases, `test-number.vala` | — | **gap**, all 52 |
| 6 cases, `test-serializer.vala` | — | **gap**, all 6 |
| ≥3 + table, `test-currency-providers.vala` | — | **gap**, all |
| 9 scenarios, `basic_mode.feature` | — | **gap** (UI exists for basic mode now, but the scenario itself is not ported) |
| 1 scenario each, `advanced_mode`/`financial_mode`/`programming_mode` | — | **gap**, all 3 (UI does not exist for any of them) |

Zero upstream tests have a named Ruby counterpart, in either the RSpec
suite (which does not run) or the drive script (which was written fresh,
not transcribed).

## Behaviour still owed (representative)

- `number.rb` (1963 lines, arbitrary-precision complex arithmetic) has no
  test of any kind — upstream pins it with 52 functions.
- `equation_parser.rb`/`equation.rb` are exercised by exactly 3 ad hoc
  expressions total across the drive script (`1 + 2 * 3`, `1 + ` as an
  error case, `1 meter in cm`) against upstream's 582-row table.
- `serializer.rb` (display formatting across automatic/fixed/scientific/
  engineering, every number base) has no test.
- `currency_provider.rb` and the 4 `lib/providers/*.rb` files have no test;
  the drive script never calls them (it never needs network access, which
  is itself untested — a provider that silently fails to parse a changed
  API response has nothing to catch it).
- `math_shortcuts.rb`'s 5 missing rows (see `component-parity.md`) have no
  test that would have caught the gap either in the port's own suite or
  upstream's, because neither side has a test over the shortcuts dialog's
  content at all — this gap was found by a manual line-count diff in this
  audit, not by any automated check.

## Conclusion

**Test parity is 0/≥760, unchanged in kind from the prior pass, but now
confirmed worse in one respect: the dev shell's own advertised spec command
does not merely find zero examples, it fails to load at all** (missing
`kettle-test` gem). A reader who runs the banner command exactly as printed
gets a `LoadError`, not "0 examples" — that distinction matters because "0
examples, suite loads fine" is a project that is simply young, while
"suite does not load" is a project where no one has run the thing the dev
shell tells you to run. The runtime gate this round (`drive_ok=true`, 43
checks) is real and re-verified live, but it is a hand-written smoke test
over 9 of the port's 23 identified units (`component-identification.md`),
not a test suite with any claim to covering the other 14, and it inherits
none of upstream's ≥760 cases' specific knowledge of edge cases, precedence
rules, or formatting corners.
