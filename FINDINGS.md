# Findings

Binding limitations discovered while porting, each verified in this
checkout's nix devshell rather than taken on faith.

## "Adwaita::Application is broken in the Ruby bindings" — not reproduced

`lib/gnome_calculator/application.rb` builds its app from
`Gtk::Application`, not `Adwaita::Application`, with a comment claiming
`Adwaita::Application` "is broken in the Ruby bindings." The same claim,
word for word, is in the gnome-contacts-rb pilot port
(`lib/main.rb`: "Adwaita::Application is still broken in the bindings").

Verification attempt in this fork's devshell:

```
$ nix develop --command xvfb-run -a ruby -e '
require "gtk4"; require "adwaita"
app = Adwaita::Application.new("org.rubygtkproject.Probe", :default_flags)
app.signal_connect("activate") do
  win = Adwaita::ApplicationWindow.new(app)
  win.title = "probe"
  win.present
  GLib::Timeout.add(200) { app.quit; false }
end
app.run([])
puts "ran ok"
'
=> "ran ok"
```

This did **not** reproduce a failure: constructing `Adwaita::Application`,
connecting `activate`, presenting an `Adwaita::ApplicationWindow` owned by
it, and running the main loop to completion all worked. So the claim as
written is unverified at best on this toolchain/gtk4-gem version — it may
have been true against an older gem version, or may describe a failure
mode this smoke test doesn't exercise (e.g. combined with `Gio::Menu`
actions or `Adwaita::ToolbarView` content). This port keeps
`Gtk::Application` rather than risk a verified-broken change without
exhausting that possibility, but the claim should not be restated as fact
next to the code; `lib/gnome_calculator/application.rb` now points here
instead.

## GtkSourceView has no Ruby binding in this toolchain

Upstream's `MathEquation` (`lib/math-equation.vala`) subclasses
`GtkSource.Buffer` for its syntax highlighting and style-scheme theming.
Neither `gtksourceview4` nor `gtksourceview5` load in this fork's devshell:

```
$ nix develop --command xvfb-run -a ruby -e 'require "gtksourceview4"'
cannot load such file -- gtksourceview4
$ nix develop --command xvfb-run -a ruby -e 'require "gtksourceview5"'
cannot load such file -- gtksourceview5
```

`lib/math_equation.rb` is built on a plain `Gtk::TextBuffer` instead. The
parts of upstream's behaviour that depend specifically on `GtkSource.Buffer`
(the Classic/Classic-dark style schemes, syntax highlighting) are not
carried over; the answer-bolding (`ans_tag`) and the rest of the equation
state machine are, since `Gtk::TextBuffer` supports tags on its own.

## GLib::Variant cannot construct a tuple (`(ss)`, etc.) from a Ruby Array

Upstream's `cal.insert-brackets` action takes a `(ss)` tuple — opening and
closing bracket — as its parameter type. Constructing that from the Ruby
bindings fails outright:

```
$ nix develop --command xvfb-run -a ruby -e '
require "gtk4"
GLib::Variant.new(["(", ")"], GLib::VariantType.new("(ss)"))
'
TODO: Ruby -> GVariant((ss)): ["(", ")"] (NotImplementedError)
```

`lib/math_buttons.rb`'s `insert-brackets` action takes a plain `s` instead
— the two characters concatenated ("()", "[]", "||") — and splits them
apart in the handler. Scalar variant types (`s`, `i`, the stateful action's
default) all construct fine; only the tuple signature is affected.

## Adwaita::ShortcutsItem rejects every documented keyword-argument signature

`lib/math_shortcuts.rb`'s class comment already asserted this; this entry
is the smoke test proving it, owed since an earlier accountability pass
flagged the claim as unverified in FINDINGS.md:

```
$ nix develop --command xvfb-run -a ruby -e '
require "gtk4"
require "adwaita"
Adwaita::ShortcutsItem.new(title: "Open", accelerator: "<Ctrl>N")
'
ArgumentError: wrong arguments: Adwaita::ShortcutsItem#initialize({title: "Open", accelerator: "<Ctrl>N"}):
available signatures:
Adwaita::ShortcutsItem#initialize(title: utf8, accelerator: utf8)
Adwaita::ShortcutsItem#initialize(title: utf8, action_name: utf8)
```

The call matches a listed signature exactly (`title:`/`accelerator:`, both
`utf8`/String) and is still rejected — the loader's own error message
contradicts itself, so this is a binding bug in the keyword-argument path
for this GObject-Introspection constructor, not a usage mistake.
`lib/math_shortcuts.rb` works around it by never constructing
`Adwaita::ShortcutsItem` at all: it renders the same sections over a plain
`Adwaita::Dialog` and label/accelerator rows instead.
