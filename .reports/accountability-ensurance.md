# Accountability ensurance — gnome-calculator-rb

Fifth pass, at `eba4d35e`. Ran
`.claude/skills/accountability-ensurance/scripts/find-excuses.sh lib exe .reports`
and by hand over the same plus `FINDINGS.md`, `AGENTS.md`, `CLAUDE.md`,
`README.md`, `CHANGELOG.md`. `PORTING.md` still does not exist on this
branch — unchanged across five passes now, so this is the fifth
consecutive pass noting it, not a new observation.

## find-excuses.sh: one hit, read and dismissed

```
gnome_calculator.rb:20:NOT required here:...
```

`lib/gnome_calculator.rb:19-20` reads: `"The GUI is NOT required here:
upstream splits lib/ from src/ so that gcalccmd and the search provider
link the engine without pulling in GTK..."`. Read in context this is an
architectural comment explaining a deliberate require-order split, not an
excuse for missing behaviour — it names the search provider as a reason
the split exists, not as a claim the search provider is built (it is not;
`component-identification.md` lists it as unit 21, zero port counterpart).
Dismissed as a false positive of the script's pattern match, same as in
the fourth pass.

No `TODO`, `FIXME`, "not implemented", "for now", or "in a future" string
appears anywhere in `lib/` or `exe/` — checked directly with
`grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/`,
zero hits, same as every prior pass.

## Headline finding this pass: four prior parity reports carried a false green on the error-message mapping

Every `component-parity.md` and `translation-parity.md` pass through the
fourth (at commits `9824569e` through `da40269a`/`feb97cb0`) counted the
engine's error-reporting behaviour as parity-holding on the strength of
drive-script steps `[14]`/`[15]` — "an incomplete expression fails to
solve... with an actual ErrorCode, not an exception." That check is true
and remains true. But it only asserts that *an* `ErrorCode` comes back,
never that the **text** shown to the user for that code matches upstream.
No prior pass opened `lib/math_equation.rb#error_message` next to
upstream's `lib/math-equation.vala` and read the two mappings side by
side. Doing that this pass (table in `component-parity.md`'s "new finding"
section) shows 8 of 9 branches display different English than upstream,
several silently dropping the `%s` token that names the actual bad
variable/unit/function, and all 8 of those strings are therefore absent
from every `.po` catalogue — a translation gap that traces to the same
root cause (`translation-parity.md`'s "new finding this pass").

This is exactly the shape this skill exists to catch: a runtime check that
is real and passes (an `ErrorCode` object comes back, not an exception) was
treated across four passes as license to not read the behaviour it stands
in for (what the user actually sees). The check was never false — the
*inference* drawn from it, that error reporting "holds parity" or needs no
further read, was false, and stood uncorrected for four passes. Fixed in
place this pass in both `component-parity.md` and `translation-parity.md`;
flagged here as the standing lesson, since the same shape of error (a
narrow live check standing in for a broader parity claim) is exactly what
let a prior pass's bindtextdomain transcript go wrong too (see below).

## Checked and clean this pass: the newly-ported host and panel

`lib/math_buttons.rb` and `lib/advanced_button_panel.rb` (both new in
`8de8a498`) were read in full against this skill's patterns. No excuse
language, no silent fallback. The one place upstream behaviour is
genuinely narrowed — Financial/Programming/Conversion modes — is handled
by `raise ArgumentError, "MathButtons has no panel for #{mode.inspect}
yet"`, a loud failure a user or test would notice immediately, not a
silent no-op or a comment claiming the mode "works for now." This is the
right shape for a known, named gap and is credited as such in
`component-identification.md`, not rounded up to "present."

## Standing risk, restated: report staleness is structural, not a one-off

Every prior pass of this report has found the *previous* pass's reports
out of date against commits that landed between write and read — the
third pass found `component-inventory.md` two commits stale; the fourth
found a false `bindtextdomain` transcript in the third pass's
`translation-parity.md`; this pass finds a four-pass-old blind spot in how
error-message parity was being inferred. The pattern is not "one report
had one bug" — it is that **every report in this directory describes a
moving target and starts decaying the moment it is committed.** Two
commits landed between the fourth pass's reports (`feb97cb0`) and this
one's starting point (`8de8a498`, `eba4d35e`), and this pass's component
reports needed real updates, not just a header-date bump, to stay honest
about them. The discipline this skill asks for — re-run every cited
command, re-read every file claimed "clean," never trust a prior pass's
prose — caught something new again this pass. Treat the next pass's
starting assumption the same way: whatever this pass says is current will
itself be at least one commit stale by the time anyone reads it.

## Checked and clean: this round's runtime gate claim

The task brief's gate (`drive_ok=true, 62 checks passed, 0 failed, 13
components`) was re-run live this pass, not taken on faith:

```
$ nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb
...
62 of 62 checks passed
DRIVE OK
```

Matches exactly. No false green here. But per `component-parity.md` and
`component-identification.md`, "62/62, 13 components" is accurately
reported by the harness and is still not evidence about the 8 units with
zero port counterpart, nor about the half of the Advanced panel's own
button grid (log/exp stack, nth-root, complex row, angle-unit menu,
constant buttons) the drive script's own step `[9]` does not touch. A
passing narrow gate is not being treated as a passing wide one anywhere in
this pass's reports — stated explicitly in each.

## Verdict

No excuse-language violation found in `lib/`/`exe/` this pass. One
multi-pass false inference (error-message parity) found and corrected.
`PORTING.md` absence stands, now across five passes, and is reportable as
its own small accountability item: a port this far along ought to have a
tracking document, and not having one makes exactly the kind of drift this
report keeps finding easier to miss for longer.
