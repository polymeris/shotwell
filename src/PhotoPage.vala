/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class CropToolWindow : Gtk.Window {
    public static const int CONTROL_SPACING = 8;
    public static const int WINDOW_BORDER = 8;
    
    public Gtk.Button apply_button = new Gtk.Button.from_stock(Gtk.STOCK_APPLY);
    public Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);
    public bool user_moved = false;

    private Gtk.Window owner;
    private Gtk.HBox layout = new Gtk.HBox(false, CONTROL_SPACING);
    private Gtk.Frame layout_frame = new Gtk.Frame(null);
    
    public CropToolWindow(Gtk.Window owner) {
        this.owner = owner;
        
        type_hint = Gdk.WindowTypeHint.TOOLBAR;
        set_transient_for(owner);
        unset_flags(Gtk.WidgetFlags.CAN_FOCUS);
        set_accept_focus(false);
        set_focus_on_map(false);
        
        apply_button.set_tooltip_text("Set the crop for this photo");
        cancel_button.set_tooltip_text("Return to current photo dimensions");
        
        apply_button.set_image_position(Gtk.PositionType.LEFT);
        cancel_button.set_image_position(Gtk.PositionType.LEFT);
        
        layout.set_border_width(WINDOW_BORDER);
        layout.add(apply_button);
        layout.add(cancel_button);
        
        layout_frame.set_border_width(0);
        layout_frame.set_shadow_type(Gtk.ShadowType.OUT);
        layout_frame.add(layout);
        
        add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.FOCUS_CHANGE_MASK);
        
        add(layout_frame);
    }
    
    private override bool button_press_event(Gdk.EventButton event) {
        // LMB only
        if (event.button != 1)
            return (base.button_press_event != null) ? base.button_press_event(event) : true;
        
        begin_move_drag((int) event.button, (int) event.x_root, (int) event.y_root, event.time);
        user_moved = true;
        
        return true;
    }
    
    private override void realize() {
        set_opacity(FullscreenWindow.TOOLBAR_OPACITY);
        
        base.realize();
    }
    
    // This is necessary because some window managers (Metacity seems to be guilty of it) seem to
    // ignore the set_focus_on_map flag, and give the toolbar focus when it appears on the screen.
    // Thereafter, thanks to set_accept_focus, the toolbar will never accept it.  Because changing
    // focus inside of a focus signal seems to be problematic, if the toolbar ever does receive
    // focus, it schedules a task to give it back to its owner.
    private override bool focus(Gtk.DirectionType direction) {
        Idle.add_full(Priority.HIGH, unsteal_focus);
        
        return true;
    }
    
    private bool unsteal_focus() {
        owner.present_with_time(Gdk.CURRENT_TIME);
        
        return false;
    }
}

public class PhotoPage : SinglePhotoPage {
    public static const double CROP_INIT_X_PCT = 0.15;
    public static const double CROP_INIT_Y_PCT = 0.15;
    public static const int CROP_MIN_WIDTH = 100;
    public static const int CROP_MIN_HEIGHT = 100;
    public static const float CROP_SATURATION = 0.00f;
    public static const int CROP_EXTERIOR_RED_SHIFT = -32;
    public static const int CROP_EXTERIOR_GREEN_SHIFT = -32;
    public static const int CROP_EXTERIOR_BLUE_SHIFT = -32;
    public static const int CROP_EXTERIOR_ALPHA_SHIFT = 0;
    
    public static const int CROP_TOOL_WINDOW_SEPARATOR = 8;
    
    private Gtk.Window container = null;
    private Gtk.Menu context_menu;
    private CheckerboardPage controller = null;
    private Photo photo = null;
    private Thumbnail thumbnail = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToggleToolButton crop_button = null;
    private Gtk.ToolButton prev_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
    private Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
    private Gdk.CursorType current_cursor_type = Gdk.CursorType.ARROW;
    private BoxLocation in_manipulation = BoxLocation.OUTSIDE;
    private Gdk.GC wide_black_gc = null;
    private Gdk.GC wide_white_gc = null;
    private Gdk.GC thin_white_gc = null;
    
    // cropping
    private bool show_crop = false;
    private Box scaled_crop;
    private CropToolWindow crop_tool_window = null;
    private Gdk.Pixbuf color_shifted = null;

