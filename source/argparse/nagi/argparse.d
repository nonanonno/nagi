module nagi.argparse;
import std.stdio;
import std.algorithm;
import std.string;
import std.format;
import std.conv;
import std.sumtype;

struct MyOption {
    string pos1;
    string pos2;
    bool flag;
    int value;
    string data;
    string error;
}

void parseArg2(string[] args, ref MyOption opt, int position) {
    if (args.length == 0) {
        return;
    }
    if (args[0].startsWith("--")) {
        switch (args[0]) {
        case "--flag":
            opt.flag = true;
            parseArg2(args[1 .. $], opt, position);
            return;
        case "--value":
            if (args.length == 1) {
                opt.error = "Error for value";
                return;
            }
            if (!args[1].isNumeric) {
                opt.error = format("%s is not a number", args[1]);
                return;
            }
            opt.value = args[1].to!int;
            parseArg2(args[2 .. $], opt, position);
            return;
        case "--data":
            if (args.length == 1) {
                opt.error = "Error for data";
                return;
            }
            opt.data = args[1];
            parseArg2(args[2 .. $], opt, position);
            return;
        case "--help":
            writeln("usage");
            return;
        default:
            opt.error = format("Unknown option: %s", args[0]);
        }
    }
    else {
        if (position == 0) {
            opt.pos1 = args[0];
        }
        else if (position == 1) {
            opt.pos2 = args[1];
        }
        parseArg2(args[1 .. $], opt, position + 1);
    }
}

void parseArgumentImpl(T...)(ref Argument[] args, T opts) {
    static if (opts.length) {
        auto arg = getArgument(to!string(opts[0]));
        static if (is(typeof(opts[1]) : string)) {
            string help = opts[1];
            alias receiver = opts[2];
            immutable lowSliceIndex = 3;
        }
        else {
            alias receiver = opts[1];
            string help = "";
            immutable lowSliceIndex = 2;
        }
        arg.match!(
            (ref Positional a) {
            a.help = help;
            a.callback = (string a) { *receiver = to!(typeof(*receiver))(a); };
        },
            (ref Option a) {
            a.help = help;
            a.callback = (string a) { *receiver = to!(typeof(*receiver))(a); };
        },
        );
        args ~= arg;
        parseArgumentImpl(args, opts[lowSliceIndex .. $]);
    }
}

unittest {
    Argument[] args;
    string data;
    string foo;
    parseArgumentImpl(args,
        "data", &data,
        "--foo|-f", &foo,
    );
    writeln(args);

}

enum OptionType {
    zero,
    one,
    any,
}

struct Option {
    string optShort;
    string optLong;
    string help;
    bool required;
    OptionType type;
    void delegate(string) callback;
}

struct Positional {
    string name;
    string help;
    bool requied;
    void delegate(string) callback;
}

alias Argument = SumType!(Positional, Option);

Argument getArgument(string arg) @trusted nothrow {
    import std.array;

    auto sp = split(arg, "|");
    string optLong = null;
    string optShort = null;
    string positional = null;
    foreach (s; sp) {
        if (s.startsWith("--")) {
            assert(!optLong);
            optLong = s;
        }
        else if (s.startsWith("-")) {
            assert(!optShort);
            optShort = s;
        }
        else {
            assert(!positional);
            assert(s.length);
            positional = s;
        }
    }
    if (positional) {
        assert(!optLong && !optShort);
        return Positional(positional).to!Argument;
    }
    if (optLong || optShort) {
        assert(!positional);
        return Option(optShort, optLong).to!Argument;
    }
    assert(0);
}

@safe unittest {
    auto pos = getArgument("foo");
    pos.match!(
        (Positional p) => assert(p.name == "foo"),
        _ => assert(0),
    );

    auto olong = getArgument("--foo");
    olong.match!(
        (Option o) { assert(o.optLong == "--foo"); assert(o.optShort == null); },
        _ => writeln(_),
    );

    auto olongshort = getArgument("--foo|-f");
    olongshort.match!(
        (Option o) { assert(o.optLong == "--foo"); assert(o.optShort == "-f"); },
        _ => writeln(_),
    );

    auto oshortlong = getArgument("--foo|-f");
    oshortlong.match!(
        (Option o) { assert(o.optLong == "--foo"); assert(o.optShort == "-f"); },
        _ => writeln(_),
    );
}
