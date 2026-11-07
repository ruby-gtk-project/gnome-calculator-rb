# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "../math_window"

module GnomeCalculator
  # The port's application: one window, built by MathWindow, with the
  # ported style sheet attached at application priority.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    def build
      app.tap do
        app.signal_connect("activate") do
          # 600 is GTK_STYLE_PROVIDER_PRIORITY_APPLICATION; the Ruby bindings
          # do not expose the constant.
          Gtk::StyleContext.add_provider_for_display(Gdk::Display.default, css_provider, 600)

          math_window.build.present
        end
      end
    end

    # The application object comes from Gtk, not Adwaita; see FINDINGS.md
    # ("Adwaita::Application is broken in the Ruby bindings" — not
    # reproduced) for why and what was actually checked.
    def app = @app ||= Gtk::Application.new("org.rubygtkproject.GnomeCalculator", :default_flags)

    def math_window = @math_window ||= MathWindow.new(app)

    # Ported from upstream's src/ui/style.css.
    def css_provider
      @css_provider ||= Gtk::CssProvider.new.tap do |provider|
        provider.load_from_path(File.join(__dir__, "..", "style.css"))
      end
    end
  end
end
