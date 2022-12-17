module nagi.consile;

version (Posix) {
    version = ansi;
}

version (ansi) {

    /// Raw color and glyph codes
    enum Code : string {
        resetAll = "0",
        bold = "1",
        dim = "2",
        italic = "3",
        underline = "4",
        blinking = "5",
        inverse = "7",
        hidden = "8",
        strikethroguh = "9",
        resetBold = "22",
        resetDim = "22",
        resetItalic = "23",
        resetUnderline = "24",
        resetBlinking = "25",
        resetInverse = "27",
        resetHidden = "28",
        resetStrikethrough = "29",
        foregroundBlack = "30",
        foregroundRed = "31",
        foregroundGreen = "32",
        foregroundYellow = "33",
        foregroundBlue = "34",
        foregroundMagenta = "35",
        foregroundCyan = "36",
        foregroundWhite = "37",
        foreground = "38", // for 255 colors
        foregroundDefault = "39",
        backgroundBlack = "40",
        backgroundRed = "41",
        backgroundGreen = "42",
        backgroundYellow = "43",
        backgroundBlue = "44",
        backgroundMagenta = "45",
        backgroundCyan = "46",
        backgroundWhite = "47",
        background = "48", // for 255 colors
        backgroundDefault = "49",
    }

    /// Glyph operation
    enum Glyph {
        bold = build(Code.bold),
        dim = build(Code.dim),
        italic = build(Code.italic),
        underline = build(Code.underline),
        blinking = build(Code.blinking),
        inverse = build(Code.inverse),
        hidden = build(Code.hidden),
        strikethrough = build(Code.strikethroguh),
    }

    /// Reset glyph operation
    enum Reset {
        all = build(Code.resetAll),
        bold = build(Code.resetBold),
        dim = build(Code.resetDim),
        italic = build(Code.resetItalic),
        underline = build(Code.resetUnderline),
        blinking = build(Code.resetBlinking),
        inverse = build(Code.resetInverse),
        hidden = build(Code.resetHidden),
        strikethrough = build(Code.resetStrikethrough),
    }

    /// Foreground colors
    enum Foreground {
        black = build(Code.foregroundBlack),
        red = build(Code.foregroundRed),
        green = build(Code.foregroundGreen),
        yellow = build(Code.foregroundYellow),
        blue = build(Code.foregroundBlue),
        magenta = build(Code.foregroundMagenta),
        cyan = build(Code.foregroundCyan),
        white = build(Code.foregroundWhite),
        default_ = build(Code.foregroundDefault),
    }

    /// Background colors
    enum Background {
        black = build(Code.backgroundBlack),
        red = build(Code.backgroundRed),
        green = build(Code.backgroundGreen),
        yellow = build(Code.backgroundYellow),
        blue = build(Code.backgroundBlue),
        magenta = build(Code.backgroundMagenta),
        cyan = build(Code.backgroundCyan),
        white = build(Code.backgroundWhite),
        default_ = build(Code.backgroundDefault),
    }

    /**
     * Build an ESC code sequence with multiple color and glyph codes.
     * Params:
     *      code = A color/glyph code
     *      codes =  Extra codes (optional)
     * Returns: ESC code sequence
     */
    string build(Codes...)(Code code, Codes extraCodes) pure nothrow {
        static if (extraCodes.length == 0) {
            return "\033[" ~ code ~ "m";
        }
        else {
            string ret = "\033[" ~ code;
            foreach (c; extraCodes) {
                ret ~= ";" ~ c;
            }
            return ret ~ "m";
        }
    }
}

