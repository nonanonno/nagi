module nagi.argparse.action;

import nagi.argparse.types;
import std.conv;
import std.exception;

int defaultArgPositionalAction(string[] args, string id, NArgs nargs, ParseResult result) {
    assert(args.length > 0);
    with (NArgs) final switch (nargs) {
    case zero:
        assert(0, "Positional argument needs at least one argument.");
    case one:
        result.args[id] = args[0];
        return 1;
    case any:
        assert(0, "Any is not supported for positional argument.");
    }
}

int defaultArgOptionalAction(string[] args, string id, NArgs nargs, ParseResult result) {
    assert(args.length > 0);
    auto opt = parseOption(args[0]);

    with (NArgs) final switch (nargs) {
    case zero:
        if (opt.length == 1) {
            result.args[id] = true;
        }
        else {
            result.args[id] = opt[1].to!bool;
        }
        return 1;
    case one:
        if (opt.length == 1) {
            enforce!ArgumentException(args.length > 1, text("Need one following argument for ", opt[0]));
            result.args[id] = args[1];
            return 2;
        }
        else {
            result.args[id] = opt[1];
            return 1;
        }
    case any:
        result.args.require(id, ArgValue(cast(string[])[]));
        if (opt.length == 1) {
            enforce!ArgumentException(args.length > 1, text("Need one following argument for ", opt[0]));
            result.args[id] ~= args[1];
            return 2;
        }
        else {
            result.args[id] ~= opt[1];
            return 1;
        }
    }
}

bool matchOption(string arg, ArgOptional optional) {
    auto opt = parseOption(arg);
    return optional.optShort == opt[0] || optional.optLong == opt[0];
}

private string[] parseOption(string arg) {
    import std.regex;

    auto equalPattern = regex(r"^(--?[\w-_]+)=(.*)$");
    if (auto m = matchFirst(arg, equalPattern)) {
        return [m[1], m[2]];
    }
    else {
        return [arg];
    }
}

unittest {
    assert(parseOption("--opt") == ["--opt"]);
    assert(parseOption("-o") == ["-o"]);
    assert(parseOption("--opt=") == ["--opt", ""]);
    assert(parseOption("-o=") == ["-o", ""]);
    assert(parseOption("--opt=OPT") == ["--opt", "OPT"]);
    assert(parseOption("-o=OPT") == ["-o", "OPT"]);
    assert(parseOption("--opt=OPT=FOO") == ["--opt", "OPT=FOO"]);
    assert(parseOption("-o=OPT=FOO") == ["-o", "OPT=FOO"]);
    assert(parseOption("--opt-opt=OPT=FOO") == ["--opt-opt", "OPT=FOO"]);
    assert(parseOption("--opt_opt=OPT=FOO") == ["--opt_opt", "OPT=FOO"]);
    assert(parseOption("pos-pos=FOO") == ["pos-pos=FOO"]);

}
