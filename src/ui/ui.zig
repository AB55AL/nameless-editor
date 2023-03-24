const std = @import("std");
const print = std.debug.print;
const math = std.math;
const unicode = std.unicode;

const gui = @import("gui");
const input_layer = @import("input_layer");

const core = @import("core");
const utils = core.utils;

const Options = gui.Options;
const Rect = gui.Rect;
const RectScale = gui.RectScale;
const WidgetData = gui.WidgetData;
const InstallOptions = gui.InstallOptions;
const Event = gui.Event;
const EventIterator = gui.EventIterator;
const Size = gui.Size;
const Point = gui.Point;
const Animation = gui.Animation;

const BufferIterator = core.Buffer.BufferIterator;
const LineIterator = core.Buffer.LineIterator;

pub fn bufferWidget(src: std.builtin.SourceLocation, id_extra: usize, buffer_window_node: *core.BufferWindowNode, focus: bool, opts: Options) !void {
    var bw = BufferWidget.init(src, id_extra, buffer_window_node, opts);
    defer bw.deinit();
    try bw.install(.{});

    var buffer_window = buffer_window_node.data;
    var buffer = buffer_window.buffer;
    const relative_index = buffer_window.relativeBufferIndexFromAbsolute(buffer_window.buffer.cursor_index);
    var iter = LineIterator.init(buffer, buffer_window.first_visiable_row, buffer.lineCount());
    while (iter.next()) |slice| {
        if (try bw.addText(slice, relative_index, opts)) break;
    }

    try bw.renderCursor(.{ .color_border = toColor(0x0000AA, 100) });

    if (focus) gui.focusWidget(bw.wd.id, null);
}

