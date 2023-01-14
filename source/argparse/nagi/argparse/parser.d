module nagi.argparse.parser;

import std.variant;
import std.typecons;
import std.string;
import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.exception;
import std.stdio : stdout, File;

class ArgumentParser {
    ParseResult parse(string[] argsWithCommandName) {
        if (subParsers_.length == 0) {
            return parseAsEndPoint(argsWithCommandName);
        }
        else {
            return parseAsSubParsers(argsWithCommandName);
        }
    }

    package this() {
        messageSink_ = stdout;
    }

    package string name_;
    package string helpText_;
    package string shortDescription_;
    package ArgPositional[] positionals_;
    package ArgOptional[] optionals_;
    package ArgOptional helpOption_;
    package ArgumentParser[] subParsers_;
    package File messageSink_;

    private ParseResult parseAsEndPoint(string[] argsWithCommandName) {
        assert(argsWithCommandName.length > 0);
        assert(subParsers_.length == 0);
        if (helpOption_.name) {
            if (canFind(argsWithCommandName, helpOption_.optShort) ||
                canFind(argsWithCommandName, helpOption_.optLong)
                ) {
                messageSink_.writeln(this.generateHelpMessage(argsWithCommandName[0]));
                return null;
            }
        }
        auto countedPositionals = counted(this.positionals_);
        auto countedOptionals = counted(this.optionals_);
        auto result = new ParseResult();

        // set false for flags
        this.optionals_
            .filter!(o => o.nArgs == NArgs.zero)
            .each!((o) { result[o.name] = false; });
        // set [] for array
        this.optionals_
            .filter!(o => o.nArgs == NArgs.any)
            .each!((o) { result[o.name] = cast(string[])[]; });

        parseImpl(argsWithCommandName[1 .. $], countedPositionals, countedOptionals, result);

        countedPositionals.each!((p) { validate(p); });
        countedOptionals.each!((o) { validate(o); });

        return result;
    }

    private ParseResult parseAsSubParsers(string[] argsWithCommandName) {
        assert(argsWithCommandName.length > 0);
        assert(positionals_.length == 0);
        auto prog = argsWithCommandName[0];
        auto optionals = counted(helpOption_.name !is null ? (helpOption_ ~ optionals_) : optionals_);
        auto result = new ParseResult();
        auto argsForSubParser = parseImplForSubParser(argsWithCommandName[1 .. $], optionals, result);
        if (helpOption_.name && helpOption_.name in result) {
            messageSink_.writeln(this.generateHelpMessage(argsWithCommandName[0]));
            return null;
        }
        enforce!ArgumentException(argsForSubParser.length > 0, text("Need a command"));
        auto foundSubParsers = this.subParsers_.find!(p => p.name_ == argsForSubParser[0]);

        enforce!ArgumentException(foundSubParsers.length > 0,
            text("Unknown command ", argsForSubParser[0], " found."));

        auto subParser = foundSubParsers[0];
        auto subParserResult = subParser.parse(argsForSubParser);
        if (subParserResult is null) {
            // help is specified. Do nothing.
            return null;
        }
        result.subCommand = tuple(subParser.name_, subParserResult);

        return result;
    }