    // these are kept in absolute coordinates, not relative to photo's position on canvas
    private int last_grab_x = -1;
    private int last_grab_y = -1;
    
    // drag-and-drop state
    private File drag_file = null;
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "FileMenu", null, "_File", null, null, null },
        { "Export", Gtk.STOCK_SAVE_AS, "_Export", "<Ctrl>E", "Export photo to disk", on_export },
        
        { "ViewMenu", null, "_View", null, null, on_view_menu },
        { "ReturnToPage", Resources.RETURN_TO_PAGE, "_Return to Photos", "Escape", null, on_return_to_collection },

        { "PhotoMenu", null, "_Photo", null, null, on_photo_menu },
        { "PrevPhoto", Gtk.STOCK_GO_BACK, "_Previous Photo", null, "Previous Photo", on_previous_photo },
        { "NextPhoto", Gtk.STOCK_GO_FORWARD, "_Next Photo", null, "Next Photo", on_next_photo },
        { "RotateClockwise", Resources.CLOCKWISE, "Rotate _Right", "<Ctrl>R", "Rotate the selected photos clockwise", on_rotate_clockwise },
        { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE, "Rotate _Left", "<Ctrl><Shift>R", "Rotate the selected photos counterclockwise", on_rotate_counterclockwise },
        { "Mirror", Resources.MIRROR, "_Mirror", "<Ctrl>M", "Make mirror images of the selected photos", on_mirror },
        { "Revert", Gtk.STOCK_REVERT_TO_SAVED, "Re_vert to Original", null, "Revert to the original photo", on_revert },

        { "HelpMenu", null, "_Help", null, null, null }
    };
    
    public PhotoPage() {
        base("Photo");
        
        init_ui("photo.ui", "/PhotoMenuBar", "PhotoActionGroup", ACTIONS);

        context_menu = (Gtk.Menu) ui.get_widget("/PhotoContextMenu");

        // set up page's toolbar (used by AppWindow for layout and FullscreenWindow as a popup)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
        rotate_button.clicked += on_rotate_clockwise;
        toolbar.insert(rotate_button, -1);
        
        // crop tool
        crop_button = new Gtk.ToggleToolButton.from_stock(Resources.CROP);
        crop_button.set_label("Crop");
        crop_button.set_tooltip_text("Crop the photo's size");
        crop_button.toggled += on_crop_toggled;
        toolbar.insert(crop_button, -1);
        
        // separator to force next/prev buttons to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // previous button
        prev_button.set_tooltip_text("Previous photo");
        prev_button.clicked += on_previous_photo;
        toolbar.insert(prev_button, -1);
        
        // next button
        next_button.set_tooltip_text("Next photo");
        next_button.clicked += on_next_photo;
        toolbar.insert(next_button, -1);
        
    }
    
    public void set_container(Gtk.Window container) {
        // this should only be called once
        assert(this.container == null);

        this.container = container;

        // DnD only available in full-window view
        if (!(container is FullscreenWindow))
            enable_drag_source(Gdk.DragAction.COPY);
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public CheckerboardPage get_controller() {
        return controller;
    }
    
    public Thumbnail get_thumbnail() {
        return thumbnail;
    }
    
    public override void switching_from() {
        base.switching_from();

        deactivate_crop();
    }
    
    public override void switching_to_fullscreen() {
        base.switching_to_fullscreen();

        deactivate_crop();
    }
    
    public void display(CheckerboardPage controller, Thumbnail thumbnail) {
        this.controller = controller;
        this.thumbnail = thumbnail;
        
        set_page_name(thumbnail.get_title());
        
        update_display();
        update_sensitivity();
    }
    
    private void update_display() {
        if (photo != null)
            photo.altered -= on_photo_altered;
            
        photo = thumbnail.get_photo();
        photo.altered += on_photo_altered;
        
        set_pixbuf(photo.get_pixbuf());
    }
    
    private void update_sensitivity() {
        bool multiple = controller.get_count() > 1;
        
        prev_button.sensitive = multiple;
        next_button.sensitive = multiple;
    }

    private override void drag_begin(Gdk.DragContext context) {
        // drag_data_get may be called multiple times within a drag as different applications
        // query for target type and information ... to prevent a lot of file generation, do all
        // the work up front
        File file = null;
        try {
            file = photo.generate_exportable();
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // set up icon for drag-and-drop
        Gdk.Pixbuf icon = photo.get_thumbnail(ThumbnailCache.MEDIUM_SCALE);
        Gtk.drag_source_set_icon_pixbuf(canvas, icon);

        debug("Prepared for export %s", file.get_path());
        
        drag_file = file;
    }
    
    private override void drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        assert(target_type == TargetType.URI_LIST);
        
        if (drag_file == null)
            return;
        
        string[] uris = new string[1];
        uris[0] = drag_file.get_uri();
        
        selection_data.set_uris(uris);
    }
    
    private override void drag_end(Gdk.DragContext context) {
        drag_file = null;
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_file = null;
        
        return false;
    }
    
    // Return true to block the DnD handler from activating a drag
    private override bool on_left_click(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS && !show_crop) {
            on_return_to_collection();
            
            return true;
        }
        
        int x = (int) event.x;
        int y = (int) event.y;
        
        Gdk.Rectangle scaled_pos = get_scaled_position();
        
        // only concerned about mouse-downs on the pixbuf ... return true prevents DnD when the
        // user drags outside the displayed photo
        if (!coord_in_rectangle(x, y, scaled_pos))
            return true;
        
        // only interested in LMB in regards to crop tool
        if (!show_crop)
            return false;
        
        // scaled_crop is not maintained relative to photo's position on canvas
        Box offset_scaled_crop = scaled_crop.get_offset(scaled_pos.x, scaled_pos.y);
        
        in_manipulation = offset_scaled_crop.approx_location(x, y);
        last_grab_x = x -= scaled_pos.x;
        last_grab_y = y -= scaled_pos.y;
        
        // repaint because crop changes on a manipulation
        default_repaint();
        
        // block DnD handlers if crop is enabled
        return true;
    }
    
    private override bool on_left_released(Gdk.EventButton event) {
        if (in_manipulation == BoxLocation.OUTSIDE)
            return false;
        
        // end manipulation
        in_manipulation = BoxLocation.OUTSIDE;
        last_grab_x = -1;
        last_grab_y = -1;
        
        update_cursor((int) event.x, (int) event.y);
        
        // repaint because crop changes on a manipulation
        default_repaint();

        return false;
    }
    
    private override bool on_right_click(Gdk.EventButton event) {
        return on_context_menu(event);
    }
    
    private void on_view_menu() {
        Gtk.MenuItem return_item = (Gtk.MenuItem) ui.get_widget("/PhotoMenuBar/ViewMenu/ReturnToPage");
        if (return_item != null && controller != null) {
            Gtk.Label label = (Gtk.Label) return_item.get_child();
            if (label != null)
                label.set_text("Return to %s".printf(controller.get_page_name()));
        }
    }
    
    private void on_return_to_collection() {
        AppWindow.get_instance().switch_to_page(controller);
    }
    
    private void on_export() {
        ExportDialog export_dialog = new ExportDialog(1);
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;
        
        File save_as = ExportUI.choose_file(photo.get_file());
        if (save_as == null)
            return;
        
        try {
            photo.export(save_as, scale, constraint, quality);
        } catch (Error err) {
            AppWindow.error_message("Unable to export %s: %s".printf(save_as.get_path(), err.message));
        }
    }
    
    private void on_photo_altered(Photo p) {
        assert(photo.equals(p));
        
        set_pixbuf(photo.get_pixbuf());
    }
    
    private override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        if (!show_crop)
            return false;
        
        if (in_manipulation != BoxLocation.OUTSIDE)
            return on_canvas_manipulation(x, y);
        
        update_cursor(x, y);
        
        return false;
    }
    
    private bool on_context_menu(Gdk.EventButton event) {
        if (photo == null)
            return false;
        
        set_item_sensitive("/PhotoContextMenu/ContextRevert", photo.has_transformations());

        context_menu.popup(null, null, null, event.button, event.time);
        
        return true;
    }
    
    private void update_cursor(int x, int y) {
        assert(show_crop);
        
        // scaled_crop is not maintained relative to photo's position on canvas
        Gdk.Rectangle scaled_pos = get_scaled_position();
        Box offset_scaled_crop = scaled_crop.get_offset(scaled_pos.x, scaled_pos.y);
        
        Gdk.CursorType cursor_type = Gdk.CursorType.ARROW;
        switch (offset_scaled_crop.approx_location(x, y)) {
            case BoxLocation.LEFT_SIDE:
                cursor_type = Gdk.CursorType.LEFT_SIDE;
            break;

            case BoxLocation.TOP_SIDE:
                cursor_type = Gdk.CursorType.TOP_SIDE;
            break;

            case BoxLocation.RIGHT_SIDE:
                cursor_type = Gdk.CursorType.RIGHT_SIDE;
            break;

            case BoxLocation.BOTTOM_SIDE:
                cursor_type = Gdk.CursorType.BOTTOM_SIDE;
            break;

            case BoxLocation.TOP_LEFT:
                cursor_type = Gdk.CursorType.TOP_LEFT_CORNER;
            break;

            case BoxLocation.BOTTOM_LEFT:
                cursor_type = Gdk.CursorType.BOTTOM_LEFT_CORNER;
            break;

            case BoxLocation.TOP_RIGHT:
                cursor_type = Gdk.CursorType.TOP_RIGHT_CORNER;
            break;

            case BoxLocation.BOTTOM_RIGHT:
                cursor_type = Gdk.CursorType.BOTTOM_RIGHT_CORNER;
            break;

            case BoxLocation.INSIDE:
                cursor_type = Gdk.CursorType.FLEUR;
            break;
            
            default:
                // use Gdk.CursorType.ARROW
            break;
        }
        
        if (cursor_type != current_cursor_type) {
            Gdk.Cursor cursor = new Gdk.Cursor(cursor_type);
            canvas.window.set_cursor(cursor);
            current_cursor_type = cursor_type;
        }
    }
    
    private bool on_canvas_manipulation(int x, int y) {
        Gdk.Rectangle scaled_pos = get_scaled_position();
        
        // scaled_crop is maintained in coordinates non-relative to photo's position on canvas ...
        // but bound tool to photo itself
        x -= scaled_pos.x;
        if (x < 0)
            x = 0;
        else if (x >= scaled_pos.width)
            x = scaled_pos.width - 1;
        
        y -= scaled_pos.y;
        if (y < 0)
            y = 0;
        else if (y >= scaled_pos.height)
            y = scaled_pos.height - 1;
        
        // need to make manipulations outside of box structure, because its methods do sanity
        // checking
        int left = scaled_crop.left;
        int top = scaled_crop.top;
        int right = scaled_crop.right;
        int bottom = scaled_crop.bottom;

        switch (in_manipulation) {
            case BoxLocation.LEFT_SIDE:
                left = x;
            break;

            case BoxLocation.TOP_SIDE:
                top = y;
            break;

            case BoxLocation.RIGHT_SIDE:
                right = x;
            break;

            case BoxLocation.BOTTOM_SIDE:
                bottom = y;
            break;

            case BoxLocation.TOP_LEFT:
                top = y;
                left = x;
            break;

            case BoxLocation.BOTTOM_LEFT:
                bottom = y;
                left = x;
            break;

            case BoxLocation.TOP_RIGHT:
                top = y;
                right = x;
            break;

            case BoxLocation.BOTTOM_RIGHT:
                bottom = y;
                right = x;
            break;

            case BoxLocation.INSIDE:
                assert(last_grab_x >= 0);
                assert(last_grab_y >= 0);
                
                int delta_x = (x - last_grab_x);
                int delta_y = (y - last_grab_y);
                
                last_grab_x = x;
                last_grab_y = y;

                int width = right - left + 1;
                int height = bottom - top + 1;
                
                left += delta_x;
                top += delta_y;
                right += delta_x;
                bottom += delta_y;
                
                // bound crop inside of photo
                if (left < 0)
                    left = 0;
                
                if (top < 0)
                    top = 0;
                
                if (right >= scaled_pos.width)
                    right = scaled_pos.width - 1;
                
                if (bottom >= scaled_pos.height)
                    bottom = scaled_pos.height - 1;
                
                int adj_width = right - left + 1;
                int adj_height = bottom - top + 1;
                
                // don't let adjustments affect the size of the crop
                if (adj_width != width) {
                    if (delta_x < 0)
                        right = left + width - 1;
                    else
                        left = right - width + 1;
                }
                
                if (adj_height != height) {
                    if (delta_y < 0)
                        bottom = top + height - 1;
                    else
                        top = bottom - height + 1;
                }
            break;
            
            default:
                // do nothing, not even a repaint
                return false;
        }
        
        int width = right - left + 1;
        int height = bottom - top + 1;
        
        // max sure minimums are respected ... have to adjust the right value depending on what's
        // being manipulated
        switch (in_manipulation) {
            case BoxLocation.LEFT_SIDE:
            case BoxLocation.TOP_LEFT:
            case BoxLocation.BOTTOM_LEFT:
                if (width < CROP_MIN_WIDTH)
                    left = right - CROP_MIN_WIDTH;
            break;
            
            case BoxLocation.RIGHT_SIDE:
            case BoxLocation.TOP_RIGHT:
            case BoxLocation.BOTTOM_RIGHT:
                if (width < CROP_MIN_WIDTH)
                    right = left + CROP_MIN_WIDTH;
            break;

            default:
            break;
        }

        switch (in_manipulation) {
            case BoxLocation.TOP_SIDE:
            case BoxLocation.TOP_LEFT:
            case BoxLocation.TOP_RIGHT:
                if (height < CROP_MIN_HEIGHT)
                    top = bottom - CROP_MIN_HEIGHT;
            break;

            case BoxLocation.BOTTOM_SIDE:
            case BoxLocation.BOTTOM_LEFT:
            case BoxLocation.BOTTOM_RIGHT:
                if (height < CROP_MIN_HEIGHT)
                    bottom = top + CROP_MIN_HEIGHT;
            break;
            
            default:
            break;
        }
        
        Box new_crop = Box(left, top, right, bottom);
        
        if (in_manipulation != BoxLocation.INSIDE)
            crop_resized(new_crop);
        else
            crop_moved(new_crop);
        
        // load new values
        scaled_crop = new_crop;

        return false;
    }
    
    private override bool on_configure(Gdk.EventConfigure event, Gdk.Rectangle rect) {
        // if crop window is present and the user hasn't touched it, it moves with the window
        if (crop_tool_window != null && !crop_tool_window.user_moved)
            place_crop_tool_window();
        
        return false;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Left":
            case "KP_Left":
                on_previous_photo();
            break;
            
            case "Right":
            case "KP_Right":
                on_next_photo();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }
    
    protected override void new_drawable(Gdk.Drawable drawable) {
        // set up GC's for painting the crop tool
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = fetch_color("#000", drawable);
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = 1;
        gc_values.line_style = Gdk.LineStyle.SOLID;
        gc_values.cap_style = Gdk.CapStyle.BUTT;
        gc_values.join_style = Gdk.JoinStyle.MITER;

        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND
            | Gdk.GCValuesMask.FUNCTION
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH 
            | Gdk.GCValuesMask.LINE_STYLE
            | Gdk.GCValuesMask.CAP_STYLE
            | Gdk.GCValuesMask.JOIN_STYLE;

        wide_black_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
        
        gc_values.foreground = fetch_color("#FFF", drawable);
        
        wide_white_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
        
        gc_values.line_width = 0;
        
        thin_white_gc = new Gdk.GC.with_values(drawable, gc_values, mask);
    }
    
    protected override void updated_pixbuf(Gdk.Pixbuf pixbuf, SinglePhotoPage.UpdateReason reason, 
        Dimensions old_dim) {
        color_shifted = null;
        
        if (!show_crop)
            return;
            
        // create color shifted pixbuf for crop tool
        color_shifted = pixbuf.copy();
        shift_colors(color_shifted, CROP_EXTERIOR_RED_SHIFT, CROP_EXTERIOR_GREEN_SHIFT,
            CROP_EXTERIOR_BLUE_SHIFT, CROP_EXTERIOR_ALPHA_SHIFT);

        if (reason == UpdateReason.NEW_PHOTO)
            init_crop();
        else if (reason == UpdateReason.RESIZED_CANVAS)
            rescale_crop(old_dim, Dimensions.for_pixbuf(pixbuf));
    }
    
    protected override void paint(Gdk.GC gc, Gdk.Drawable drawable) {
        if (show_crop)
            draw_with_crop(gc, drawable);
        else
            base.paint(gc, drawable);
    }

    private void rotate(Rotation rotation) {
        deactivate_crop();
        
        // let the signal generate a repaint
        photo.rotate(rotation);
    }
    
    private void on_rotate_clockwise() {
        rotate(Rotation.CLOCKWISE);
    }
    
    private void on_rotate_counterclockwise() {
        rotate(Rotation.COUNTERCLOCKWISE);
    }
    
    private void on_mirror() {
        rotate(Rotation.MIRROR);
    }
    
    private void on_revert() {
        photo.remove_all_transformations();
    }

    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_COUNTERCLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_COUNTERCLOCKWISE_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CLOCKWISE_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CLOCKWISE_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private void on_crop_toggled() {
        if (crop_button.active)
            activate_crop();
        else
            deactivate_crop();
    }
    
    private void place_crop_tool_window() {
        assert(crop_tool_window != null);

        Gtk.Requisition req;
        crop_tool_window.size_request(out req);

        if (container == AppWindow.get_instance()) {
            // Normal: position crop tool window centered on viewport/canvas at the bottom, straddling
            // the canvas and the toolbar
            int rx, ry;
            container.window.get_root_origin(out rx, out ry);
            
            int cx, cy, cwidth, cheight;
            cx = viewport.allocation.x;
            cy = viewport.allocation.y;
            cwidth = viewport.allocation.width;
            cheight = viewport.allocation.height;
            
            crop_tool_window.move(rx + cx + (cwidth / 2) - (req.width / 2), ry + cy + cheight);
        } else {
            // Fullscreen: position crop tool window centered on screen at the bottom, just above the
            // toolbar
            Gtk.Requisition toolbar_req;
            toolbar.size_request(out toolbar_req);
            
            Gdk.Screen screen = container.get_screen();
            int x = (screen.get_width() - req.width) / 2;
            int y = screen.get_height() - toolbar_req.height - req.height - CROP_TOOL_WINDOW_SEPARATOR;
            
            crop_tool_window.move(x, y);
        }
    }
    
    private void activate_crop() {
        if (show_crop)
            return;
            
        show_crop = true;
        
        // show uncropped photo for editing
        set_pixbuf(photo.get_pixbuf(Photo.EXCEPTION_CROP));

        crop_button.set_active(true);

        crop_tool_window = new CropToolWindow(container);
        crop_tool_window.apply_button.clicked += on_crop_apply;
        crop_tool_window.cancel_button.clicked += on_crop_cancel;
        crop_tool_window.show_all();
        
        place_crop_tool_window();
    }
    
    private void deactivate_crop() {
        if (!show_crop)
            return;
        
        show_crop = false;

        if (crop_tool_window != null) {
            crop_tool_window.hide();
            crop_tool_window = null;
        }
        
        crop_button.set_active(false);
        
        // make sure the cursor isn't set to a modify indicator
        canvas.window.set_cursor(new Gdk.Cursor(Gdk.CursorType.ARROW));
        
        // return to original view
        set_pixbuf(photo.get_pixbuf());
    }
    
    private void init_crop() {
        // using uncropped photo to work with
        Dimensions uncropped_dim = photo.get_uncropped_dimensions();

        Box crop;
        if (!photo.get_crop(out crop)) {
            int xofs = (int) (uncropped_dim.width * CROP_INIT_X_PCT);
            int yofs = (int) (uncropped_dim.height * CROP_INIT_Y_PCT);
            
            // initialize the actual crop in absolute coordinates, not relative
            // to the photo's position on the canvas
            crop = Box(xofs, yofs, uncropped_dim.width - xofs, uncropped_dim.height - yofs);
        }
        
        // scale the crop to the scaled photo's size ... the scaled crop is maintained in
        // coordinates not relative to photo's position on canvas
        scaled_crop = crop.get_scaled_proportional(uncropped_dim, 
            Dimensions.for_rectangle(get_scaled_position()));
    }

    private void rescale_crop(Dimensions old_pixbuf_dim, Dimensions new_pixbuf_dim) {
        assert(show_crop);
        
        Dimensions uncropped_dim = photo.get_uncropped_dimensions();
        
        // rescale to full crop
        Box crop = scaled_crop.get_scaled_proportional(old_pixbuf_dim, uncropped_dim);
        
        // rescale back to new size
        scaled_crop = crop.get_scaled_proportional(uncropped_dim, new_pixbuf_dim);
    }
    
    private void paint_pixbuf(Gdk.Pixbuf pb, Box source) {
        Gdk.Rectangle scaled_pos = get_scaled_position();
        
        get_drawable().draw_pixbuf(canvas_gc, pb,
            source.left, source.top,
            scaled_pos.x + source.left, scaled_pos.y + source.top,
            source.get_width(), source.get_height(),
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void draw_box(Gdk.GC gc, Box box) {
        Gdk.Rectangle rect = box.get_rectangle();
        rect.x += get_scaled_position().x;
        rect.y += get_scaled_position().y;
        
        // See note at gtk_drawable_draw_rectangle for info on off-by-one with unfilled rectangles
        get_drawable().draw_rectangle(gc, false, rect.x, rect.y, rect.width - 1, rect.height - 1);
    }
    
    private void draw_horizontal_line(Gdk.GC gc, int x, int y, int width) {
        x += get_scaled_position().x;
        y += get_scaled_position().y;
        
        Gdk.draw_line(get_drawable(), gc, x, y, x + width - 1, y);
    }
    
    private void draw_vertical_line(Gdk.GC gc, int x, int y, int height) {
        x += get_scaled_position().x;
        y += get_scaled_position().y;
        
        Gdk.draw_line(get_drawable(), gc, x, y, x, y + height - 1);
    }
    
    private void erase_horizontal_line(int x, int y, int width) {
        get_drawable().draw_pixbuf(canvas_gc, get_scaled_pixbuf(),
            x, y,
            get_scaled_position().x + x, get_scaled_position().y + y,
            width, 1,
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void erase_vertical_line(int x, int y, int height) {
        get_drawable().draw_pixbuf(canvas_gc, get_scaled_pixbuf(),
            x, y,
            get_scaled_position().x + x, get_scaled_position().y + y,
            1, height,
            Gdk.RgbDither.NORMAL, 0, 0);
    }
    
    private void erase_box(Box box) {
        erase_horizontal_line(box.left, box.top, box.get_width());
        erase_horizontal_line(box.left, box.bottom, box.get_width());
        
        erase_vertical_line(box.left, box.top, box.get_height());
        erase_vertical_line(box.right, box.top, box.get_height());
    }
    
    private void invalidate_area(Box area) {
        Gdk.Rectangle rect = area.get_rectangle();
        rect.x += get_scaled_position().x;
        rect.y += get_scaled_position().y;
        
        invalidate(rect);
    }
    
    private void paint_crop_tool(Box crop) {
        // paint rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            draw_horizontal_line(thin_white_gc, crop.left, crop.top + one_third_y, crop.get_width());
            draw_horizontal_line(thin_white_gc, crop.left, crop.top + (one_third_y * 2), crop.get_width());

            draw_vertical_line(thin_white_gc, crop.left + one_third_x, crop.top, crop.get_height());
            draw_vertical_line(thin_white_gc, crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }

        // outer rectangle ... outer line in black, inner in white, corners fully black
        draw_box(wide_black_gc, crop);
        draw_box(wide_white_gc, crop.get_reduced(1));
        draw_box(wide_white_gc, crop.get_reduced(2));
    }
    
    private void erase_crop_tool(Box crop) {
        // erase rule-of-thirds lines if user is manipulating the crop
        if (in_manipulation != BoxLocation.OUTSIDE) {
            int one_third_x = crop.get_width() / 3;
            int one_third_y = crop.get_height() / 3;
            
            erase_horizontal_line(crop.left, crop.top + one_third_y, crop.get_width());
            erase_horizontal_line(crop.left, crop.top + (one_third_y * 2), crop.get_width());
            
            erase_vertical_line(crop.left + one_third_x, crop.top, crop.get_height());
            erase_vertical_line(crop.left + (one_third_x * 2), crop.top, crop.get_height());
        }

        // erase border
        erase_box(crop);
        erase_box(crop.get_reduced(1));
        erase_box(crop.get_reduced(2));
    }
    
    private void invalidate_crop_tool(Box crop) {
        invalidate_area(crop);
    }
    
    private void crop_resized(Box new_crop) {
        if(scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        invalidate_crop_tool(scaled_crop);
        
        Box horizontal;
        bool horizontal_enlarged;
        Box vertical;
        bool vertical_enlarged;
        BoxComplements complements = scaled_crop.resized_complements(new_crop, out horizontal,
            out horizontal_enlarged, out vertical, out vertical_enlarged);
        
        // this should never happen ... this means that the operation wasn't a resize
        assert(complements != BoxComplements.NONE);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = horizontal_enlarged ? get_scaled_pixbuf() : color_shifted;
            paint_pixbuf(pb, horizontal);
            
            invalidate_area(horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            Gdk.Pixbuf pb = vertical_enlarged ? get_scaled_pixbuf() : color_shifted;
            paint_pixbuf(pb, vertical);
            
            invalidate_area(vertical);
        }
        
        paint_crop_tool(new_crop);
        invalidate_crop_tool(new_crop);
    }
    
    private void crop_moved(Box new_crop) {
        if (scaled_crop.equals(new_crop)) {
            // no change
            return;
        }
        
        // erase crop and rule-of-thirds lines
        erase_crop_tool(scaled_crop);
        invalidate_crop_tool(scaled_crop);
        
        Box scaled_horizontal;
        Box scaled_vertical;
        Box new_horizontal;
        Box new_vertical;
        BoxComplements complements = scaled_crop.shifted_complements(new_crop, out scaled_horizontal,
            out scaled_vertical, out new_horizontal, out new_vertical);
        
        if (complements == BoxComplements.HORIZONTAL || complements == BoxComplements.BOTH) {
            // paint in the horizontal complements appropriately
            paint_pixbuf(color_shifted, scaled_horizontal);
            paint_pixbuf(get_scaled_pixbuf(), new_horizontal);
            
            invalidate_area(scaled_horizontal);
            invalidate_area(new_horizontal);
        }
        
        if (complements == BoxComplements.VERTICAL || complements == BoxComplements.BOTH) {
            // paint in vertical complements appropriately
            paint_pixbuf(color_shifted, scaled_vertical);
            paint_pixbuf(get_scaled_pixbuf(), new_vertical);
            
            invalidate_area(scaled_vertical);
            invalidate_area(new_vertical);
        }
        
        if (complements == BoxComplements.NONE) {
            // this means the two boxes have no intersection, not that they're equal ... since
            // there's no intersection, fill in both new and old with apropriate pixbufs
            paint_pixbuf(color_shifted, scaled_crop);
            paint_pixbuf(get_scaled_pixbuf(), new_crop);
            
            invalidate_area(scaled_crop);
            invalidate_area(new_crop);
        }
        
        // paint crop in new location
        paint_crop_tool(new_crop);
        invalidate_crop_tool(new_crop);
    }
    
    private void draw_with_crop(Gdk.GC gc, Gdk.Drawable drawable) {
        assert(show_crop);
        
        Gdk.Rectangle scaled_pos = get_scaled_position();
        
        // painter's algorithm: from the bottom up, starting with the color shifted portion of the
        // photo outside the crop
        drawable.draw_pixbuf(gc, color_shifted, 
            0, 0, 
            scaled_pos.x, scaled_pos.y, 
            scaled_pos.width, scaled_pos.height,
            Gdk.RgbDither.NORMAL, 0, 0);
        
        // paint exposed (cropped) part of pixbuf minus crop border
        paint_pixbuf(get_scaled_pixbuf(), scaled_crop);

        // paint crop tool last
        paint_crop_tool(scaled_crop);
    }
    
    private void on_crop_apply() {
        // up-scale scaled crop to photo's dimensions
        Box crop = scaled_crop.get_scaled_proportional(Dimensions.for_rectangle(get_scaled_position()), 
            photo.get_uncropped_dimensions());

        deactivate_crop();

        // let the signal generate a repaint
        photo.set_crop(crop);
    }
    
    private void on_crop_cancel() {
        deactivate_crop();
    }
    
    private void on_photo_menu() {
        bool multiple = false;
        if (controller != null)
            multiple = controller.get_count() > 1;
        
        bool revert_possible = false;
        if (photo != null)
            revert_possible = photo.has_transformations();
            
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/PrevPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/NextPhoto", multiple);
        set_item_sensitive("/PhotoMenuBar/PhotoMenu/Revert", revert_possible);
    }
    
    private void on_next_photo() {
        deactivate_crop();
        
        this.thumbnail = (Thumbnail) controller.get_next_item(thumbnail);
        update_display();
    }
    
    private void on_previous_photo() {
        deactivate_crop();
        
        this.thumbnail = (Thumbnail) controller.get_previous_item(thumbnail);
        update_display();
    }
}