pub const BufferWidget = struct {
    pub const defaults: Options = .{
        .margin = Rect.all(0),
        .corner_radius = Rect.all(0),
        .border = Rect.all(1),
        .padding = Rect.all(4),
        .background = true,
        // .color_style = .content,
    };

    wd: WidgetData = undefined,
    insert_pt: Point = Point{},
    cursor_rect: Rect = Rect{},
    corners: [4]?Rect = [_]?Rect{null} ** 4,
    buffer_window: *core.BufferWindowNode,
    /// This is used in locateCursor to keep track of how many strings have
    /// been looked at from one call to the next
    accumulated_string_len: u64 = 0,

    pub fn init(src: std.builtin.SourceLocation, id_extra: usize, buffer_window: *core.BufferWindowNode, opts: Options) BufferWidget {
        const options = defaults.override(opts);
        var bw = BufferWidget{ .wd = WidgetData.init(src, id_extra, options), .buffer_window = buffer_window };
        return bw;
    }

    pub fn install(buffer_widget: *BufferWidget, opts: InstallOptions) !void {
        try buffer_widget.wd.borderAndBackground();

        if (opts.process_events) {
            var iter = EventIterator.init(buffer_widget.data().id, buffer_widget.data().borderRectScale().r);
            while (iter.next()) |e| {
                buffer_widget.processEvent(&iter, e);
            }
        }

        if (gui.focusedWidgetId() == buffer_widget.wd.id)
            try buffer_widget.wd.focusBorder();
    }

    pub fn deinit(buffer_widget: *BufferWidget) void {
        buffer_widget.wd.minSizeSetAndCue();
        buffer_widget.wd.minSizeReportToParent();
    }

    // pub fn widget(buffer_widget: *buffer_widget) Widget {
    //     return Widget.init(buffer_widget, data, rectFor, screenRectScale, minSizeForChild, processEvent, bubbleEvent);
    // }

    pub fn data(buffer_widget: *BufferWidget) *WidgetData {
        return &buffer_widget.wd;
    }

    pub fn screenRectScale(buffer_widget: *BufferWidget, rect: Rect) RectScale {
        const rs = buffer_widget.wd.contentRectScale();
        return RectScale{ .r = rect.scale(rs.s).offset(rs.r), .s = rs.s };
    }

    pub fn processEvent(buffer_widget: *BufferWidget, iter: *EventIterator, e: *Event) void {
        var bw = buffer_widget.buffer_window;
        switch (e.evt) {
            .key => |ke| {
                e.handled = true;
                if (ke.kind == .text) {
                    input_layer.characterInput(ke.kind.text);
                }

                const key_union = guiKeyToEditor(switch (ke.kind) {
                    .text => return,
                    inline else => |key| key,
                });

                const key = core.input.Key{
                    .key = key_union,
                    .mod = guiModToEditorMod(ke.mod),
                };
                input_layer.keyInput(key);
            },

            .mouse => |me| {
                switch (me.kind) {
                    .focus => {
                        e.handled = true;
                        gui.focusWidget(buffer_widget.wd.id, iter);
                        core.setFocusedWindow(bw);
                    },
                    .wheel_y => |y| {
                        if (y >= 0)
                            bw.data.scrollUp(1)
                        else
                            bw.data.scrollDown(1);
                    },
                    else => {},
                }
            },

            else => {},
        }

        if (gui.bubbleable(e)) {
            buffer_widget.bubbleEvent(e);
        }
    }

    pub fn bubbleEvent(buffer_widget: *BufferWidget, e: *Event) void {
        buffer_widget.wd.parent.bubbleEvent(e);
    }

    pub fn renderCursor(self: *BufferWidget, const_options: Options) !void {
        const options = self.wd.options.override(const_options);
        const rs = self.screenRectScale(self.cursor_rect);
        self.cursor_rect = rs.r;

        try gui.pathAddRect(self.cursor_rect, .{});
        try gui.pathFillConvex(options.color(.border));
    }

    // TODO: Wrapping
    pub fn locateCursor(self: *BufferWidget, text: []const u8, size: Size, cursor_index: u64, opts: Options) !void {
        if (self.accumulated_string_len > cursor_index) return;
        const options = self.wd.options.override(opts);
        const rect = self.wd.contentRect();

        const end = text.len;

        const lineskip = try options.fontGet().lineSkip();
        const new_line = text[end - 1] == '\n';
        const relative_index = math.min(cursor_index - self.accumulated_string_len, end - 1);

        if (utils.inRange(cursor_index, self.accumulated_string_len, self.accumulated_string_len + end - 1)) {
            // Found the slice containing the cursor

            const txt = text[0..end];
            const cp_slice = blk: {
                const cp_len = unicode.utf8ByteSequenceLength(txt[relative_index]) catch unreachable;
                break :blk txt[relative_index .. relative_index + cp_len];
            };

            const cp_is_newline = cp_slice.len == 1 and cp_slice[0] == '\n';
            const cp_size = if (cp_is_newline)
                try options.fontGet().textSize("@") // use the size of @ for the newline char
            else
                try options.fontGet().textSize(cp_slice);

            const cursor_offset = try options.fontGet().textSize(txt[0..relative_index]);

            self.cursor_rect.w = cp_size.w;
            self.cursor_rect.h = cp_size.h;
            self.cursor_rect.x += cursor_offset.w;
        } else if (!new_line) {
            self.cursor_rect.x += size.w;
        } else if (new_line) {
            self.cursor_rect.y += lineskip;
            self.cursor_rect.x = 0;
        }

        self.accumulated_string_len += end;

        // don't render the cursor outside the containing rect
        if (self.cursor_rect.y >= rect.h) self.cursor_rect = Rect{ .w = 0, .h = 0 };
    }

    pub fn addText(self: *BufferWidget, text: []const u8, cursor_index: ?u64, const_options: Options) !bool {
        var done = false;
        const options = self.wd.options.override(const_options);
        const msize = try options.fontGet().textSize("m");
        const lineskip = try options.fontGet().lineSkip();
        var txt = text;

        const rect = self.wd.contentRect();
        var container_width = rect.w;
        if (self.screenRectScale(rect).r.empty()) {
            // if we are not being shown at all, probably this is the first
            // frame for us and we should calculate our min height assuming we
            // get at least our min width

            // do this dance so we aren't repeating the contentRect
            // calculations here
            const given_width = self.wd.rect.w;
            self.wd.rect.w = math.max(given_width, self.wd.min_size.w);
            container_width = self.wd.contentRect().w;
            self.wd.rect.w = given_width;
        }

        while (txt.len > 0) {
            var linestart: f32 = 0;
            var linewidth = container_width;
            var width = linewidth - self.insert_pt.x;
            for (self.corners) |corner| {
                if (corner) |cor| {
                    if (math.max(cor.y, self.insert_pt.y) < math.min(cor.y + cor.h, self.insert_pt.y + lineskip)) {
                        linewidth -= cor.w;
                        if (linestart == cor.x) {
                            linestart = (cor.x + cor.w);
                        }

                        if (self.insert_pt.x <= (cor.x + cor.w)) {
                            width -= cor.w;
                            if (self.insert_pt.x >= cor.x) {
                                self.insert_pt.x = (cor.x + cor.w);
                            }
                        }
                    }
                }
            }

            var end: usize = undefined;

            // get slice of text that fits within width or ends with newline
            // - always get at least 1 code_point so we make progress

            var s = try options.fontGet().textSizeEx(txt, width, &end);

            const newline = (txt[end - 1] == '\n');

            //std.debug.print("{d} 1 txt to {d} \"{s}\"\n", .{ container_width, end, txt[0..end] });

            // if we are boxed in too much by corner widgets drop to next line
            if (s.w > width and linewidth < container_width) {
                self.insert_pt.y += lineskip;
                self.insert_pt.x = 0;
                continue;
            }

            // try to break on space if:
            // - slice ended due to width (not newline)
            // - linewidth is long enough (otherwise too narrow to break on space)
            if (end < txt.len and !newline and linewidth > (10 * msize.w)) {
                const space: []const u8 = &[_]u8{' '};
                // now we are under the length limit but might be in the middle of a word
                // look one char further because we might be right at the end of a word
                const spaceIdx = std.mem.lastIndexOfLinear(u8, txt[0 .. end + 1], space);
                if (spaceIdx) |si| {
                    end = si + 1;
                    s = try options.fontGet().textSize(txt[0..end]);
                } else if (self.insert_pt.x > linestart) {
                    // can't fit breaking on space, but we aren't starting at the left edge
                    // so drop to next line
                    self.insert_pt.y += lineskip;
                    self.insert_pt.x = 0;
                    continue;
                }
            }

            // We want to render text, but no sense in doing it if we are off the end
            if (self.insert_pt.y < rect.h) {
                const rs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = width, .h = math.max(0, rect.h - self.insert_pt.y) });
                //std.debug.print("renderText: {} {s}\n", .{ rs.r, txt[0..end] });

                if (newline) {
                    try gui.renderText(options.fontGet(), txt[0 .. end - 1], rs, options.color(.text));
                } else {
                    try gui.renderText(options.fontGet(), txt[0..end], rs, options.color(.text));
                }
            }

            // even if we don't actually render, need to update insert_pt and minSize
            // like we did because our parent might size based on that (might be in a
            // scroll area)
            self.insert_pt.x += s.w;
            const size = Size{ .w = 0, .h = self.insert_pt.y + s.h };
            self.wd.min_size.h = math.max(self.wd.min_size.h, self.wd.padSize(size).h);

            if (cursor_index) |ci| try self.locateCursor(txt[0..end], s, ci, options);
            txt = txt[end..];

            // move insert_pt to next line if we have more text
            if (txt.len > 0 or newline) {
                self.insert_pt.y += lineskip;
                self.insert_pt.x = 0;
            }
            if (self.insert_pt.y >= rect.h) {
                done = true;
                break;
            } // This will speed up rendering but prevent scrolling from working.
        }

        return done;
    }
};

