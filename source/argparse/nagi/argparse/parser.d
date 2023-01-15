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
import nagi.argparse.types;
import nagi.argparse.action;
import nagi.argparse.help_format;

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
        if (helpOption_.id) {
            if (canFind(argsWithCommandName, helpOption_.optShort) ||
                canFind(argsWithCommandName, helpOption_.optLong)
                ) {
                messageSink_.writeln(generateHelpMessage(argsWithCommandName[0], this.helpText_, this.positionals_, this
                        .subParsers_, this.optionals_, this.helpOption_));
                return null;
            }
        }
        auto countedPositionals = counted(this.positionals_);
        auto countedOptionals = counted(this.optionals_);
        auto result = new ParseResult();

        // set false for flags
        this.optionals_
            .filter!(o => o.nArgs == fromText(0))
            .each!((o) { result[o.id] = false; });
        // set [] for array
        this.optionals_
            .filter!(o => o.nArgs == fromText("*"))
            .each!((o) { result[o.id] = cast(string[])[]; });

        parseImpl(argsWithCommandName[1 .. $], countedPositionals, countedOptionals, result);

        countedPositionals.each!((p) { validate(p); });
        countedOptionals.each!((o) { validate(o); });

        return result;
    }

    private ParseResult parseAsSubParsers(string[] argsWithCommandName) {
        assert(argsWithCommandName.length > 0);
        assert(positionals_.length == 0);
        auto prog = argsWithCommandName[0];
        auto optionals = counted(helpOption_.id !is null ? (helpOption_ ~ optionals_) : optionals_);
        auto result = new ParseResult();
        auto argsForSubParser = parseImplForSubParser(argsWithCommandName[1 .. $], optionals, result);
        if (helpOption_.id && helpOption_.id in result) {
            messageSink_.writeln(generateHelpMessage(argsWithCommandName[0], this.helpText_, this.positionals_, this
                    .subParsers_, this.optionals_, this.helpOption_));
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
}

@("ArgumentParser.parse for end point")
unittest {
    auto parser = new ArgumentParser();
    parser.positionals_ = [
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
    ];
    parser.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
    ];
    parser.helpOption_ = ArgOptional("help", null, "-h", "--help", false, fromText(0), &defaultArgOptionalAction);

    {
        const result = parser.parse([
            "prog", "POS", "123.45", "-o", "-p", "ABC", "--qqq", "123", "--qqq",
            "456", "--", "REST1", "REST2"
        ]);
        assert(result !is null);
        assert("pos1" in result && result["pos1"].as!string == "POS");
        assert("pos2" in result && result["pos2"].as!double == 123.45);
        assert("o" in result && result["o"].as!bool == true);
        assert("p" in result && result["p"].as!string == "ABC", text(result));
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
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
    ];
    parser.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
    ];
    parser.helpOption_ = ArgOptional("help", "", "-h", "--help", false, fromText(0), &defaultArgOptionalAction);

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
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
    ];
    parser.helpOption_ = ArgOptional("help", "", "-h", "--help", false, fromText(0), &defaultArgOptionalAction);

    sub1.name_ = "sub1";
    sub1.optionals_ = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
    ];
    sub1.helpOption_ = ArgOptional("help", "", "-h", "--help", false, fromText(0), &defaultArgOptionalAction);

    sub2.name_ = "sub2";
    sub2.optionals_ = [
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
    ];
    sub2.helpOption_ = ArgOptional("help", "", "-h", "--help", false, fromText(0), &defaultArgOptionalAction);
    sub2.subParsers_ = [sub2sub];

    sub2sub.name_ = "sub";
    sub2sub.optionals_ = [
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
    ];
    sub2sub.positionals_ = [
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
    ];
    sub2sub.helpOption_ = ArgOptional("help", "", "-h", "--help", false, fromText(0), &defaultArgOptionalAction);

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

private void parseImpl(
    string[] args,
    Counter!(ArgPositional)[] positionals,
    Counter!(ArgOptional)[] optionals,
    ParseResult result,
) {
    if (args.length == 0) {
        return;
    }
    auto argKind = detectArgKind(args[0]);
    with (ArgKind) final switch (argKind) {
    case seperator:
        result.trail ~= args[1 .. $];
        break;
    case optShort, optLong:
        foreach (ref optional; optionals) {
            if (matchOption(args[0], optional)) {
                if (optional.count == 0) {
                    parseResultInitialize(optional.id, optional.nArgs, result);
                }
                optional.count++;
                auto consumeArgs = optional.action(args, optional.id, optional.nArgs, result);
                parseImpl(args[consumeArgs .. $], positionals, optionals, result);
                return;
            }
        }
        enforce!ArgumentException(false, text("Unknown option: ", args[0]));
        assert(0);
    case someValue:
        if (positionals.length == 0) {
            result.trail ~= args[0];
            parseImpl(args[1 .. $], positionals, optionals, result);
        }
        else {
            if (positionals[0].count == 0) {
                parseResultInitialize(positionals[0].id, positionals[0].nArgs, result);
            }
            positionals[0].count++;
            auto consumeArgs = positionals[0].action(args, positionals[0].id, positionals[0].nArgs, result);
            auto consumePositionals = argPositionalIsFilled(positionals[0].id, positionals[0].nArgs, result) ? 1
                : 0;
            parseImpl(args[consumeArgs .. $], positionals[consumePositionals .. $], optionals, result);
        }
    }
}

