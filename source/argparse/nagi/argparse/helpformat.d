module nagi.argparse.helpformat;

import std.typecons;
import std.conv : text;
import std.sumtype;
import std.format;
import std.range;
import std.string;

import nagi.argparse.types;
import nagi.argparse.parser;
import nagi.argparse.help_format;

/** 
 * Interafce for help message typography.
 */
interface HelpTypographyInterface {
    /** 
     * Generate a help message string which is composed by the arguments.
     * Params:
     *   commandName = The name of the command.
     *   description = The description of the command.
     *   subCommands = The list of the sub commands. If the positionals exist, this should be empty.
     *   positionals = The list of the positional arguments. If the subCommands exist, this should be empty.
     *   optionals = The list of the optional arguments.
     *   helpOptional = The option to show the help message.
     *   footer = The footer of the help message.
     * Returns: A string to show the help message.
     */
    string print(
        const string commandName, const string description, const ArgumentParser[] subCommands,
        const ArgPositional[] positionals, const ArgOptional[] optionals, const ArgOptional helpOptional, string footer,
    )
    in (subCommands.length == 0 || positionals.length == 0);
}

class HelpTypography : HelpTypographyInterface {
    this(int sampleBoxWidth = 18, int descriptionBoxWidth = 60, int gapWidth = 2) {
        this.sampleBoxWidth_ = sampleBoxWidth;
        this.descriptionBoxWidth_ = descriptionBoxWidth;
        this.gapWidth_ = gapWidth;
    }

    override string print(const string commandName, const string description, const ArgumentParser[] subCommands,
    const ArgPositional[] positionals, const ArgOptional[] optionals, const ArgOptional helpOptional, string footer,
    )
    in (subCommands.length == 0 || positionals.length == 0) {
        import std.array : appender;
        import std.algorithm;

        auto buffer = appender!string;

        // Usage line
        buffer ~= text("usage: ", commandName);
        if (!isEmpty(helpOptional)) {
            assert(helpOptional.optShort || helpOptional.optLong);
            const helpFlag = helpOptional.optShort ? helpOptional.optShort : helpOptional.optLong;
            buffer ~= text(" [", helpFlag, "]");
        }
        if (optionals) {
            buffer ~= " [OPTION]";
        }
        if (subCommands) {
            buffer ~= format(" {%-(%s,%)} ...", subCommands.map!(a => a.id_));
        }
        if (positionals) {
            buffer ~= format(" %-(%s %)", positionals.map!(a => a.id));
        }

        buffer ~= makeHelpSection(subCommands, "Sub commands");
        buffer ~= makeHelpSection(positionals.filter!(item => item.isRequired)
                .array(), "Required positional arguments");
        buffer ~= makeHelpSection(positionals.filter!(item => !item.isRequired)
                .array(), "Non-required positional arguments");
        buffer ~= makeHelpSection(optionals.filter!(item => item.isRequired)
                .array(), "Required optional arguments");
        buffer ~= makeHelpSection(optionals.filter!(item => !item.isRequired)
                .array(), "Non-required optional arguments");

        return buffer[];
    }

private:
    int sampleBoxWidth_;
    int descriptionBoxWidth_;
    int gapWidth_;

    string makeHelpSection(T)(T[] items, string title) const {
        import std.array : appender;
        import std.algorithm;

        if (items) {
            auto buffer = appender!string;
            buffer ~= text("\n", title, "\n", replicate("=", title.length), "\n");
            each!((item) { buffer ~= makeHelpItem(item); })(items);
            return buffer[];
        }
        else {
            return "";
        }
    }

    string makeHelpItem(T)(in T item) const {
        const name = sampleText(item);
        const description = descriptionText(item);
        const indent = replicate(" ", gapWidth_ + sampleBoxWidth_);
        const first = leftJustify(text("  ", name), sampleBoxWidth_);
        // Add 2 for wrap function. Without it, wrap function wraps text even if the word width equals to width.
        if (first.length <= sampleBoxWidth_) {
            return wrap(description, sampleBoxWidth_ + gapWidth_ + descriptionBoxWidth_ + 2,
                first ~ replicate(" ", gapWidth_), indent);
        }
        else {
            return text(first, "\n",
                wrap(description, sampleBoxWidth_ + gapWidth_ + descriptionBoxWidth_ + 2, indent, indent));
        }
    }

