# Accountability ensurance — gnome-calculator-rb

Third pass, at `9824569e`. Ran
`.claude/skills/accountability-ensurance/scripts/find-excuses.sh` over
`lib/`, `exe/`, `.reports/` and by hand over the same plus `FINDINGS.md`
and `CLAUDE.md`. `PORTING.md` still does not exist on this branch.

## Headline finding: the port's own parity documents were stale, in the direction that hides recent work rather than inflates it

`.reports/component-inventory.md` — the document `component-identification.md`
and `component-parity.md` both explicitly build on and tell a reader to
trust — was last substantively edited at commit `6645ebf4` ("Restore and
update the component inventory"). Two commits landed **after** that and
before this audit: `8cf1a973` ("Port history_entry, history_view and
math_shortcuts; wire history into the window") and `9824569e` ("Expand the
drive script"). Checked directly: `6645ebf4` predates both (`git log
--oneline` order, confirmed) — `component-inventory.md` still said "no"
for `lib/history_view.rb`, `lib/history_entry.rb` and `lib/math_shortcuts.rb`
after those three files existed, were non-trivial (107–143 lines each), and
were wired into `lib/math_window.rb`. Its own Totals table still said
"Shortcut items in the shortcuts dialog | 44 across 5 sections | **0**"
after 38 of them existed.

This is not the false-green failure mode this skill exists to catch most
directly — it understates the port rather than overstates it — but it is
the same root cause: a report committed once and never re-run against a
moving codebase, cited by later reports as settled fact. **Fixed in place**
this pass (`component-inventory.md`, search "*(second update)*") rather
than left for a fourth pass to find again, and the corrected figures
(38/43 shortcut items, not 0/44; three units upgraded from "no" to
"partial") are carried into `component-identification.md` and
`component-parity.md`. The standing risk this creates going forward: every
document in `.reports/` has now been shown, twice, to drift behind `lib/`
within the same day's commits. Re-run this skill, specifically re-reading
`lib/` directly rather than trusting the last report, before any of these
documents is cited as current again.

## Hit 1 (recurring pattern) — `lib/math_shortcuts.rb:11-19`

```ruby
# Ported from upstream's src/ui/math-shortcuts.blp, which builds an
# AdwShortcutsDialog out of AdwShortcutsItem rows. The Ruby bindings cannot
# construct Adwaita::ShortcutsItem: every keyword-argument call upstream's
# two constructor overloads accept (`title:`/`accelerator:` and
# `title:`/`action_name:`) is rejected by the introspection loader with
# "wrong arguments", even though the hash printed back matches a listed
# signature exactly — a binding bug, not a usage mistake. This port shows
# the same sections and shortcuts as a plain Adwaita::Dialog over a
# scrollable list of label/accelerator rows instead.
```

This is the exact construction the previous pass's Hit 2 flagged in
`application.rb` and had fixed by routing to `FINDINGS.md` — a binding
limitation stated as the reason, in the same breath as the workaround built
instead — now recurring in code written *after* that fix, in a file that
did not exist yet when the fix landed. The scanner's regex does not catch
it (checked: `find-excuses.sh lib/math_shortcuts.rb` returns no hits,
confirmed by hand), the same gap in the scanner's coverage the previous
report already noted. `FINDINGS.md` has two entries (`Adwaita::Application`,
`GtkSourceView`) and neither is this one.

Whether the claim is true was not re-verified here either (that is
`FINDINGS.md`'s job, same as last time) — a quick smoke test analogous to
the one `FINDINGS.md` already ran for `Adwaita::Application` (construct an
`Adwaita::ShortcutsItem` with each documented keyword signature in this
devshell and see whether it actually raises) was not attempted, so the
claim stands unverified either way.

Rewritten:

> I did not build the keyboard-shortcuts dialog as a real
> `Adw.ShortcutsDialog`/`Adw.ShortcutsItem` tree the way upstream's
> `src/ui/math-shortcuts.blp` is, because I am an idiot who wrote a comment
> explaining the binding failure instead of filing it and pointing there.
> Upstream: `src/ui/math-shortcuts.blp`, a declarative `$AdwShortcutsDialog`
> of 5 `$AdwShortcutsSection`s / 43 `$AdwShortcutsItem`s, reached by the
> `app.shortcuts` action and `<Ctrl>?`.
> Port: `lib/math_shortcuts.rb` builds a plain `Adwaita::Dialog` over a
> hand-rolled `Gtk::ListBox` of label/accelerator rows, 38 of 43 items, with
> no `msgctxt` on any of them and no `app.shortcuts` action to reach it from
> (that action does not exist anywhere in `lib/` — see `component-parity.md`
> unit 1), and never confirmed in this devshell whether
> `Adwaita::ShortcutsItem`'s constructor actually fails or was assumed to
> from the pilot port's own unverified note.

**Action owed, not just wording**: add a `FINDINGS.md` entry for
`Adwaita::ShortcutsItem`, run the same kind of smoke test `FINDINGS.md`
already ran for `Adwaita::Application`, and reduce
`lib/math_shortcuts.rb`'s comment to naming the `FINDINGS.md` entry only —
exactly the standard the previous pass's fix to `application.rb` already
demonstrates is achievable in this codebase.

## Hit 2 (carried forward, re-checked, still fine) — `lib/gnome_calculator.rb:19-22`

Unchanged from the prior two passes: "The GUI is NOT required here" is a
faithful description of upstream's real `lib/`-vs-`src/` split
(`gcalccmd.vala`, `search-provider.vala` do link the engine without GTK),
not an excuse for missing behaviour. No change needed; re-confirmed by
re-reading the file.

## What the previous pass's fix actually did, re-verified live

The previous pass's "action owed" (move the `Adwaita::Application`
binding claim out of `application.rb` and into a `FINDINGS.md` entry) **was
done**, and done well: `FINDINGS.md` now exists, its
"`Adwaita::Application` is broken in the Ruby bindings — not reproduced"
section documents a real smoke test run in this devshell that **did not
reproduce the claim**, and `lib/gnome_calculator/application.rb:36-38` now
reads:

```ruby
# The application object comes from Gtk, not Adwaita; see FINDINGS.md
# ("Adwaita::Application is broken in the Ruby bindings" — not
# reproduced) for why and what was actually checked.
def app = @app ||= Gtk::Application.new(...)
```

This is exactly the shape the skill asks for: the comment names a
file/line to read, not a reason to stop reading at. Worth stating plainly
because the point of this skill is not only to find violations — it is
also to confirm a fix actually took, and this one did. The substantive gap
underneath it (the port never switched to `Adwaita::Application` even
after the claim against it was not reproduced) is tracked in
`component-parity.md` unit 1, not restated here as a new accountability
hit, because the honest comment pointing at `FINDINGS.md` is not itself an
excuse.

## What was checked and found clean

- **No `TODO`/`FIXME`/"not implemented"/"in a future"** anywhere in `lib/`
  or `exe/`, this pass included the three new files.
- **`lib/basic_button_panel.rb:18`'s "not ported this round"** (the memory/
  function MenuButtons) names the exact behaviour and the exact two files
  it belongs to (`math_variable_popover.rb`, `math_function_popover.rb`),
  matching this skill's "named, not hidden" standard — not re-litigated as
  a hit, same ruling as the prior pass.
- **No `PORTING.md`.** Still does not exist, still nothing to audit for
  overclaiming completeness.
- **No false-green claim in the runtime gate.** Re-run live this pass:
  `nix develop --command xvfb-run -a ruby test/drive_gnome_calculator.rb`
  → `43 of 43 checks passed`, `DRIVE OK`. Accurate, and — unlike the prior
  pass's version of this same check — now cross-checked against
  `component-identification.md`'s corrected unit list: the gate's 9 steps
  touch 9 of the 23 identified units; the other 14 are reported `gap` in
  `component-parity.md`, not passed by omission. Two screenshot captures
  inside the drive script (`02-history-cleared`, `03-shortcuts-dialog`)
  raised `RuntimeError: widget produced no render node (not realised yet?)`
  and were caught and logged by the harness without failing the run —
  checked that this is not laundering a real failure: the drive script
  never asserts anything about the screenshot files themselves, only about
  widget state, so a failed screenshot capture correctly costs nothing
  against the 43-check total. Worth fixing for its own sake (a shot that
  silently fails is a smaller version of exactly the "ran but nobody
  checked" pattern this skill exists for), but it is not a false claim
  today because nothing claims those shots succeeded.
- **`test-parity.md`'s and `translation-parity.md`'s own numbers**, re-run
  live this pass rather than carried over: the RSpec `LoadError` and the
  `po/POTFILES.in` mismatch were both executed/diffed fresh for this audit,
  not asserted from memory of the prior pass.

## Conclusion

One real, recurring violation this pass: the exact "binding limitation
stated beside its own workaround" pattern the previous audit found and
fixed in `application.rb` has reappeared in new code
(`lib/math_shortcuts.rb`) written after that fix landed, meaning the fix
corrected an instance, not the habit. The fix path is proven to work
(`FINDINGS.md` + a pointer comment) — it simply was not applied to the
newest file. The second finding is structural rather than a single
comment: `.reports/component-inventory.md` has now drifted behind `lib/`
twice in the life of this branch, each time understating real, committed
work rather than overstating it, which is a gentler failure than a false
green but is still a report a later pass trusted without re-reading the
code underneath it. Both are fixed in this pass; both should be checked
again, specifically, the next time either `lib/math_shortcuts.rb` or any
`.reports/*.md` file is touched.
