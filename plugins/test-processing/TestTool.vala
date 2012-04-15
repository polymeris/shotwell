namespace Spit.Processing {
    
public class TestTool : GLib.Object, Spit.Pluggable, Spit.Processing.Tool {
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Transitions.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.processing.testtool";
    }

    public unowned string get_pluggable_name() {
        return "Test Tool";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Camilo Polymeris";
        info.copyright = _("Copyright 2012 Camilo Polymeris");
//~         info.translators = Resources.TRANSLATORS;
//~         info.version = _VERSION;
//~         info.website_name = Resources.WEBSITE_NAME;
//~         info.website_url = Resources.WEBSITE_URL;
//~         info.is_license_wordwrapped = false;
//~         info.license = Resources.LICENSE;
        try {
            info.icons = {new Gdk.Pixbuf.from_file("icons/sprocket.png")};
        } catch {
            info.icons = null;
        }
    }

    public void activation(bool enabled) {}
    
    public Spit.Processing.Process create_process() {
        return new TestProcess(this, -1.0f);
    }

    public Spit.Processing.ParameterType get_parameter_type() {
        return ParameterType.NONE;
    }
    
    public string get_help_text() {
        return "Just a test tool - desaturates your image.";
    }
}

public class TestTool2 : GLib.Object, Spit.Pluggable, Spit.Processing.Tool {
    public int get_pluggable_interface(int min_host_interface, int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Transitions.CURRENT_INTERFACE);
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.processing.testtool2";
    }

    public unowned string get_pluggable_name() {
        return "Test Tool #2";
    }
    
    public void get_info(ref Spit.PluggableInfo info) {
        info.authors = "Camilo Polymeris";
        info.copyright = _("Copyright 2012 Camilo Polymeris");
//~         info.translators = Resources.TRANSLATORS;
//~         info.version = _VERSION;
//~         info.website_name = Resources.WEBSITE_NAME;
//~         info.website_url = Resources.WEBSITE_URL;
//~         info.is_license_wordwrapped = false;
//~         info.license = Resources.LICENSE;
        try {
        info.icons = {new Gdk.Pixbuf.from_file("icons/generic-plugin.png")};
        }
        catch {
            info.icons = null;
        }
    }

    public void activation(bool enabled) {}
    
    public Spit.Processing.Process create_process() {
        return new TestProcess(this, 0.5f);
    }

    public Spit.Processing.ParameterType get_parameter_type() {
        return ParameterType.RANGE_DISCRETE;
    }
    
    public string get_help_text() {
        return "Just a copy of a test tool - saturates your image.";
    }
}


public class TestProcess : GLib.Object, Spit.Processing.Process {
    private Tool tool;
    private float factor;
    private float val;
    
    public TestProcess(Tool tool, float factor) {
        this.tool = tool;
        this.factor = factor;
    }

    public Spit.Processing.Tool get_tool() {
        return tool;
    }

    public void set_parameter_value(float value) {
        val = value;
    }

    public Gdk.Pixbuf execute(Gdk.Pixbuf pixbuf) {
        pixbuf.saturate_and_pixelate(pixbuf,
            1.0f + val * factor,
            false);
        return pixbuf;
    }
}
}