    static string sampleText(in ArgPositional item) {
        return item.id;
    }

    static string sampleText(in ArgOptional item) {
        const opt = () {
            if (item.optShort && item.optLong) {
                return text(item.optShort, " ", item.optLong);
            }
            else if (item.optShort && !item.optLong) {
                return item.optShort;
            }
            else if (!item.optShort && item.optLong) {
                return text("   ", item.optLong);
            }
            else {
                assert(false);
            }
        }();

        return item.nArgs.match!(
            (NArgsOption n) {
            with (NArgsOption) final switch (n) {
            case one:
                return text(opt, " ", item.id);
            case zeroOrOne:
                return text(opt, " ", item.id, "?");
            case moreThanEqualZero:
                return text(opt, " ", item.id, "...");
            case moreThanEqualOne:
                return text(opt, " ", item.id, "...");
            }
        },
            (uint n) {
            if (n == 0) {
                return opt;
            }
            else {
                return format(text(opt, " %-(", item.id, "%d %)"), iota(n));
            }
        }
        );
    }

    static string sampleText(in ArgumentParser item) {
        return item.id_;
    }

    static string descriptionText(in ArgPositional item) {
        return item.helpText;
    }

    static string descriptionText(in ArgOptional item) {
        return item.helpText;
    }

    static string descriptionText(in ArgumentParser item) {
        return item.shortDescription_;
    }
}

unittest {
    import std.stdio;

    HelpTypographyInterface h = new HelpTypography();
    writeln(h.print("cmd", "help",
            [], [ArgPositional("pos1")], [ArgOptional("opt1")], ArgOptional("help", "Display this message.", "-h"), ""));
}

/** 
 * Interface of the builder for composing help message.
 *
 * `HelpBuilderInterface` define the components of help message. Implementation
 * should have the following contents and need to compose as string.
 * * Command name
 * * COmmand description
 * * Sub commands
 * * Required positional arguments
 * * Non-required positional arguments
 * * Required optional arguments
 * * Non-requird optional arguments
 * * Footer
 *
 * By implementing user-defined HelpBuilder, the appearance of the help message can be modified.
 */
interface HelpBuilderInterface {
    alias This = typeof(this);

    /// Add a description. Descriptions can be appended by calling this multiple times.
    /** 
     * Add a description.
     * 
     * Descriptions can be appended by calling this multiple times.
     * Params:
     *   description = The description.
     * Returns: This object.
     */
    This addDescription(string description);
    /** 
     * Add a sub command.
     * Params:
     *   name = The display name of the sub command. 
     *   description = The description of the sub command.
     * Returns: This object.
     */
    This addSubCommand(string name, string description);
    /** 
     * Add a positional argument.
     * Params:
     *   name = The display name of the argument.
     *   description = The description of the argument.
     *   defaultValue = The default value of the argument. `null` for no default.
     *   isRequired = The argument is required or not.
     * Returns: This object.
     */
    This addPositional(string name, string description, string defaultValue, bool isRequired);
    /// Add an optinal  arugment.
    /** 
     * Add an optional argument.
     * Params:
     *   name = The display name of the argument.
     *   optShort = The short option of the argument. `null` for unset.
     *   optLong = The long option of the argument. `null` for unset.
     *   description = The description of the argument.
     *   defaultValue = The default value of the argument. `null` for no default.
     *   isRequired = The argument is required or not.
     * Returns: This object.
     */
    This addOptional(string name, string optShort, string optLong,
        string description, string defaultValue, bool isRequired, NArgs nArgs);
    /// Add an optional argument for help option.
    /** 
     * Set an optional argument for help option.
     *
     * Help option should be considered separated from the other optionals,
     * because a tool user want to know which option shows the help message and
     * then *exit* immediately.
     * Params:
     *   optShort = The short option of the help option. `null` for unset.
     *   optLong = The long option of the help option. `null` for unset.
     *   description = The description of the help option.
     * Returns: This object.
     */
    This setHelpOptional(string optShort, string optLong, string description);
    /** 
     * Set a footer.
     * Params:
     *   footer = The footer message.
     * Returns: This object.
     */
    This setFooter(string footer);
    /** 
     * Compose the contents and return it as a string.
     * Params:
     *   commandName = The command name to be used.
     * Returns: Help message composed.
     */
    string build(string commandName) const;
}

