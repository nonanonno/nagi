module nagi.argparse.validation;

import std.exception;
import std.sumtype;
import std.conv;

import nagi.argparse.types;
import nagi.argparse.utils;

void checkRequired(T)(in Counter!T arg) {
    if (arg.isRequired) {
        enforce!ArgumentException(arg.count > 0, text("Required argument '", arg.id, "' is not specified"));
    }
}

unittest {
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", false, fromText(".")));
        assertNotThrown!ArgumentException(checkRequired(a));
    }
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", true, fromText(".")));
        a.count = 1;
        assertNotThrown!ArgumentException(checkRequired(a));
    }
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", true, fromText(".")));
        assertThrown!ArgumentException(checkRequired(a));
    }
}

void checkNARgs(T)(in T arg, ParseResult result) {
    // dfmt off
    arg.nArgs.match!(
        (NArgsOption n) {
            with (NArgsOption) switch (n) {
            case moreThanEqualOne:
                if (arg.id in result) {
                    enforce!ArgumentException(result[arg.id].as!(string[]).length > 0,
                        text("'", arg.id, "' should have more than one arguments"));
                }
                break;
            default:
                break;
            }
        },
        (uint n) {
            if (n > 0) {
                if (arg.id in result) {
                    enforce!ArgumentException(result[arg.id].as!(string[]).length == n,
                        text("'", arg.id, "' should have n arguments"));
                }
            }
        },
    );
    // dfmt on
}

unittest {
    auto id = "id";
    foreach (txt; [".", "?", "*", "+"]) {
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(txt)), new ParseResult()));
    }
    foreach (n; [0, 1, 2, 3]) {
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(n)), new ParseResult()));
    }
    foreach (txt; [".", "?"]) {
        auto result = new ParseResult();
        result["id"] = "ABC";
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(txt)), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = cast(string[])[];
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText("*")), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = ["ABC"];
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText("+")), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = false;
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(0)), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = cast(string[])[];
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText("+")), result));
    }
    foreach (n; [1, 2, 3]) {
        import std.array;
        import std.range;

        auto result = new ParseResult();
        result["id"] = repeat("aaa", n).array();
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(n)), result));
    }

    foreach (n; [1, 2, 3]) {
        import std.array;
        import std.range;

        auto result = new ParseResult();
        result["id"] = repeat("aaa", 0).array();
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(n)), result));
        result["id"] = repeat("aaa", 10).array();
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, fromText(n)), result));
    }
}
