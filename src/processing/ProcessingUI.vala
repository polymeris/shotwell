public class ProcessingUI : Gtk.ScrolledWindow {
    public Photo photo;
    
    public ProcessingUI() {
        Gtk.Grid grid = new Gtk.Grid();
        grid.set_row_spacing(2);
        int i = 0;
        foreach (Spit.Pluggable p in Plugins.get_pluggables_for_type(typeof(Spit.Processing.Tool))) {
                Spit.Processing.Tool tool = p as Spit.Processing.Tool;
            Gtk.ToggleButton button = new Gtk.ToggleButton();
            Spit.PluggableInfo info = new Spit.PluggableInfo();
            // TODO: why multiple icons?
            tool.get_info(ref info);
            button.set_image(new Gtk.Image.from_pixbuf(info.icons[0]));
            button.set_tooltip_text(tool.get_help_text());
            // TODO: more generic for other widgets
            Gtk.Scale? parameter = get_parameter_widget(tool)
                as Gtk.Scale?;
            if (parameter != null) {
                parameter.set_sensitive(false);
                parameter.set_hexpand(true);
                button.toggled.connect((b) => parameter.set_sensitive(b.get_active()));
                parameter.value_changed.connect((p) => this.update_tool(tool, button, p));
                grid.attach(parameter, 1, i, 1, 1);
            }
            button.toggled.connect((b) => this.update_tool(tool, b, parameter));
            grid.attach(button, 0, i++, 1, 1);
        }
        this.add_with_viewport(grid);
    }

    protected Gtk.Widget? get_parameter_widget(
        Spit.Processing.Tool tool) {
        switch (tool.get_parameter_type()) {
            case Spit.Processing.ParameterType.RANGE_DISCRETE:
                Gtk.Scale? scale = new Gtk.HScale.with_range(0, 3, 1);
//~                 scale.set_has_origin(true);
//~                 scale.set_draw_value(false);
                // strangely, the previous call resets the step
                return scale;
            default:
                return null;
        }
    }

    public void update_tool(Spit.Processing.Tool tool,
        Gtk.ToggleButton b, Gtk.Range? s) {
        bool state = b.get_active();
        switch (tool.get_parameter_type()) {
            case Spit.Processing.ParameterType.NONE:
                ToolCommand command = new ToolCommandNoParameter(photo, tool, state);
                AppWindow.get_command_manager().execute(command);
                break;
            case Spit.Processing.ParameterType.RANGE_DISCRETE:
                assert(s != null);
                int val = (state? 0 : ((int)s.get_value()));
                ToolCommand command = new ToolCommandRangeDiscrete(photo, tool, val);
                AppWindow.get_command_manager().execute(command);
                break;
        }
    }
}