/** 
 * Default HelpBuilder implementation.
 * 
 * This builder has the following three sections.
 * * Usage section
 * * Description section
 * * Arguments section
 * For the arguments section, there are five sub sections that shows sub
 * commands, required/non-required positional arguments and
 * required/non-required optional arguments. Each item in every sub section has
 * `sample` and 
 */
class HelpBuilder : HelpBuilderInterface {
    this(int sampleBoxWidth = 18, int descriptionBoxWidth = 60, int gapWidth = 2) {
        this.sampleBoxWidth_ = sampleBoxWidth;
        this.descriptionBoxWidth_ = descriptionBoxWidth;
        this.gapWidth_ = gapWidth;
    }

    override This addDescription(string description) {
        this.descrptions_ ~= description;
        return this;
    }

    override This addSubCommand(string name, string description) {
        this.subCommands_ ~= SubCommand(name, description);
        return this;
    }

    override This addPositional(string name, string description, string defaultValue, bool isRequired) {
        this.positionals_ ~= Positional(name, description, defaultValue, isRequired);
        return this;
    }

    override This addOptional(string name, string optShort, string optLong,
        string description, string defaultValue, bool isRequired, NArgs nArgs) {
        this.optionals_ ~= Optional(name, optShort, optLong, description, defaultValue, isRequired, nArgs);
        return this;
    }

    override This setHelpOptional(string optShort, string optLong, string description) {
        this.helpOptional_ = Optional("help", optShort, optLong, description, null, false);
        return this;
    }

    override This setFooter(string footer) {
        this.footer_ = footer;
        return this;
    }

    override string build(string commandName) const
    in (subCommands_.length == 0 || positionals_.length == 0) {
        import std.array : appender;
        import std.algorithm;

        auto buffer = appender!string;

        // Usage line
        buffer ~= text("usage: ", commandName, " ");
        if (!helpOptional_.isNull()) {
            auto helpOpt = helpOptional_.get();
            const helpFlag = helpOpt.optShort ? helpOpt.optShort : helpOpt.optLong;
            buffer ~= text("[", helpFlag, "] ");
        }
        if (optionals_) {
            buffer ~= "[OPTION] ";
        }
        if (subCommands_) {
            buffer ~= format("{%-(%s,%)} ...", subCommands_.map!(c => c.name));
        }
        if (positionals_) {
            buffer ~= format("%-(%s %)", positionals_.map!(c => c.name));
        }

        return buffer[];
    }

private:

    struct SubCommand {
        string name;
        string description;
    }

    struct Positional {
        string name;
        string description;
        string defaultvalue;
        bool isRequired;
    }

    struct Optional {
        string name;
        string optShort;
        string optLong;
        string description;
        string defaultValue;
        bool isRequired;
        NArgs nArgs;
    }

    // Configuration
    int sampleBoxWidth_;
    int descriptionBoxWidth_;
    int gapWidth_;

    // Internal data
    string[] descrptions_;
    SubCommand[] subCommands_;
    Positional[] positionals_;
    Optional[] optionals_;
    Nullable!Optional helpOptional_;
    string footer_;

    static string sampleText(in Positional item) {
        return item.name;
    }

    static string sampleText(in Optional item) {
        const opt = () {
            if (item.optShort && item.optLong) {
                return text(item.optShort, " ", item.optLong);
            }
            else if (item.optShort && !item.optLong) {
                return item.optShort;
            }
            else if (!item.optShort && item.optLong) {
                return text("   ", item.optLong);
            }
            else {
                assert(false);
            }
        }();

        return item.nArgs.match!(
            (NArgsOption n) {
            with (NArgsOption) final switch (n) {
            case one:
                return text(opt, " ", item.name);
            case zeroOrOne:
                return text(opt, " ", item.name, "?");
            case moreThanEqualZero:
                return text(opt, " ", item.name, "...");
            case moreThanEqualOne:
                return text(opt, " ", item.name, "...");
            }
        },
            (uint n) {
            if (n == 0) {
                return opt;
            }
            else {
                return format(text(opt, " %-(", item.name, "%d %)"), iota(n));
            }
        }
        );
    }
}

