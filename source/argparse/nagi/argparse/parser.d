module nagi.argparse.parser;

import std.variant;
import std.typecons;
import std.string;
import std.algorithm;
import std.array;
import std.string;
import std.conv;

class ArgumentParser {
    ParseResult parse(string[] argsWithCommandName) {
        assert(argsWithCommandName.length > 0);
        if (helpOption_.name) {
            if (canFind(argsWithCommandName, helpOption_.optShort) ||
                canFind(argsWithCommandName, helpOption_.optLong)
                ) {
                // ToDo: Show help message here.
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

    package this() {
    }

    package string name_;
    package string helpText_;
    package string shortDescription_;
    package ArgPositional[] positionals_;
    package ArgOptional[] optionals_;
    package ArgOptional helpOption_;
    package ArgumentParser[] subParsers_;

}

@("ArgumentParser.parse")
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
        assert(parser.parse(["prog", "--help"]) is null);
        assert(parser.parse(["prog", "-h"]) is null);
    }
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
    assert(ParseValue(["123.45", "456.78"]).as!(double[]) == [123.45, 456.78]);
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

void parseImpl(
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
        parseImpl(["POS1", "123", "REST1", "REST2"], counted(positionals), [], result);
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
        "POS", "123.45", "-o", "--", "-p", "ABC", "--qqq", "123", "--qqq", "456",
    ], counted(positionals), counted(optionals), result);
    assert("pos1" in result && result["pos1"].as!string == "POS");
    assert("pos2" in result && result["pos2"].as!double == 123.45);
    assert("o" in result && result["o"].as!bool == true);
    assert("p" !in result);
    assert("q" !in result);
    assert(result.trail == ["-p", "ABC", "--qqq", "123", "--qqq", "456"]);
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
