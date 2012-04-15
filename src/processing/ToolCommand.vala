public abstract class ToolCommand : SingleDataSourceCommand {
    protected Spit.Processing.Tool tool;
    protected float parameter_value;
    
    public ToolCommand(
        Photo photo, Spit.Processing.Tool tool, float parameter_value) {
        // TODO: introduce more meaningful strings
        base(photo, tool.get_pluggable_name(), tool.get_help_text());
        
        this.tool = tool;
        this.parameter_value = parameter_value;
    }
    
    public override void execute() {
        ((Photo) source).apply_tool(tool, parameter_value);
    }

    public override void undo() {
        ((Photo) source).apply_tool(tool, -parameter_value);
    }
}

public class ToolCommandNoParameter: ToolCommand {
    public ToolCommandNoParameter(Photo ph,
        Spit.Processing.Tool t, bool val)
    {
        base(ph, t, val? 1.0f: 0.0f);
    }
}

public class ToolCommandRangeDiscrete: ToolCommand {
    public ToolCommandRangeDiscrete(Photo ph,
        Spit.Processing.Tool t, int val = 1)
    {
        base(ph, t, val);
    }
}