pure nothrow @safe {
    /// Reset all colors and text effects.
    string reset(string text) {
        return Reset.all ~ text;
    }
    /// Make bold.
    string bold(string text) {
        return Glyph.bold ~ text ~ Reset.bold;
    }
    /// Make dim.
    string dim(string text) {
        return Glyph.dim ~ text ~ Reset.dim;
    }
    /// Make italic.
    string italic(string text) {
        return Glyph.italic ~ text ~ Reset.italic;
    }
    /// Make underline.
    string underline(string text) {
        return Glyph.underline ~ text ~ Reset.underline;
    }
    /// Make blinking.
    string blinking(string text) {
        return Glyph.blinking ~ text ~ Reset.blinking;
    }
    /// Make inverse.
    string inverse(string text) {
        return Glyph.inverse ~ text ~ Reset.inverse;
    }
    /// Make hidden.
    string hidden(string text) {
        return Glyph.hidden ~ text ~ Reset.hidden;
    }
    /// Make strikethrough.
    string strikethrough(string text) {
        return Glyph.strikethrough ~ text ~ Reset.strikethrough;
    }
    /// Make foreground black.
    string black(string text) {
        return Foreground.black ~ text ~ Foreground.default_;
    }
    /// Make foreground red.
    string red(string text) {
        return Foreground.red ~ text ~ Foreground.default_;
    }
    /// Make foreground green.
    string green(string text) {
        return Foreground.green ~ text ~ Foreground.default_;
    }
    /// Make foreground yellow.
    string yellow(string text) {
        return Foreground.yellow ~ text ~ Foreground.default_;
    }
    /// Make foreground blue.
    string blue(string text) {
        return Foreground.blue ~ text ~ Foreground.default_;
    }
    /// Make foreground magenta.
    string magenta(string text) {
        return Foreground.magenta ~ text ~ Foreground.default_;
    }
    /// Make foreground cyan.
    string cyan(string text) {
        return Foreground.cyan ~ text ~ Foreground.default_;
    }
    /// Make foreground white.
    string white(string text) {
        return Foreground.white ~ text ~ Foreground.default_;
    }
    /// Make foreground default (reset foreground color).
    string default_(string text) {
        return Foreground.default_ ~ text;
    }
    /// Make background black.
    string bblack(string text) {
        return Background.black ~ text ~ Background.default_;
    }
    /// Make background red.
    string bred(string text) {
        return Background.red ~ text ~ Background.default_;
    }
    /// Make background green.
    string bgreen(string text) {
        return Background.green ~ text ~ Background.default_;
    }
    /// Make background yellow.
    string byellow(string text) {
        return Background.yellow ~ text ~ Background.default_;
    }
    /// Make background blue.
    string bblue(string text) {
        return Background.blue ~ text ~ Background.default_;
    }
    /// Make background magenta.
    string bmagenta(string text) {
        return Background.magenta ~ text ~ Background.default_;
    }
    /// Make background cyan.
    string bcyan(string text) {
        return Background.cyan ~ text ~ Background.default_;
    }
    /// Make background white.
    string bwhite(string text) {
        return Background.white ~ text ~ Background.default_;
    }
    /// Make background default (reset background color).
    string bdefault_(string text) {
        return Background.default_ ~ text;
    }
    /**
     * Make foreground ID of 256 colors.
     * See_Also:
     *      https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
     */
    string foreground256(string text, ubyte id) {
        import std.conv : to;

        return build(Code.foreground, "5", id.to!string) ~ text ~ Foreground.default_;
    }
    /**
     * Make background ID of 256 colors.
     * See_Also:
     *      https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
     */
    string background256(string text, ubyte id) {
        import std.conv : to;

        return build(Code.background, "5", id.to!string) ~ text ~ Background.default_;
    }

}

@("Display all colorizing functions")
debug (Example) unittest {
    import std.stdio : write;

    static foreach (i, color; [
            "reset", "bold", "dim", "italic", "underline", "blinking", "inverse",
            "strikethrough",
        ]) {
        mixin(`write("` ~ color ~ `".` ~ color ~ `, " ");`);
    }
    write("\n");
    static foreach (i, color; [
            "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
            "default_",
        ]) {
        mixin(`write("` ~ color ~ `".` ~ color ~ `, " ");`);
    }
    write("\n");
    static foreach (i, color; [
            "bblack", "bred", "bgreen", "byellow", "bblue", "bmagenta", "bcyan",
            "bwhite", "bdefault_",
        ]) {
        mixin(`write("` ~ color ~ `".` ~ color ~ `, " ");`);
    }
    write("\n");
}

@("Display combination")
debug (Example) unittest {
    import std.stdio : writeln;

    string italic = "italic".italic;
    string bold = ("bold " ~ italic ~ " bold").bold;
    string red = ("red " ~ bold ~ " red").red;
    string bgreen = ("bgreen " ~ red ~ " bgreen").bgreen;

    writeln(bgreen);
}

@("Build your own code combination")
debug (Example) unittest {
    import std.stdio : writeln;

    with (Code) {
        auto code = build(bold, strikethroguh, foregroundRed, backgroundCyan);
        assert(code == "\033[1;9;31;46m");
        writeln(code, "build your own combination", reset(""));
    }
}

@("Display 256 colors")
debug (Example) unittest {
    import std.stdio : write;
    import std.conv : to;

    foreach (ubyte i; 0 .. 256) {
        write(foreground256(i.to!string, i), " ");
        if (i % 20 == 19) {
            write("\n");
        }
    }
    write(reset("\n"));
    foreach (ubyte i; 0 .. 256) {
        write(background256(i.to!string, i), " ");
        if (i % 20 == 19) {
            write("\n");
        }
    }
    write(reset("\n"));
}
