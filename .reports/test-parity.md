# Test parity — gnome-calculator-rb

Fifth pass, at `eba4d35e`. This report answers two separate questions that
earlier rounds tended to blur together: (1) is every upstream test ported,
and (2) does whatever test suite exists actually run. The answer to (2) is
the headline, because it changes what (1) even means.

## The RSpec suite has never executed a single example

```
$ nix develop --command xvfb-run -a ruby -e \
  'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'

An error occurred while loading spec_helper. - Did you mean?
                    rspec ./spec/spec_helper.rb

Failure/Error: require "kettle/test/rspec"

LoadError:
  cannot load such file -- kettle/test/rspec
# ./spec/spec_helper.rb:23:in '<top (required)>'

0 examples, 0 failures, 2 errors occurred outside of examples
```

`spec/` contains exactly two files: `spec_helper.rb` (kettle-test
boilerplate that cannot load because the `kettle-test` gem is not in the
dev shell's bundle) and `README.md` (prose describing helpers —
`stub_env`, `hide_env`, `:freeze`/`:travel`, `include_context "with rake"`
— that **no spec file uses, because no spec file exists**). This is not a
suite with failing examples; it is a suite with zero examples that cannot
even reach the point of looking for any. This finding is unchanged across
at least the last two passes (the fourth pass's commit message says
"the RSpec suite still fails to load (missing kettle-test gem)") — the
drive-script work in `8de8a498`/`eba4d35e` did not touch `spec/` or the
`Gemfile`'s `kettle-test` dependency.

**Say this plainly, because it is the kind of gap that is easy to round
away: there are zero RSpec examples in this repository, upstream or
ported, and the harness that would run them does not load.** Any
reference anywhere in this port's history to "N examples passing" refers
to the drive script below, not to RSpec — and none of this project's
`.reports/` files make that conflation, checked by grepping all five
report files for "RSpec" and "examples" together; it is flagged here as a
thing to keep watching, not a correction to a false claim found this pass.

## What does run: the headless drive script

`test/drive_gnome_calculator.rb` is not RSpec. It is a hand-rolled,
sequential smoke-test harness (`test/gtk_driver.rb` supplies `ok`/`shot`
helpers) that builds the real application object graph under Xvfb and
asserts against it step by step. Re-run this pass:

```
$ nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb
...
62 of 62 checks passed
DRIVE OK
```

This is real coverage — every "verified live" line in
`component-parity.md` traces to a step in this file — but it is coverage
of **13 components** out of the 23 identified upstream units, and it is
not RSpec, does not use `kettle-test`'s helpers, and would not be
discovered by `rspec spec`. It is also the *only* thing that runs:
`bundle exec rake` and `rspec spec` both fail before reaching a single
assertion for reasons unrelated to app logic (missing gem, not a bug in
`lib/`).

## Upstream's own test suite: not ported, not inventoried file-by-file

Upstream carries a Vala test suite:

```
$ git ls-tree -r --name-only origin/main | grep '^tests/'
tests/test-equation.vala
tests/test-fixed-pt.vala
tests/test-number.vala
tests/test-serializer.vala
tests/test.c
tests/meson.build
```

None of these five test files have a ported counterpart under `spec/` —
there is nothing under `spec/` to have a counterpart, per the section
above. `test-equation.vala` and `test-number.vala` in particular exercise
exactly the engine classes (`lib/equation.rb`, `lib/number.rb`) this port
claims are "20/20 complete" in every prior `component-identification.md`
pass; that claim is about files existing, not about upstream's own test
assertions being reproduced against them. The drive script's engine
section (steps `[14]`–`[16]`) checks precedence, a bad-expression error
code, and one unit conversion — a handful of assertions, not upstream's
test files translated line for line.

## Verdict

| Question | Answer |
|---|---|
| Does every upstream test exist in the port, ported? | No — 0 of upstream's 5 `tests/*.vala` files have any `spec/` counterpart |
| Does the port's own test suite (RSpec) run at all? | No — 0 examples, fails at `spec_helper` load, unchanged across at least two passes |
| Is there a running check of any kind? | Yes — the non-RSpec drive script, 62/62 this pass, covering 13 of 23 identified units |
| Is the drive script a substitute for the missing RSpec suite? | No — different mechanism, narrower scope (13/23 units), and it was never positioned as a replacement by this project's own commits |

**Gap, on both axes.** Fixing the `kettle-test` load failure is a
prerequisite to porting any of upstream's five test files, and until that
happens "RSpec suite" and "0 examples that have never run" are the same
sentence.