@("Positional argument can be parsed by parseImpl")
unittest {
    auto positionals = [
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
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
        ArgOptional("opt1", "", "-o", "--opt1", false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("opt2", "", null, "--opt2", false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("opt3", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
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
        ArgOptional("o", "", "-o", null, false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", "-q", null, false, fromText("*"), &defaultArgOptionalAction),
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
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
    ];
    auto optionals = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
    ];

    auto result = new ParseResult();
    parseImpl([
        "POS", "123.45", "-o", "-p", "ABC", "--qqq", "123", "--qqq", "456",
        "--", "REST1", "REST2"
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
        ArgPositional("pos1", "", true, fromText("."), &defaultArgPositionalAction),
        ArgPositional("pos2", "", false, fromText("."), &defaultArgPositionalAction),
    ];
    auto optionals = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("p", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("q", "", null, "--qqq", false, fromText("*"), &defaultArgOptionalAction),
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

@("--option=OPT pattern")
unittest {
    auto optionals = [
        ArgOptional("opt1", "", "-o", "--opt1", false, fromText(0), &defaultArgOptionalAction),
        ArgOptional("opt2", "", "-p", "--opt2", false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("opt3", "", "-q", "--opt3", false, fromText("*"), &defaultArgOptionalAction),
    ];
    {
        auto result = new ParseResult();
        parseImpl(["-o=true", "-p=ABC", "-q=123", "-q=456"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!bool == true);
        assert("opt2" in result && result["opt2"].as!string == "ABC");
        assert("opt3" in result && result["opt3"].as!(int[]) == [123, 456]);
    }
    {
        auto result = new ParseResult();
        parseImpl(["--opt1=true", "--opt2=ABC", "--opt3=123", "--opt3=456"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!bool == true);
        assert("opt2" in result && result["opt2"].as!string == "ABC");
        assert("opt3" in result && result["opt3"].as!(int[]) == [123, 456]);
    }
    {
        auto result = new ParseResult();
        parseImpl(["--opt1=false"], [], counted(optionals), result);
        assert("opt1" in result && result["opt1"].as!bool == false);
    }

}

private string[] parseImplForSubParser(
    string[] args,
    Counter!(ArgOptional)[] optionals,
    ParseResult result,
) {
    if (args.length == 0) {
        return [];
    }
    auto argKind = detectArgKind(args[0]);
    with (ArgKind) final switch (argKind) {
    case seperator:
        result.trail ~= args[1 .. $];
        return [];
    case optShort, optLong:
        foreach (ref optional; optionals) {
            if (matchOption(args[0], optional)) {
                if (optional.count == 0) {
                    parseResultInitialize(optional.id, optional.nArgs, result);
                }
                optional.count++;
                auto consumeArgs = optional.action(args, optional.id, optional.nArgs, result);
                return parseImplForSubParser(args[consumeArgs .. $], optionals, result);
            }
        }
        enforce!ArgumentException(false, text("Unknown option: ", args[0]));
        assert(0);
    case someValue:
        return args;
    }
}

@("parseImplForSubParser parses options till non-optional argument is found")
unittest {
    auto optionals = [
        ArgOptional("opt1", "", "-o", "--opt1", false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("opt2", "", null, "--opt2", false, fromText("."), &defaultArgOptionalAction),
        ArgOptional("opt3", "", "-p", null, false, fromText("."), &defaultArgOptionalAction),
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
        enforce!ArgumentException(arg.count == 1, text("Positional argument ", arg.id, " should be specified"));
    }
}

private void validate(in Counter!ArgOptional arg) {
    import std.exception;
    import std.sumtype;

    if (arg.isRequired) {
        arg.nArgs.match!(
            (NArgsOption n) {
            with (NArgsOption) final switch (n) {
            case one:
                enforce!ArgumentException(arg.count == 1, text(
                    "Optional argument ", arg.id,
                    " should be specified once, but actually set ", arg.count, " times"));
                break;
            case zeroOrOne:
                assert(0);
            case moreThanEqualZero:
                enforce!ArgumentException(arg.count > 0, text("Optional argument ", arg.id, " should be specified"));
                break;
            case moreThanEqualOne:
                assert(0);
            }
        },
            (uint n) {
            switch (n) {
            case 0:
                enforce!ArgumentException(arg.count == 1, text(
                    "Optional argument ", arg.id,
                    " should be specified once, but actually set ", arg.count, " times"));
                break;
            default:
                assert(0);
            }
        },
        );
    }
}
