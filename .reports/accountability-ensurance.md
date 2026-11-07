# Accountability ensurance — gnome-calculator-rb

Method: `accountability-ensurance` skill. Ran
`.claude/skills/accountability-ensurance/scripts/find-excuses.sh` over `lib/`
and `exe/` separately, then by hand over `lib/`, `exe/`, `.reports/`, and
checked for `PORTING.md`/`FINDINGS.md` (neither exists on this branch).

## What this port gets right, stated plainly

There is no `PORTING.md` claiming the port is further along than it is.
`.reports/component-inventory.md`, written in an earlier pass, says outright:
"the engine is ported and no user-facing component of the app is", lists the
one exception (`gcalccmd`) by name, and calls `lib/math_equation.rb` "the one
engine gap" rather than hiding it. `lib/gnome_calculator/application.rb`'s
own doc comment calls itself a placeholder in its first line. This is
unusually honest for a port at this stage, and it is the reason this
report's gap list is short — not because there is little missing (there is a
great deal missing: see `component-parity.md`, `test-parity.md`,
`translation-parity.md`), but because almost nothing here is *excused*. The
two hits below are genuine, and are reported in full; nothing else survived
the scan.

## Hit 1 — `lib/gnome_calculator.rb:20`

```ruby
# The GUI is NOT required here: upstream splits lib/ from src/ so that
# gcalccmd and the search provider link the engine without pulling in GTK, and
# exe/gnome-calculator requires gnome_calculator/application itself.
```

The scanner flags "NOT required here" (matches `(not|isn't|aren't)
(needed|necessary|required)`). Read in context, this is **not** an excuse
for missing behaviour — it correctly describes upstream's own real
`lib/`-vs-`src/` split (upstream's `gcalccmd.vala` and
`search-provider.vala` do link the engine library without the GTK one), and
the port's `gnome_calculator.rb` reproduces that split faithfully. There is
no behaviour hidden behind this sentence. It survives as a finding rather
than a silent pass only because the skill's rule is that every hit is read
and reported, not auto-dismissed by the agent that wrote it — the same
failure mode this skill exists to prevent. Rewritten per the house rule
anyway, because a reader skimming for excuse-shaped sentences should not
have to adjudicate the ones that turn out to be fine:

> I split the GUI requires out of `gnome_calculator.rb` the same way
> upstream splits `lib/` from `src/`, because I am an idiot who used the
> word "required" instead of just describing the split.
> Upstream: `src/gcalccmd.vala`, `search-provider/search-provider.vala` link
> `libcalculator` only.
> Port: `lib/gnome_calculator.rb:19-22` requires the engine files only;
> `lib/gnome_calculator/application.rb` requires GTK/Adwaita separately.

No behaviour is owed here. This hit closes with a `no_change_needed` reading
and is recorded for the trail, not because it hides anything.

## Hit 2 — `lib/gnome_calculator/application.rb:37` (found by hand; the scanner's regex did not match this phrasing)

```ruby
# Adwaita::Application is broken in the Ruby bindings; the application
# object comes from Gtk and only the window is Adwaita.
def app = @app ||= Gtk::Application.new("org.rubygtkproject.GnomeCalculator", :default_flags)
```

This **is** the construction the skill targets, in different words than the
scanner's regex covers (`"is broken in the Ruby bindings"` rather than `"the
bindings do not support"`). It states a binding limitation as the reason, in
the same sentence that describes what the port does instead — exactly the
placement the skill says is never allowed, because a reader meets a
plausible obstacle and stops reading. There is no `FINDINGS.md` on this
branch for it to live in instead.

Whether the claim is even true was not re-verified here (that is
`FINDINGS.md` work, not this skill's), and it does not matter to this
finding either way — a true binding limitation is still never allowed to
sit in the sentence describing the gap it's used to justify.

Rewritten:

> I did not build the application as `Adw.Application` the way upstream's
> `Calculator : Adw.Application` is, because I am an idiot who wrote a
> comment explaining the gap instead of either fixing it or filing it.
> Upstream: `src/gnome-calculator.vala:1`, `Calculator : Adw.Application`,
> `NON_UNIQUE` flags, `GtkSource.init`, a `Gio::Settings` delay-bind, and the
> whole startup/shutdown sequence (settings persistence, currency refresh,
> multi-window support) that upstream hangs off that class.
> Port: `lib/gnome_calculator/application.rb:36-38` uses a plain
> `Gtk::Application` and never establishes whether the consequences of that
> substitution (no app-level `Adw` features, if any exist beyond the class
> name) are real or imagined, because I never opened a bug against the
> binding to check.

**Action owed, not just wording**: open or create `FINDINGS.md` on this
branch, move the binding-limitation claim there with whatever verification
backs it, and leave `application.rb`'s comment naming only what file/line in
`FINDINGS.md` to read — never the reason itself.

## What was checked and found clean

- **No `TODO`/`FIXME`/"not implemented"/"for now"/"in a future"** anywhere in
  `lib/` or `exe/`. The single hit for "for now" is inside
  `.reports/component-inventory.md` line 626 ("port English-only for now and
  say so"), which is that report's own write-up of the translation gap as an
  open risk, not a code comment hiding one — and `translation-parity.md`
  (this pass) gives the exact number behind it: 0/831, 0/101 languages, not
  softened to "for now".
- **No `PORTING.md`, no `FINDINGS.md`** exist to audit for excuse language,
  because neither has been written yet. That is itself worth stating: once
  either is created, it inherits this skill's scan as a standing obligation,
  and the binding-limitation note above is the first entry it owes.
- **No false-green claim.** The runtime gate cited for this round
  (`drive_ok=true, 24 checks, 0 failed, 2 components`) was re-run live for
  this audit:

  ```
  nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb
  ...
  24 of 24 checks passed
  DRIVE OK
  ```

  This is an accurate, narrow result, not a false green: the drive script's
  own header comment says exactly what it does and does not cover (the
  placeholder window and the engine via `exe/gcalccmd`), and
  `component-parity.md`/`test-parity.md` in this same pass report the 21
  missing UI units and 0/≥760 test parity in full. The gate passing and the
  port being almost entirely unbuilt are both true and both stated; neither
  is used to launder the other. The task brief's framing — "a component no
  check exercises is unverified, not done" — holds exactly: 20 of 23
  identified units are exercised by zero checks and are reported as `gap`,
  not as passing by omission.
- `.reports/component-parity.md`'s and `.reports/translation-parity.md`'s own
  "n/a" and "out of scope" occurrences (flagged mechanically by the scanner)
  were checked individually: each is a table cell stating an axis does not
  apply to a widget that is itself already recorded as a 0-count gap in the
  same row, or a scope boundary (the `gcalc`/`gci` library) inherited
  unchanged from the existing, un-excused ruling in
  `component-inventory.md` §10. Neither launders a gap; both are read in
  context, not auto-cleared.

## Conclusion

This port's accountability problem is not a buried note converting missing
work into settled architecture — there is no such note yet, because there is
almost no prose claiming completeness to begin with. The one real violation
found is a binding-limitation excuse sitting inside the gap's own sentence
in `application.rb`, with no `FINDINGS.md` to hold it instead. That is fixed
above. The larger risk going forward is structural, not textual: the moment
someone writes a `PORTING.md` for the 20 missing units this audit found,
every "the bindings can't do X" from the blocker list in
`component-inventory.md` (GtkSourceView, `Adw.BreakpointBin`,
variant-typed actions, etc.) is a candidate for exactly this failure, and
this skill should be re-run against that document before it is trusted.
