/**
 * (DRAFT!) Shotwell Photo Postprocessing API
 *
 * Plugin interface to implement postprocessing effects and filters.
 */
namespace Spit.Processing {
     
/**
 * The current version of the Photo Postprocessing API
 */
public const int CURRENT_INTERFACE = 0;

/**
 * Tools are used to apply corrections and effects in the
 * last stage of the photo rendering pipeline.
 * The user can activate them by clicking on buttons in the foto page
 * pane.
 */
public interface Tool : Object, Spit.Pluggable {
    /**
     * A factory method that instantiates and returns a new Process
     * object.
     */
    public abstract Process create_process();
    /**
     * Returns the ParameterType expected by the process.
     */
    public abstract ParameterType get_parameter_type();
    /**
     * Returns a short description of what this tool does.
     */
    public abstract string get_help_text();
//~     /**
//~      * Returns the filename of the icon to be used in the user
//~      * interface.
//~      */
//~     public abstract string get_icon();
}

public interface Process : Object {
    /**
     * Returns this process' asociated Tool
     */
    public abstract Tool get_tool();
    /**
     * Set the process' parameter value. Type of value must match
     * the one listed in the description of ParameterType.
     */
    public abstract void set_parameter_value(float value);
    /**
     * Excecute the process on the provided Pixbuf.
     */
    public abstract Gdk.Pixbuf execute(Gdk.Pixbuf pixbuf);
}

/**
 * Parameter types indicate what data the process expects and
 * how it shall be represented in the GUI.
 * Currently each Tool may have only one parameter, and there is only
 * one parameter type.
 * More types may be added later.
 */
public enum ParameterType {
    /**
     * No parameter. A boolean value controls activation.
     * Represented in the GUI by the tool's button toggling.
     */
    NONE,
    /**
     * Discrete numerical (int) type that represents the "amount" of
     * processing in the range 0 to 3, where 0 represents "off", and 1
     * to 3 represent "mild", "medium" and "strong", respectively.
     * In Shotwell's GUI this is set by a slider. (Or multiple clicks
     * on the tool's icon)
     */
    RANGE_DISCRETE
}

}