    string generateHelpMessage(string commandName) {
        enum nameBoxWidth = 18;
        enum helpBoxWidth = 60;
        enum gap = 2;
        string buffer;
        buffer ~= text("usage: ", commandName, " ");
        if (this.helpOption_.name !is null) {
            auto helpFlag = this.helpOption_.optShort ? this.helpOption_.optShort
                : this.helpOption_.optLong;
            buffer ~= text("[", helpFlag, "] ");
        }
        if (this.optionals_.length > 0) {
            buffer ~= "[OPTION] ";
        }
        if (this.subParsers_.length > 0) {
            buffer ~= format("{%-(%s,%)} ", this.subParsers_.map!(p => p.name_));
        }
        if (this.positionals_.length > 0) {
            buffer ~= format("%-(%s %) ", this.positionals_.map!(p => sampleText(p)));
        }
        buffer ~= "\n";
        if (this.helpText_) {
            buffer ~= "\n";
            buffer ~= wrap(this.helpText_, nameBoxWidth + helpBoxWidth + gap);
        }

        void append(T)(T[] args, string title) {
            if (args) {
                buffer ~= text("\n",
                    title, "\n",
                    replicate("=", title.length), "\n"
                );
                args.each!((a) {
                    buffer ~= generateHelpItem(a, nameBoxWidth, helpBoxWidth, gap);
                });
            }
        }

        append(this.subParsers_, "Sub commands");
        append(this.positionals_.filter!(a => a.isRequired).array(), "Required positional argument");
        append(this.positionals_.filter!(a => !a.isRequired).array(), "Non-required positional argument");
        append(this.optionals_.filter!(a => a.isRequired).array(), "Required optional argument");
        auto nonRequiredOptionals = this.optionals_.filter!(a => !a.isRequired).array();
        if (this.helpOption_.name) {
            nonRequiredOptionals ~= this.helpOption_;
        }

        append(nonRequiredOptionals, "Non-required optional argument");

        return buffer;
    }
}

@("ArgumentParser.parse for end point")
unittest {
    auto parser = new ArgumentParser();
    parser.positionals_ = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    parser.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];
    parser.helpOption_ = ArgOptional("help", null, "-h", "--help", false, NArgs.zero);

    {
        const result = parser.parse([
            "prog", "POS", "123.45", "-o", "-p", "ABC", "--qqq", "123", "--qqq",
            "456", "REST1", "REST2"
        ]);
        assert(result !is null);
        assert("pos1" in result && result["pos1"].as!string == "POS");
        assert("pos2" in result && result["pos2"].as!double == 123.45);
        assert("o" in result && result["o"].as!bool == true);
        assert("p" in result && result["p"].as!string == "ABC");
        assert("q" in result && result["q"].as!(int[]) == [123, 456]);
        assert(result.trail == ["REST1", "REST2"]);
    }
    {
        const result = parser.parse(["prog", "POS"]);
        assert(result !is null);
        assert("pos1" in result && result["pos1"].as!string == "POS");
        assert("pos2" !in result);
        assert("o" in result && result["o"].as!bool == false);
        assert("p" !in result);
        assert("q" in result && result["q"].as!(string[]) == [], text(result));
    }
}