@("Check the format of sampleText")
unittest {
    with (HelpBuilder) {
        auto make_optional(string name, string optShort, string optLong, NArgs nArgs) {
            return Optional(name, optShort, optLong, null, null, false, nArgs);
        }

        assert(sampleText(Positional("name")) == "name");

        assert(sampleText(make_optional("name", "-o", "--opt", NArgs("."))) == "-o --opt name");
        assert(sampleText(make_optional("name", "-o", null, NArgs("."))) == "-o name");
        assert(sampleText(make_optional("name", null, "--opt", NArgs("."))) == "   --opt name");

        assert(sampleText(make_optional("name", "-o", "--opt", NArgs("?"))) == "-o --opt name?");
        assert(sampleText(make_optional("name", "-o", "--opt", NArgs("*"))) == "-o --opt name...");
        assert(sampleText(make_optional("name", "-o", "--opt", NArgs("+"))) == "-o --opt name...");

        assert(sampleText(make_optional("name", "-o", "--opt", NArgs(0))) == "-o --opt");
        assert(sampleText(make_optional("name", "-o", "--opt", NArgs(1))) == "-o --opt name0");
        assert(sampleText(make_optional("name", "-o", "--opt", NArgs(2))) == "-o --opt name0 name1");
    }
}

@("Check building functions")
unittest {
    {
        // addDescription
        auto b = new HelpBuilder();
        b.addDescription("desc1");
        assert(b.descrptions_ == ["desc1"]);
        b.addDescription("desc2").addDescription("desc3");
        assert(b.descrptions_ == ["desc1", "desc2", "desc3"]);
    }
    {
        // addSubCommand
        auto b = new HelpBuilder();
        b.addSubCommand("cmd1", "desc1");
        assert(b.subCommands_ == [b.SubCommand("cmd1", "desc1")]);
        b.addSubCommand("cmd2", "desc2").addSubCommand("cmd3", "desc3");
        assert(b.subCommands_ == [
            b.SubCommand("cmd1", "desc1"), b.SubCommand("cmd2", "desc2"),
            b.SubCommand("cmd3", "desc3"),
        ]);
    }
    {
        // addPositional
        auto b = new HelpBuilder();
        b.addPositional("pos1", "desc1", "def1", true);
        assert(b.positionals_ == [b.Positional("pos1", "desc1", "def1", true)]);
        b.addPositional("pos2", "desc2", null, false).addPositional("pos3", "desc3", null, false);
        assert(b.positionals_ == [
            b.Positional("pos1", "desc1", "def1", true),
            b.Positional("pos2", "desc2", null, false),
            b.Positional("pos3", "desc3", null, false),
        ]);
    }
    {
        // addOptional
        auto b = new HelpBuilder();
        b.addOptional("opt1", "-o", "--opt1", "desc1", "def1", false, NArgs("."));
        assert(b.optionals_ == [
            b.Optional("opt1", "-o", "--opt1", "desc1", "def1", false, NArgs("."))
        ]);
        b.addOptional("opt2", null, "--opt2", "desc2", null, true, NArgs(1))
            .addOptional("opt3", "-p", null, "desc3", null, false, NArgs("*"));
        assert(b.optionals_ == [
            b.Optional("opt1", "-o", "--opt1", "desc1", "def1", false, NArgs(".")),
            b.Optional("opt2", null, "--opt2", "desc2", null, true, NArgs(1)),
            b.Optional("opt3", "-p", null, "desc3", null, false, NArgs("*")),
        ]);
    }
    {
        // setHelpOptional
        auto b = new HelpBuilder();
        assert(b.helpOptional_.isNull());
        b.setHelpOptional("-h", "--help", "desc");
        assert(b.helpOptional_ == b.Optional("help", "-h", "--help", "desc", null, false));
    }
    {
        // setFooter
        auto b = new HelpBuilder();
        b.setFooter("footer");
        assert(b.footer_ == "footer");
    }
}

@("Build help message with individual element")
unittest {
    import std.stdio;

    {
        // No optionals, positionals
        auto b = new HelpBuilder();
    }
    {
        // Help message
        auto b = new HelpBuilder();
        b.setHelpOptional("-h", "--help", "Display this message");
    }
    {
        // Positionals
        auto b = new HelpBuilder();
        b.addPositional("pos1", "desc1", null, true);
        b.addPositional("pos2", "desc2", null, false);
    }
}