pub fn guiKeyToEditor(key: gui.Key) core.input.KeyUnion {
    return switch (key) {
        .a => .{ .code_point = 'a' },
        .b => .{ .code_point = 'b' },
        .c => .{ .code_point = 'c' },
        .d => .{ .code_point = 'd' },
        .e => .{ .code_point = 'e' },
        .f => .{ .code_point = 'f' },
        .g => .{ .code_point = 'g' },
        .h => .{ .code_point = 'h' },
        .i => .{ .code_point = 'i' },
        .j => .{ .code_point = 'j' },
        .k => .{ .code_point = 'k' },
        .l => .{ .code_point = 'l' },
        .m => .{ .code_point = 'm' },
        .n => .{ .code_point = 'n' },
        .o => .{ .code_point = 'o' },
        .p => .{ .code_point = 'p' },
        .q => .{ .code_point = 'q' },
        .r => .{ .code_point = 'r' },
        .s => .{ .code_point = 's' },
        .t => .{ .code_point = 't' },
        .u => .{ .code_point = 'u' },
        .v => .{ .code_point = 'v' },
        .w => .{ .code_point = 'w' },
        .x => .{ .code_point = 'x' },
        .y => .{ .code_point = 'y' },
        .z => .{ .code_point = 'z' },

        .zero => .{ .code_point = '0' },
        .one => .{ .code_point = '1' },
        .two => .{ .code_point = '2' },
        .three => .{ .code_point = '3' },
        .four => .{ .code_point = '4' },
        .five => .{ .code_point = '5' },
        .six => .{ .code_point = '6' },
        .seven => .{ .code_point = '7' },
        .eight => .{ .code_point = '8' },
        .nine => .{ .code_point = '9' },

        .kp_divide => .{ .code_point = '/' },
        .kp_multiply => .{ .code_point = '*' },
        .kp_subtract, .minus => .{ .code_point = '-' },
        .kp_add => .{ .code_point = '+' },
        .kp_0 => .{ .code_point = '0' },
        .kp_1 => .{ .code_point = '1' },
        .kp_2 => .{ .code_point = '2' },
        .kp_3 => .{ .code_point = '3' },
        .kp_4 => .{ .code_point = '4' },
        .kp_5 => .{ .code_point = '5' },
        .kp_6 => .{ .code_point = '6' },
        .kp_7 => .{ .code_point = '7' },
        .kp_8 => .{ .code_point = '8' },
        .kp_9 => .{ .code_point = '9' },
        .equal, .kp_equal => .{ .code_point = '=' },
        .left_bracket => .{ .code_point = '[' },
        .right_bracket => .{ .code_point = ']' },
        .backslash => .{ .code_point = '\\' },
        .semicolon => .{ .code_point = ';' },
        .comma => .{ .code_point = ',' },
        .period => .{ .code_point = '.' },
        .slash => .{ .code_point = '/' },
        .grave => .{ .code_point = '`' },

        .f1 => .{ .function_key = .f1 },
        .f2 => .{ .function_key = .f2 },
        .f3 => .{ .function_key = .f3 },
        .f4 => .{ .function_key = .f4 },
        .f5 => .{ .function_key = .f5 },
        .f6 => .{ .function_key = .f6 },
        .f7 => .{ .function_key = .f7 },
        .f8 => .{ .function_key = .f8 },
        .f9 => .{ .function_key = .f9 },
        .f10 => .{ .function_key = .f10 },
        .f11 => .{ .function_key = .f11 },
        .f12 => .{ .function_key = .f12 },
        .f13 => .{ .function_key = .f13 },
        .f14 => .{ .function_key = .f14 },
        .f15 => .{ .function_key = .f15 },
        .f16 => .{ .function_key = .f16 },
        .f17 => .{ .function_key = .f17 },
        .f18 => .{ .function_key = .f18 },
        .f19 => .{ .function_key = .f19 },
        .f20 => .{ .function_key = .f20 },
        .f21 => .{ .function_key = .f21 },
        .f22 => .{ .function_key = .f22 },
        .f23 => .{ .function_key = .f23 },
        .f24 => .{ .function_key = .f24 },

        .enter, .kp_enter => .{ .function_key = .enter },

        .escape => .{ .function_key = .escape },
        .tab => .{ .function_key = .tab },
        .num_lock => .{ .function_key = .num_lock },
        .caps_lock => .{ .function_key = .caps_lock },
        .print => .{ .function_key = .print_screen },
        .scroll_lock => .{ .function_key = .scroll_lock },
        .pause => .{ .function_key = .pause },
        .delete => .{ .function_key = .delete },
        .home => .{ .function_key = .home },
        .end => .{ .function_key = .end },
        .page_up => .{ .function_key = .page_up },
        .page_down => .{ .function_key = .page_down },
        .insert => .{ .function_key = .insert },
        .left => .{ .function_key = .left },
        .right => .{ .function_key = .right },
        .up => .{ .function_key = .up },
        .down => .{ .function_key = .down },
        .backspace => .{ .function_key = .backspace },
        .space => .{ .function_key = .space },

        // .kp_decimal=>, // ?? idk what this is
        // .apostrophe=>.{.code_point = '-'}, ?? idk what this is

        // .left_shift=>.{.function_key = .enter},
        // .right_shift=>.{.function_key = .enter},
        // .left_control=>.{.function_key = .enter},
        // .right_control=>.{.function_key = .enter},
        // .left_alt=>.{.function_key = .enter},
        // .right_alt=>.{.function_key = .enter},
        // .left_super=>.{.function_key = .enter},
        // .right_super=>.{.function_key = .enter},
        // .menu=>.{.function_key = .enter},
        // .f25 => .{ .function_key = .f25 },
        else => .{ .function_key = .unknown },
    };
}