@("Help for ArgumentParser end point")
unittest {
    auto parser = new ArgumentParser();
    parser.positionals_ = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    parser.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];
    parser.helpOption_ = ArgOptional("help", "", "-h", "--help", false, NArgs.zero);

    {
        auto tmp = File.tmpfile();
        parser.messageSink_ = tmp;
        assert(parser.parse(["prog", "-h"]) is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        parser.messageSink_ = tmp;
        assert(parser.parse(["prog", "--help"]) is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        parser.messageSink_ = tmp;
        assert(parser.parse(["prog", "POS1", "-o", "--help"]) is null);
        assert(tmp.size() > 0);
    }

}

@("ArgmentParser.parse for subparsers")
unittest {
    auto parser = new ArgumentParser();
    auto sub1 = new ArgumentParser();
    auto sub2 = new ArgumentParser();
    auto sub2sub = new ArgumentParser();

    sub1.name_ = "sub1";
    sub2.name_ = "sub2";
    sub2.subParsers_ ~= sub2sub;
    sub2sub.name_ = "subsub";
    parser.subParsers_ ~= sub1;
    parser.subParsers_ ~= sub2;

    {
        auto ret = parser.parse(["prog", "sub1"]);
        assert(ret !is null);
        assert(ret.subCommand.name == "sub1");
        assert(ret.subCommand.result !is null);
    }
    {
        auto ret = parser.parse(["prog", "sub2", "subsub"]);
        assert(ret !is null);
        assert(ret.subCommand.name == "sub2");
        assert(ret.subCommand.result !is null);
        assert(ret.subCommand.result.subCommand.name == "subsub");
        assert(ret.subCommand.result.subCommand.result !is null);
    }

}

@("SubParsers with options")
unittest {
    auto parser = new ArgumentParser();
    auto sub1 = new ArgumentParser();
    auto sub2 = new ArgumentParser();
    auto sub2sub = new ArgumentParser();

    parser.subParsers_ = [sub1, sub2];
    parser.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];
    parser.helpOption_ = ArgOptional("help", "", "-h", "--help", false, NArgs.zero);

    sub1.name_ = "sub1";
    sub1.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
    ];
    sub1.helpOption_ = ArgOptional("help", "", "-h", "--help", false, NArgs.zero);

    sub2.name_ = "sub2";
    sub2.optionals_ = [
        ArgOptional("p", "", "-p", null, false, NArgs.one),
    ];
    sub2.helpOption_ = ArgOptional("help", "", "-h", "--help", false, NArgs.zero);
    sub2.subParsers_ = [sub2sub];

    sub2sub.name_ = "sub";
    sub2sub.optionals_ = [
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];
    sub2sub.positionals_ = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    sub2sub.helpOption_ = ArgOptional("help", "", "-h", "--help", false, NArgs.zero);

    void setSink(File f) {
        [parser, sub1, sub2, sub2sub].each!((p) { p.messageSink_ = f; });
    }

    // help
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "-h"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "-o", "-h"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "-o", "-h", "sub1"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "sub1", "-h"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "sub2", "-h"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "sub2", "-h", "sub"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }
    {
        auto tmp = File.tmpfile();
        setSink(tmp);
        auto ret = parser.parse(["prog", "sub2", "sub", "-h"]);
        assert(ret is null);
        assert(tmp.size() > 0);
    }

    // Options
    {
        auto ret = parser.parse([
            "prog", "-o", "sub2", "-p", "ABC", "sub", "123"
        ]);
        assert(ret !is null);
        assert("o" in ret && ret["o"].as!bool == true);
        assert(ret.subCommand.name == "sub2");
        assert("p" in ret.subCommand.result && ret.subCommand.result["p"].as!string == "ABC");
        assert(ret.subCommand.result.subCommand.name == "sub");
        assert("pos1" in ret.subCommand.result.subCommand.result && ret
                .subCommand.result.subCommand.result["pos1"].as!int == 123);

    }
}

