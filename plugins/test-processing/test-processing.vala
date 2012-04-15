/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
 
private class TestProcessingModule : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public TestProcessingModule(GLib.File module_file) {        
        pluggables += new Spit.Processing.TestTool();
        pluggables += new Spit.Processing.TestTool2();
    }
    
    public unowned string get_module_name() {
        return _("Test Processing Module");
    }
    
    public unowned string get_version() {
        return "0.1";
    }
    
    public unowned string get_id() {
        return "org.yorba.shotwell.processing.test";
    }
    
    public unowned Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

// This entry point is required for all SPIT modules.
public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    params->module_spit_interface = Spit.negotiate_interfaces(params->host_min_spit_interface,
        params->host_max_spit_interface, Spit.CURRENT_INTERFACE);
    
    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new TestProcessingModule(params->module_file) : null;
}