pub fn guiModToEditorMod(mod: gui.Mod) core.input.Modifiers {
    var mod_int: u3 = 0;
    if (hasShift(mod)) mod_int |= @enumToInt(core.input.Modifiers.shift);
    if (hasControl(mod)) mod_int |= @enumToInt(core.input.Modifiers.control);
    if (hasAlt(mod)) mod_int |= @enumToInt(core.input.Modifiers.alt);

    return @intToEnum(core.input.Modifiers, mod_int);
}

fn hasShift(mod: gui.Mod) bool {
    const mod_int = @enumToInt(mod);
    const lshift = @enumToInt(gui.Mod.lshift);
    const rshift = @enumToInt(gui.Mod.rshift);
    return mod_int & lshift == lshift or mod_int & rshift == rshift;
}

fn hasControl(mod: gui.Mod) bool {
    const mod_int = @enumToInt(mod);
    const lctrl = @enumToInt(gui.Mod.lctrl);
    const rctrl = @enumToInt(gui.Mod.rctrl);
    return mod_int & lctrl == lctrl or mod_int & rctrl == rctrl;
}

fn hasAlt(mod: gui.Mod) bool {
    const mod_int = @enumToInt(mod);
    const lalt = @enumToInt(gui.Mod.lalt);
    const ralt = @enumToInt(gui.Mod.ralt);
    return mod_int & lalt == lalt or mod_int & ralt == ralt;
}

pub fn toColor(color: u24, alpha: u8) gui.Color {
    const r = @intCast(u8, (color >> 16) & 0xFF);
    const g = @intCast(u8, (color >> 8) & 0xFF);
    const b = @intCast(u8, color & 0xFF);
    return .{
        .r = r,
        .g = g,
        .b = b,
        .a = alpha,
    };
}