@("help message for end point")
unittest {
    auto positionals = [
        ArgPositional("pos1", "Help message for pos1", true),
        ArgPositional("pos2", "Help message for pos2", false),
    ];
    auto optionals = [
        ArgOptional("o", "Help message for option 1", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "Help message for option 2", "-p", null, false, NArgs.one),
        ArgOptional("q", "Help message for option 3", null, "--qqq", false, NArgs.any),
    ];
    auto helpArg = ArgOptional("help", "Display this message", "-h", "--help", false, NArgs.zero);
    auto helpText = text(
        "This is a sample help message for testing. Since the message count is over 80, t",
        "he message will be wrapped.");

    {
        auto expected = text("usage: prog [-h] [OPTION] <POS1> [POS2] \n",
            "\n",
            "This is a sample help message for testing. Since the message count is over 80,\n",
            "the message will be wrapped.\n",
            "\n",
            "Required positional argument\n",
            "============================\n",
            "  <POS1>            Help message for pos1\n",
            "\n",
            "Non-required positional argument\n",
            "================================\n",
            "  [POS2]            Help message for pos2\n",
            "\n",
            "Non-required optional argument\n",
            "==============================\n",
            "  -o, --opt         Help message for option 1\n",
            "  -p   <P>          Help message for option 2\n",
            "      --qqq <Q...>  Help message for option 3\n",
            "  -h, --help        Display this message\n",
        );

        auto parser = new ArgumentParser();
        parser.positionals_ = positionals;
        parser.optionals_ = optionals;
        parser.helpOption_ = helpArg;
        parser.helpText_ = helpText;

        assert(parser.generateHelpMessage("prog") == expected);
    }
    {
        auto expected = text("usage: prog [-h] [OPTION] \n",
            "\n",
            "Non-required optional argument\n",
            "==============================\n",
            "  -o, --opt         Help message for option 1\n",
            "  -p   <P>          Help message for option 2\n",
            "      --qqq <Q...>  Help message for option 3\n",
            "  -h, --help        Display this message\n",
        );

        auto parser = new ArgumentParser();
        parser.optionals_ = optionals;
        parser.helpOption_ = helpArg;

        assert(parser.generateHelpMessage("prog") == expected);
    }
    {
        auto expected = text("usage: prog [-h] <POS1> [POS2] \n",
            "\n",
            "Required positional argument\n",
            "============================\n",
            "  <POS1>            Help message for pos1\n",
            "\n",
            "Non-required positional argument\n",
            "================================\n",
            "  [POS2]            Help message for pos2\n",
            "\n",
            "Non-required optional argument\n",
            "==============================\n",
            "  -h, --help        Display this message\n",
        );

        auto parser = new ArgumentParser();
        parser.positionals_ = positionals;
        parser.helpOption_ = helpArg;

        assert(parser.generateHelpMessage("prog") == expected);
    }
    {
        // Just for behavior check. In normal case, there is no way to show help message without helpOption.
        auto expected = text("usage: prog [OPTION] <POS1> [POS2] \n",
            "\n",
            "Required positional argument\n",
            "============================\n",
            "  <POS1>            Help message for pos1\n",
            "\n",
            "Non-required positional argument\n",
            "================================\n",
            "  [POS2]            Help message for pos2\n",
            "\n",
            "Non-required optional argument\n",
            "==============================\n",
            "  -o, --opt         Help message for option 1\n",
            "  -p   <P>          Help message for option 2\n",
            "      --qqq <Q...>  Help message for option 3\n",
        );

        auto parser = new ArgumentParser();
        parser.positionals_ = positionals;
        parser.optionals_ = optionals;

        assert(parser.generateHelpMessage("prog") == expected);
    }

}

class ArgumentException : Exception {
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}

struct ParseValue {
    Variant data;
    alias data this;

    this(T)(T value) {
        data = value;
    }

    auto opAssign(T)(T value) {
        data = value;
        return this;
    }

    T as(T)() const {
        import std.traits;
        import std.conv : to, text;
        import std.exception;

        static if (isNumeric!T || isBoolean!T) {
            if (data.convertsTo!real) {
                return to!T(data.get!real);
            }
            else if (data.convertsTo!(const(char)[])) {
                return to!T(data.get!(const(char)[]));
            }
            else if (data.convertsTo!(immutable(char)[])) {
                return to!T(data.get!(immutable(char)[]));
            }
            else {
                enforce(false, text("Type ", data.type(), " does not convert to ", typeid(T)));
                assert(0);
            }
        }
        else static if (is(T : Object)) {
            return to!(T)(data.get!(Object));
        }
        else static if (isSomeString!(T)) {
            return to!(T)((cast(Variant*)&data).toString());
        }
        else static if (isArray!(T)) {
            if (data.convertsTo!(T)) {
                return to!T(data.get!(T));
            }
            else if (data.convertsTo!(const(char)[][])) {
                return to!T(data.get!(const(char)[][]));
            }
            else if (data.convertsTo!(immutable(char)[][])) {
                return to!T(data.get!(immutable(char)[][]));
            }
            else {
                enforce(false, text("Type ", data.type(), " does not convert to ", typeid(T)));
                assert(0);
            }
        }
        else {
            static assert(false, text("unsupported type for as: ", typeid(T)));
        }
    }

    string toString() const @trusted {
        return (cast(Variant*)&data).toString();
    }
}

