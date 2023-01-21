module nagi.argparse.validation;

import std.exception;
import std.sumtype;
import std.conv;
import std.range;
import std.algorithm;
import std.array;

import nagi.argparse.types;
import nagi.argparse.utils;

// Validation at parser building

void checkPositionalsConsistency(in ArgPositional[] positionals) {
    bool foundSequence = false;
    bool hasNonRequired = false;
    foreach (i, a; positionals) {
        enforce!ArgumentException(a.id && a.id != "", text(i, "th positional argument's id is empty"));
        enforce!ArgumentException(a.nArgs != NArgs(0), text(a.nArgs, " for nArgs is not allowed for positional"));
        enforce!ArgumentException(!foundSequence,
            text(a.id, " is never set because some unbounded sequence is already defined."));
        enforce!ArgumentException(!hasNonRequired || !a.isRequired,
            text("Required argument ", a.id, " is not allowed after the non-required positional argument"));
        if (a.nArgs == NArgs("*") || a.nArgs == NArgs("+")) {
            foundSequence = true;
        }
        if (!a.isRequired) {
            hasNonRequired = true;
        }
    }
    foreach (i; 0 .. positionals.length) {
        foreach (j; i + 1 .. positionals.length) {
            enforce!ArgumentException(positionals[i].id != positionals[j].id,
                text(j, "th positional argument's id conflicts with ", i, "th : ", positionals[i]
                    .id));
        }
    }
}

unittest {
    assertThrown(checkPositionalsConsistency([ArgPositional()]));
    assertThrown(checkPositionalsConsistency([ArgPositional("")]));
    assertThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs(0))
        ]));
    assertThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs("*")),
            ArgPositional("b", "", true),
        ]));
    assertThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs("+")),
            ArgPositional("b", "", true),
        ]));
    assertThrown(checkPositionalsConsistency([
            ArgPositional("a", "", false),
            ArgPositional("b", "", true),
        ]));
    assertThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true),
            ArgPositional("b", "", true),
            ArgPositional("a", "", true),
        ]));

    assertNotThrown(checkPositionalsConsistency([ArgPositional("a")]));
    assertNotThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs(1))
        ]));
    assertNotThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true), ArgPositional("b", "", true)
        ]));
    assertNotThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true), ArgPositional("b", "", false)
        ]));
    assertNotThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs(".")),
            ArgPositional("b", "", true, NArgs("?")),
            ArgPositional("c", "", true, NArgs("*")),
        ]));
    assertNotThrown(checkPositionalsConsistency([
            ArgPositional("a", "", true, NArgs(".")),
            ArgPositional("b", "", true, NArgs("?")),
            ArgPositional("c", "", true, NArgs("+")),
        ]));
}

void checkOptionalsConsistency(in ArgOptional[] optionals) {
    import std.regex;

    foreach (i, a; optionals) {
        enforce!ArgumentException(a.id && a.id != "", text(i, "th optional argument's id is empty"));
        enforce!ArgumentException((a.optShort && a.optShort != "") || (a.optLong && a.optLong != ""),
            text("At least one of optShort and optLong should have option : ", a.id));
        enforce!ArgumentException(!a.optShort || a.optShort == "" || matchFirst(a.optShort, regex(
                r"^-\w$")),
            text("Invalid optShort format for ", a.id, " : ", a.optShort));
        enforce!ArgumentException(!a.optLong || a.optLong == "" || matchFirst(a.optLong, regex(
                r"^--\w[\w-_]*$")),
            text("Invalid optLong format for ", a.id, " : ", a.optLong));
    }
    foreach (i; 0 .. optionals.length) {
        foreach (j; i + 1 .. optionals.length) {
            auto a = optionals[i];
            auto b = optionals[j];
            enforce!ArgumentException(a.id != b.id,
                text(j, "th optional argument's id conflicts with ", i, "th : ", a.id));

            if (b.optShort && b.optShort != "") {
                enforce!ArgumentException(a.optShort != b.optShort,
                    text("optShort of ", a.id, " conflicts with ", b.id, " : ", a.optShort));
            }
            if (b.optLong && b.optLong != "") {
                enforce!ArgumentException(a.optLong != b.optLong,
                    text("optLong of ", a.id, " conflicts with ", b.id, " : ", a.optLong));
            }
        }
    }
}

