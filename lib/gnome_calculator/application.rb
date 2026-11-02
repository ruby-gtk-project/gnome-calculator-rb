# frozen_string_literal: true

require "gtk4"
require "adwaita"

module GnomeCalculator
  # The port's application: one window, and a status page standing in for the
  # calculator window. The engine behind the window — Number, the lexer and
  # parser, the function and unit managers — is ported and reachable from
  # exe/gcalccmd; math_window.rb replaces the status page here.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    def build
      app.tap do
        app.signal_connect("activate") do
          window.tap do |win|
            win.content = toolbar_view
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = status_page
          end

          window.present
        end
      end
    end

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new("org.rubygtkproject.GnomeCalculator", :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = "gnome-calculator"
        win.set_default_size(800, 600)
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = "gnome-calculator"
        page.description = "Run exe/gcalccmd to evaluate expressions with the ported engine."
        page.icon_name = "applications-engineering-symbolic"
      end
    end
  end
end