@("ParseValue can hold many types of value and `as` function can get it with expected type")
unittest {
    assert(ParseValue("abc").as!string == "abc");
    assert(ParseValue("123").as!int == 123);
    assert(ParseValue(123).as!int == 123);
    assert(ParseValue(123).as!string == "123");

    assert(ParseValue("123.45").as!float == 123.45f);
    assert(ParseValue(123.45).as!double == 123.45);
    assert(ParseValue("true").as!bool == true);
    assert(ParseValue(true).as!bool == true);
    assert(ParseValue("false").as!bool == false);

    assert(ParseValue(["abc", "def"]).as!(string[]) == ["abc", "def"]);
    assert(ParseValue(["123", "456"]).as!(int[]) == [123, 456]);
    assert(ParseValue(["123.45", "456.78"]).as!(double[]) == [
            123.45, 456.78
        ]);
    assert(ParseValue([123, 456]).as!(int[]) == [123, 456]);
    assert(ParseValue([123.45, 456.78]).as!(double[]) == [123.45, 456.78]);
}

@("Invalid convertion raises an exception")
unittest {
    import std.exception;

    assertThrown(ParseValue("abc").as!int);
    assertThrown(ParseValue(["abc", "def"]).as!(int[]));
    assertThrown(ParseValue([123, 456]).as!(double[]));
    assertThrown(ParseValue([123, 456]).as!(string[]));
}

class ParseResult {
    ParseValue[string] args;
    Tuple!(string, "name", ParseResult, "result") subCommand;
    string[] trail;

    alias args this;

    override string toString() const @safe {
        return text("ParseResult(",
            "args=", args, ", ",
            "subCommand=", subCommand, ", ",
            "trail=", trail, ")"
        );
    }
}

enum NArgs {
    zero,
    one,
    any,
}

package struct ArgPositional {
    string name;
    string helpText;
    bool isRequired;
}

package struct ArgOptional {
    string name;
    string helpText;
    string optShort; // with -
    string optLong; // with --
    bool isRequired;
    NArgs nArgs;
}

private struct Counter(T) {
    this(T data) {
        this.data = data;
    }

    T data;
    int count = 0;
    alias data this;
}

private Counter!(T)[] counted(T)(T[] t) {
    return t.map!(u => Counter!T(u)).array();
}

private void parseImpl(
    string[] args,
    Counter!(ArgPositional)[] positionals,
    Counter!(ArgOptional)[] optionals,
    ParseResult result,
) {
    if (args.length == 0) {
        return;
    }
    if (args[0] == "--") {
        result.trail ~= args[1 .. $];
        return;
    }
    if (startsWith(args[0], "-")) {
        auto found = optionals.find!(o => o.optShort == args[0] || o.optLong == args[0]);
        if (found.length == 0) {
            throw new ArgumentException(text("Unknown option ", args[0], " found"));
        }
        found[0].count++;
        with (NArgs) final switch (found[0].nArgs) {
        case zero:
            result.args[found[0].name] = true;
            parseImpl(args[1 .. $], positionals, optionals, result);
            break;
        case one:
            if (args.length < 2) {
                throw new ArgumentException(text("Need one following argument for ", args[0]));
            }
            result.args[found[0].name] = args[1];
            parseImpl(args[2 .. $], positionals, optionals, result);
            break;
        case any:
            if (args.length < 2) {
                throw new ArgumentException(text("Need one following argument for ", args[0]));
            }
            if (found[0].name !in result) {
                result[found[0].name] = [args[1]];
            }
            else {
                result[found[0].name] ~= args[1];
            }
            parseImpl(args[2 .. $], positionals, optionals, result);
        }
    }
    else {
        if (positionals.length == 0) {
            result.trail ~= args[0];
            parseImpl(args[1 .. $], positionals, optionals, result);
        }
        else {
            result[positionals[0].name] = args[0];
            positionals[0].count++;
            parseImpl(args[1 .. $], positionals[1 .. $], optionals, result);
        }
    }
}