unittest {
    assertThrown!ArgumentException(checkOptionalsConsistency([
                ArgOptional(),
            ]));
    assertThrown!ArgumentException(checkOptionalsConsistency([
                ArgOptional(""),
            ]));
    foreach (opts; [
            cast(string[])[null, null],
            ["", ""],
            ["-", ""],
            ["--", ""],
            ["a", ""],
            ["aa", ""],
            ["-aa", ""],
            ["", "-"],
            ["", "-a"],
            ["", "--"],
            ["", "---"],
            ["", "---a"],
        ]) {
        assertThrown!ArgumentException(checkOptionalsConsistency([
                ArgOptional("a", "", opts[0], opts[1]),
            ]));
    }
    assertThrown!ArgumentException(checkOptionalsConsistency([
            ArgOptional("a", "", "-a"), ArgOptional("b", "", "-b"),
            ArgOptional("a", "", "-c"),
        ]));
    assertThrown!ArgumentException(checkOptionalsConsistency([
            ArgOptional("a", "", "-a"), ArgOptional("b", "", "-b"),
            ArgOptional("c", "", "-a"),
        ]));
    assertThrown!ArgumentException(checkOptionalsConsistency([
            ArgOptional("a", "", "", "--aaa"), ArgOptional("b", "", "", "--bbb"),
            ArgOptional("c", "", "", "--aaa"),
        ]));

    assertNotThrown!ArgumentException(checkOptionalsConsistency([
            ArgOptional("a", "", "-a"),
            ArgOptional("b", "", "-b"),
            ArgOptional("c", "", "", "--ccc"),
            ArgOptional("d", "", "", "--ddd"),
            ArgOptional("e", "", "-e", "--eee"),
        ]));

}

void checkArgConsistency(in ArgPositional[] positionals, in ArgOptional[] optionals) {
    checkPositionalsConsistency(positionals);
    checkOptionalsConsistency(optionals);

    struct ID {
        string id;
        string loc;
    }

    auto ids = positionals.enumerate().map!(tp => ID(tp[1].id, text(tp[0], "th positional"))).array()
        ~ optionals.enumerate().map!(tp => ID(tp[1].id, text(tp[0], "th optional"))).array();
    foreach (i; 0 .. ids.length) {
        foreach (j; i + 1 .. ids.length) {
            enforce!ArgumentException(ids[i].id != ids[j].id,
                text("id of ", ids[j].loc, " conflicts with ", ids[i].loc, " : ", ids[j].id));
        }
    }
}

unittest {
    assertThrown!ArgumentException(checkArgConsistency([
                ArgPositional("a"),
            ], [
                ArgOptional("a", "", "-a")
            ]));
    assertNotThrown!ArgumentException(checkArgConsistency([
                ArgPositional("a"),
            ], [
                ArgOptional("b", "", "-b")
            ]));
}

// Validation after parsing

void checkRequired(T)(in Counter!T arg) {
    if (arg.isRequired) {
        enforce!ArgumentException(arg.count > 0, text("Required argument '", arg.id, "' is not specified"));
    }
}

unittest {
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", false, NArgs(".")));
        assertNotThrown!ArgumentException(checkRequired(a));
    }
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", true, NArgs(".")));
        a.count = 1;
        assertNotThrown!ArgumentException(checkRequired(a));
    }
    {
        auto a = Counter!ArgPositional(ArgPositional("id", "", true, NArgs(".")));
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
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(txt)), new ParseResult()));
    }
    foreach (n; [0, 1, 2, 3]) {
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(n)), new ParseResult()));
    }
    foreach (txt; [".", "?"]) {
        auto result = new ParseResult();
        result["id"] = "ABC";
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(txt)), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = cast(string[])[];
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs("*")), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = ["ABC"];
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs("+")), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = false;
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(0)), result));
    }
    {
        auto result = new ParseResult();
        result["id"] = cast(string[])[];
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs("+")), result));
    }
    foreach (n; [1, 2, 3]) {
        import std.array;
        import std.range;

        auto result = new ParseResult();
        result["id"] = repeat("aaa", n).array();
        assertNotThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(n)), result));
    }

    foreach (n; [1, 2, 3]) {
        import std.array;
        import std.range;

        auto result = new ParseResult();
        result["id"] = repeat("aaa", 0).array();
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(n)), result));
        result["id"] = repeat("aaa", 10).array();
        assertThrown!ArgumentException(checkNARgs(ArgPositional(id, "", false, NArgs(n)), result));
    }
}