@("Positional argument can be parsed by parseImpl")
unittest {
    auto positionals = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    {
        auto result = new ParseResult();
        parseImpl(["POS1"], counted(positionals), [], result);
        assert("pos1" in result && result["pos1"].as!string == "POS1");
    }
    {
        auto result = new ParseResult();
        parseImpl(["POS1", "123"], counted(positionals), [], result);
        assert("pos1" in result && result["pos1"].as!string == "POS1");
        assert("pos2" in result && result["pos2"].as!int == 123);
    }
    {
        auto result = new ParseResult();
        parseImpl(["POS1", "123", "REST1", "REST2"], counted(positionals), [
            ], result);
        assert("pos1" in result && result["pos1"].as!string == "POS1");
        assert("pos2" in result && result["pos2"].as!int == 123);
        assert(result.trail == ["REST1", "REST2"]);
    }
}

@("Short options and long options can be parsed by parseImpl")
unittest {
    auto optionals = [
        ArgOptional("opt1", "", "-o", "--opt1", false, NArgs.one),
        ArgOptional("opt2", "", null, "--opt2", false, NArgs.one),
        ArgOptional("opt3", "", "-p", null, false, NArgs.one),
    ];
    {
        auto result = new ParseResult();
        parseImpl([], [], counted(optionals), result);
        assert("opt1" !in result);
        assert("opt2" !in result);
        assert("opt3" !in result);
    }
    {
        auto result = new ParseResult();
        parseImpl(["-o", "OPT1"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!string == "OPT1");
    }
    {
        auto result = new ParseResult();
        parseImpl(["--opt1", "OPT1"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!string == "OPT1");
    }
    {
        auto result = new ParseResult();
        parseImpl(["--opt2", "OPT2"], [], counted(optionals), result);
        assert("opt2" in result && result["opt2"].as!string == "OPT2");
    }
    {
        auto result = new ParseResult();
        parseImpl(["-p", "OPT3"], [], counted(optionals), result);
        assert("opt3" in result && result["opt3"].as!string == "OPT3");
    }
    {
        auto result = new ParseResult();
        parseImpl(["--opt2", "OPT2", "-o", "OPT1", "-p", "OPT3"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!string == "OPT1");
        assert("opt2" in result && result["opt2"].as!string == "OPT2");
        assert("opt3" in result && result["opt3"].as!string == "OPT3");
    }
}

@("nArgs can be parsed by parseImpl")
unittest {
    auto optionals = [
        ArgOptional("o", "", "-o", null, false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", "-q", null, false, NArgs.any),
    ];
    {
        auto result = new ParseResult();
        parseImpl([], [], counted(optionals), result);
        assert("o" !in result);
        assert("p" !in result);
        assert("q" !in result);
    }
    {
        auto result = new ParseResult();
        parseImpl(["-o"], [], counted(optionals), result);
        assert("o" in result && result["o"].as!bool == true);
    }
    {
        auto result = new ParseResult();
        parseImpl(["-p", "ABC"], [], counted(optionals), result);
        assert("p" in result && result["p"].as!string == "ABC");
    }
    {
        auto result = new ParseResult();
        parseImpl(["-q", "123"], [], counted(optionals), result);
        assert("q" in result && result["q"].as!(string[]) == ["123"], text(result));
    }
    {
        auto result = new ParseResult();
        parseImpl(["-q", "123", "-q", "456"], [], counted(optionals), result);
        assert("q" in result && result["q"].as!(string[]) == ["123", "456"], text(result));
    }
    {
        auto result = new ParseResult();
        parseImpl(["-p", "ABC", "-q", "123", "-o", "-q", "456"], [], counted(optionals), result);
        assert("o" in result && result["o"].as!bool == true);
        assert("p" in result && result["p"].as!string == "ABC");
        assert("q" in result && result["q"].as!(string[]) == ["123", "456"], text(result));
    }
}

@("Combination test for parseImpl")
unittest {
    auto positionals = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    auto optionals = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];

    auto result = new ParseResult();
    parseImpl([
        "POS", "123.45", "-o", "-p", "ABC", "--qqq", "123", "--qqq", "456",
        "REST1",
        "REST2"
    ], counted(positionals), counted(optionals), result);
    assert("pos1" in result && result["pos1"].as!string == "POS");
    assert("pos2" in result && result["pos2"].as!double == 123.45);
    assert("o" in result && result["o"].as!bool == true);
    assert("p" in result && result["p"].as!string == "ABC");
    assert("q" in result && result["q"].as!(int[]) == [123, 456]);
    assert(result.trail == ["REST1", "REST2"]);
}

@("-- works for parseImpl")
unittest {
    auto positionals = [
        ArgPositional("pos1", "", true),
        ArgPositional("pos2", "", false),
    ];
    auto optionals = [
        ArgOptional("o", "", "-o", "--opt", false, NArgs.zero),
        ArgOptional("p", "", "-p", null, false, NArgs.one),
        ArgOptional("q", "", null, "--qqq", false, NArgs.any),
    ];

    auto result = new ParseResult();
    parseImpl([
        "POS", "123.45", "-o", "--", "-p", "ABC", "--qqq", "123", "--qqq",
        "456",
    ], counted(positionals), counted(optionals), result);
    assert("pos1" in result && result["pos1"].as!string == "POS");
    assert("pos2" in result && result["pos2"].as!double == 123.45);
    assert("o" in result && result["o"].as!bool == true);
    assert("p" !in result);
    assert("q" !in result);
    assert(result.trail == ["-p", "ABC", "--qqq", "123", "--qqq", "456"]);
}

private string[] parseImplForSubParser(
    string[] args,
    Counter!(ArgOptional)[] optionals,
    ParseResult result,
) {
    if (args.length == 0) {
        return [];
    }
    if (args[0] == "--") {
        result.trail ~= args[1 .. $];
        return [];
    }
    if (startsWith(args[0], "-")) {
        auto found = optionals.find!(o => o.optShort == args[0] || o.optLong == args[0]);
        if (found.length == 0) {
            throw new ArgumentException(text("Unknown option ", args[0], " found"));
        }
        found[0].count++;
        with (NArgs) final switch (found[0].nArgs) {
        case zero:
            result.args[found[0].name] = true;
            return parseImplForSubParser(args[1 .. $], optionals, result);
        case one:
            if (args.length < 2) {
                throw new ArgumentException(text("Need one following argument for ", args[0]));
            }
            result.args[found[0].name] = args[1];
            return parseImplForSubParser(args[2 .. $], optionals, result);
        case any:
            if (args.length < 2) {
                throw new ArgumentException(text("Need one following argument for ", args[0]));
            }
            if (found[0].name !in result) {
                result[found[0].name] = [args[1]];
            }
            else {
                result[found[0].name] ~= args[1];
            }
            return parseImplForSubParser(args[2 .. $], optionals, result);
        }
    }
    else {
        return args;
    }
}

@("parseImplForSubParser parses options till non-optional argument is found")
unittest {
    auto optionals = [
        ArgOptional("opt1", "", "-o", "--opt1", false, NArgs.one),
        ArgOptional("opt2", "", null, "--opt2", false, NArgs.one),
        ArgOptional("opt3", "", "-p", null, false, NArgs.one),
    ];
    auto result = new ParseResult();
    auto unparsed = parseImplForSubParser([
        "-o", "OPT1", "sub", "--opt2", "OPT2"
    ], counted(optionals), result);
    assert(unparsed == ["sub", "--opt2", "OPT2"]);
    assert("opt1" in result);
    assert("opt2" !in result);
}

private void validate(in Counter!ArgPositional arg) {
    import std.exception;

    if (arg.isRequired) {
        enforce!ArgumentException(arg.count == 1, text("Positional argument ", arg.name, " should be specified"));
    }
}

private void validate(in Counter!ArgOptional arg) {
    import std.exception;

    if (arg.isRequired) {
        with (NArgs) final switch (arg.nArgs) {
        case zero, one:
            enforce!ArgumentException(arg.count == 1, text(
                    "Optional argument ", arg.name,
                    " should be specified once, but actually set ", arg.count, " times"));
            break;
        case any:
            enforce!ArgumentException(arg.count > 0, text("Optional argument ", arg.name, " should be specified"));
            break;
        }
    }
}

string displayName(in ArgOptional arg) {
    auto state = (arg.optShort ? 0b10 : 0b00) | (arg.optLong ? 0b01 : 0b00);
    switch (state) {
    case 0b11:
        return text(arg.optShort, ", ", arg.optLong);
    case 0b10:
        return text(arg.optShort, "  ");
    case 0b01:
        return text("    ", arg.optLong);
    default:
        assert(false);
    }
}

string sampleText(in ArgPositional arg) {
    if (arg.isRequired) {
        return text("<", arg.name.toUpper(), ">");
    }
    else {
        return text("[", arg.name.toUpper(), "]");
    }
}

string sampleText(in ArgOptional arg) {
    with (NArgs) final switch (arg.nArgs) {
    case zero:
        return displayName(arg);
    case one:
        return text(displayName(arg), " <", arg.name.toUpper(), ">");
    case any:
        return text(displayName(arg), " <", arg.name.toUpper(), "...>");
    }
}

string sampleText(in ArgumentParser arg) {
    return arg.name_;
}

string descriptionText(in ArgPositional arg) {
    return arg.helpText;
}

string descriptionText(in ArgOptional arg) {
    return arg.helpText;
}

string descriptionText(in ArgumentParser arg) {
    return arg.shortDescription_;
}

string generateHelpItem(T)(in T arg, int nameBoxWidth, int helpBoxWidth, int gapWidth) {
    auto name = sampleText(arg);
    auto helpText = descriptionText(arg);
    auto indent = replicate(" ", gapWidth + nameBoxWidth);
    auto first = leftJustify(text("  ", name), nameBoxWidth);
    // Add 2 for wrap function. Without it, wrap function wraps text even if the word width equals to width.
    if (first.length <= nameBoxWidth) {
        return wrap(helpText, nameBoxWidth + gapWidth + helpBoxWidth + 2, first ~ replicate(" ", gapWidth), indent);
    }
    else {
        return text(first, "\n", wrap(helpText, nameBoxWidth + gapWidth + helpBoxWidth + 2, indent, indent));
    }
}

@("Test for generateHelpItem")
unittest {
    assert(generateHelpItem(ArgPositional("name", "help"), 10, 60, 2)
            == "  [NAME]    help\n");
    assert(generateHelpItem(ArgPositional("12", "1234567890"), 6, 10, 2)
            == "  [12]  1234567890\n");
    assert(generateHelpItem(ArgPositional("12", "1234567890 1234567890"), 6, 10, 2)
            == "  [12]  1234567890\n        1234567890\n");
    assert(generateHelpItem(ArgPositional("123", "1234567890 1234567890"), 6, 10, 2)
            == "  [123]\n        1234567890\n        1234567890\n");
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, NArgs.zero),
            24, 10, 2) == text(
            "  -o, --option            1234567890\n",
            "                          1234567890\n",
    ));
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, NArgs.one),
            24, 10, 2) == text(
            "  -o, --option <OPTION>   1234567890\n",
            "                          1234567890\n",
    ));
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, NArgs.any),
            24, 10, 2) == text(
            "  -o, --option <OPTION...>\n",
            "                          1234567890\n",
            "                          1234567890\n",
    ));
    auto parser = new ArgumentParser();
    parser.name_ = "command";
    parser.shortDescription_ = "short description";
    assert(generateHelpItem(parser, 10, 60, 2) == "  command   short description\n");
}
