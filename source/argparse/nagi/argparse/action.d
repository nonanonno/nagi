module nagi.argparse.action;

import nagi.argparse.types;
import nagi.argparse.utils;
import std.conv;
import std.exception;
import std.sumtype;
import std.variant;
import std.algorithm;
import std.array;

void parseResultInitialize(string id, NArgs nArgs, ParseResult result) {
    // dfmt off
    nArgs.match!(
        (NArgsOption n) {
            with (NArgsOption) final switch(n) {
            case one, zeroOrOne:
                result.args.remove(id);
                break;
            case moreThanEqualZero, moreThanEqualOne:
                result.args[id] = cast(string[])[];
                break;
            }
        },
        (uint n) {
            if (n == 0) {
                result.args[id] = false;
            } else {
                result.args[id] = cast(string[])[];
            }
        },
    );
    // dfmt on
}

string[] pickSomeValues(string[] args, int maxNum = int.max) {
    string[] ret;
    foreach (i; 0 .. args.length) {
        if (i == maxNum || detectArgKind(args[i]) != ArgKind.someValue) {
            break;
        }
        ret ~= args[i];
    }
    return ret;
}

unittest {
    assert(pickSomeValues(["a", "b", "c", "--", "d"]) == ["a", "b", "c"]);
    assert(pickSomeValues(["a", "b", "c", "--", "d"], 2) == ["a", "b"]);
}

int defaultArgPositionalAction(string[] args, string id, NArgs nArgs, ParseResult result) {
    assert(args.length > 0);
    assert(detectArgKind(args[0]) == ArgKind.someValue);

    // dfmt off
    return nArgs.match!(
        (NArgsOption n) {
            with (NArgsOption) final switch(n) {
            case one, zeroOrOne:
                result.args[id] = args[0];
                return 1;
            case moreThanEqualZero, moreThanEqualOne:
                assert(id in result.args);
                auto picked = pickSomeValues(args);
                result.args[id] ~= picked.map!(p => Variant(p)).array();
                return picked.length.to!int;
            }
        },
        (uint n) {
            enforce!ArgumentException(n != 0, "nArgs should be more than 0 for positional argument.");
            assert(id in result.args);
            int capacity = n - result.args[id].as!(string[]).length.to!int;
            assert(capacity > 0);
            auto picked = pickSomeValues(args, capacity);
            result.args[id] ~= picked.map!(p => Variant(p)).array();
            return picked.length.to!int;
        }
    );
    // dfmt on
}

bool argPositionalIsFilled(string id, NArgs nArgs, ParseResult result) {
    if (id !in result) {
        return false;
    }
    // dfmt off
    return nArgs.match!(
        (NArgsOption n) {
            with (NArgsOption) final switch (n) {
            case one, zeroOrOne:
                return true;
            case moreThanEqualZero, moreThanEqualOne:
                return false;
            }
        },
        (uint n) {
            assert(n != 0);
            return n == result.args[id].as!(string[]).length.to!int;
        },
    );
    // dfmt on
}

@("defaultArgPositionalAction for NArgsOption.one, zeroOrOne")
unittest {
    foreach (txt; [".", "?"]) {
        auto nArgs = fromText(txt);
        auto id = "id";
        auto result = new ParseResult();

        auto consume = defaultArgPositionalAction(["ABC", "DEF"], id, nArgs, result);
        assert(consume == 1, text(txt, " -> ", consume));
        assert(id in result && result[id] == "ABC", text(txt, " -> ", result));
    }
}

@("defaultArgPositionalAction for NArgsOption.moreThanEqual***")
unittest {
    struct TestCase {
        string[] args;
        int consume;
        string[] result;
    }

    auto id = "id";

    foreach (c; [
            TestCase(["ABC"], 1, ["ABC"]),
            TestCase(["ABC", "DEF", "-f", "GHI"], 2, ["ABC", "DEF"]),
            TestCase(["ABC", "DEF", "--", "GHI"], 2, ["ABC", "DEF"]),
        ]) {
        foreach (txt; ["*", "+"]) {
            auto nArgs = fromText(txt);
            auto result = new ParseResult();

            parseResultInitialize(id, nArgs, result);
            auto consume = defaultArgPositionalAction(c.args, id, nArgs, result);
            assert(consume == c.consume, text(txt, " : ", consume, " <-> ", c));
            assert(id in result && result[id].as!(string[]) == c.result, text(txt, " : ", result, " <-> ", c));
        }
    }

    // Case for append
    foreach (txt; ["*", "+"]) {
        auto nArgs = fromText(txt);
        auto result = new ParseResult();

        parseResultInitialize(id, nArgs, result);
        assert(defaultArgPositionalAction(["ABC", "DEF", "-f", "GHI"], id, nArgs, result) == 2);
        assert(defaultArgPositionalAction(["GHI", "JKL"], id, nArgs, result) == 2);
        assert(id in result && result[id].as!(string[]) == [
                "ABC", "DEF", "GHI", "JKL"
            ], text("Case: ", txt, " -> ", result));

    }
}

@("defaultArgPositionalAction for numbers")
unittest {
    struct TestCase {
        int n;
        string[] args;
        int consume;
        string[] result;
    }

    auto id = "id";

    foreach (c; [
            // 0 is not allowed
            TestCase(1, ["ABC", "DEF"], 1, ["ABC"]),
            TestCase(3, ["ABC", "DEF"], 2, ["ABC", "DEF"]),
            TestCase(3, ["ABC", "DEF", "GHI", "JKL"], 3, ["ABC", "DEF", "GHI"]),
            TestCase(3, ["ABC", "DEF", "--", "GHI", "JKL"], 2, ["ABC", "DEF"]),
        ]) {
        auto nArgs = fromText(c.n);
        auto result = new ParseResult();

        parseResultInitialize(id, nArgs, result);
        auto consume = defaultArgPositionalAction(c.args, id, nArgs, result);

        assert(consume == c.consume, text(consume, " <-> ", c));
        assert(id in result && result[id].as!(string[]) == c.result, text(result, " <-> ", c));
    }

    // Case for splitting by flag
    {
        auto nArgs = fromText(3);
        auto result = new ParseResult();
        parseResultInitialize(id, nArgs, result);
        assert(defaultArgPositionalAction(["ABC", "DEF", "-f", "FOO"], id, nArgs, result) == 2);
        assert(defaultArgPositionalAction(["GHI", "JKL"], id, nArgs, result) == 1);
        assert(id in result && result[id].as!(string[]) == ["ABC", "DEF", "GHI"], text(result));
    }
}

int defaultArgOptionalAction(string[] args, string id, NArgs nArgs, ParseResult result) {
    assert(args.length > 0);
    assert(detectArgKind(args[0]) == ArgKind.optShort || detectArgKind(args[0]) == ArgKind.optLong);

    auto keyValue = parseOption(args[0]);

    bool isNotNull(string str) {
        return str !is null && str != "";
    }

    // --key=VALUE style
    if (keyValue.length == 2) {
        // dfmt off
        nArgs.match!(
            (NArgsOption n) {
                with (NArgsOption) final switch (n) {
                case one:
                    enforce!ArgumentException(isNotNull(keyValue[1]), text("Need a value for ", keyValue[0]));
                    result.args[id] = keyValue[1];
                    break;
                case zeroOrOne:
                    if (isNotNull(keyValue[1])) {
                        result.args[id] = keyValue[1];
                    }
                    break;
                case moreThanEqualZero, moreThanEqualOne:
                    assert(id in result.args);
                    if (isNotNull(keyValue[1])) {
                        result.args[id] ~= [Variant(keyValue[1])];
                    }
                    break;
                }
            },
            (uint n) {
                if (n == 0) {
                    enforce!ArgumentException(isNotNull(keyValue[1]), text("Need a value for ", keyValue[0]));
                    result.args[id] = keyValue[1].to!bool;
                }else{
                    assert(id in result.args);
                    if (isNotNull(keyValue[1])) {
                        result.args[id] ~= [Variant(keyValue[1])];
                    }
                }
            }
        );
        // dfmt on
        return 1;
    }
    else {
        // dfmt off
        return nArgs.match!(
            (NArgsOption n) {
                with (NArgsOption) final switch (n) {
                case one:
                    enforce!ArgumentException(args.length > 1 && detectArgKind(args[1]) == ArgKind.someValue,
                        text("Need a value for ", keyValue[0]));
                    result.args[id] = args[1];
                    return 2;
                case zeroOrOne:
                    if(args.length > 1 && detectArgKind(args[1]) == ArgKind.someValue){
                        result.args[id] = args[1];
                        return 2;
                    }
                    else {
                        return 1;
                    }
                case moreThanEqualZero, moreThanEqualOne:
                    assert(id in result.args);
                    auto picked = pickSomeValues(args[1..$]);
                    result.args[id] ~= picked.map!(p => Variant(p)).array();
                    return picked.length.to!int + 1;
                }
            },
            (uint n) {
                if (n == 0) {
                    result.args[id] = true;
                    return 1;
                } else {
                    assert(id in result.args);
                    auto capacity = n - result.args[id].as!(string[]).length.to!int;
                    auto picked = pickSomeValues(args[1..$], capacity);
                    result.args[id] ~= picked.map!(p => Variant(p)).array();
                    return picked.length.to!int + 1;
                }
            },
        );
        // dfmt on
    }
}

unittest {
    struct TestCase {
        string[] args;
        int consume;
        string result;
    }

    auto nArgs = fromText(".");
    auto id = "id";

    foreach (c; [
            TestCase(["-o", "ABC"], 2, "ABC"),
            TestCase(["-o=ABC"], 1, "ABC"),
            TestCase(["-o", "ABC", "DEF"], 2, "ABC"),
        ]) {
        auto result = new ParseResult();
        auto consume = defaultArgOptionalAction(c.args, id, nArgs, result);
        assert(consume == c.consume, text(consume, " <-> ", c));
        assert(id in result && result[id] == c.result);
    }

    // Case for null call
    foreach (args; [
            ["-o"],
            ["-o", "-f"],
            ["-o=", "ABC"],
        ]) {
        auto result = new ParseResult();
        assertThrown!ArgumentException(defaultArgOptionalAction(args, id, nArgs, result), text("Case: ", args));
    }
}

unittest {
    struct TestCase {
        string[] args;
        int consume;
        string result;
    }

    auto nArgs = fromText("?");
    auto id = "id";

    foreach (c; [
            TestCase(["-o", "ABC"], 2, "ABC"),
            TestCase(["-o=ABC"], 1, "ABC"),
            TestCase(["-o", "ABC", "DEF"], 2, "ABC"),
        ]) {
        auto result = new ParseResult();
        auto consume = defaultArgOptionalAction(c.args, id, nArgs, result);
        assert(consume == c.consume, text(consume, " <-> ", c));
        assert(id in result && result[id] == c.result);
    }

    // Case fo null call
    foreach (args; [
            ["-o"],
            ["-o", "-f"],
            ["-o=", "ABC"],
        ]) {
        auto result = new ParseResult();
        auto consume = defaultArgOptionalAction(args, id, nArgs, result);
        assert(consume == 1, text("Case: ", args, " -> ", consume));
        assert(id !in result);
    }
}

unittest {
    struct TestCase {
        string[] args;
        int consume;
        string[] result;
    }

    auto id = "id";

    foreach (c; [
            TestCase(["-o"], 1, []),
            TestCase(["-o=", "ABC"], 1, []),
            TestCase(["-o", "ABC", "-f"], 2, ["ABC"]),
            TestCase(["-o", "ABC", "--", "DEF"], 2, ["ABC"]),
            TestCase(["-o=ABC", "DEF"], 1, ["ABC"]),
            TestCase(["-o", "ABC", "DEF"], 3, ["ABC", "DEF"]),
        ]) {
        foreach (txt; ["*", "+"]) {
            auto nArgs = fromText(txt);
            auto result = new ParseResult();

            parseResultInitialize(id, nArgs, result);
            auto consume = defaultArgOptionalAction(c.args, id, nArgs, result);
            assert(consume == c.consume, text("Case: ", txt, " -> ", consume, " <-> ", c));
            assert(id in result && result.args[id].as!(string[]) == c.result, text("Case: ", txt, " -> ", result));
        }
    }

    // Case for append
    foreach (txt; ["*", "+"]) {
        auto nArgs = fromText(txt);
        auto result = new ParseResult();

        parseResultInitialize(id, nArgs, result);

        assert(defaultArgOptionalAction(["-o", "ABC", "DEF", "-f", "GHI"], id, nArgs, result) == 3);
        assert(defaultArgOptionalAction(["-o", "GHI", "JKL"], id, nArgs, result) == 3);
        assert(id in result && result[id].as!(string[]) == [
                "ABC", "DEF", "GHI", "JKL"
            ], text("Case: ", txt, " -> ", result));
    }
}

unittest {
    struct TestCase {
        string[] args;
        bool result;
    }

    auto id = "id";
    auto nArgs = fromText(0);
    foreach (c; [
            TestCase(["-o"], true),
            TestCase(["-o=true"], true),
            TestCase(["-o=false"], false),
        ]) {
        auto result = new ParseResult();
        auto consume = defaultArgOptionalAction(c.args, id, nArgs, result);
        assert(consume == 1, text("Case: ", c, " -> ", consume));
        assert(id in result && result[id].as!bool == c.result);
    }

    // Case for null call
    {
        auto result = new ParseResult();
        assertThrown!ArgumentException(defaultArgOptionalAction(["-o=", "-f"], id, nArgs, result));
    }
}

unittest {
    struct TestCase {
        int n;
        string[] args;
        int consume;
        string[] result;
    }

    auto id = "id";

    foreach (c; [
            // dfmt off
            TestCase(1, ["-o","ABC", "DEF"], 2, ["ABC"]),
            TestCase(3, ["-o","ABC", "DEF"], 3, ["ABC", "DEF"]),
            TestCase(3, ["-o","ABC", "DEF", "GHI", "JKL"], 4, ["ABC", "DEF", "GHI"]),
            TestCase(3, ["-o","ABC", "DEF", "--", "GHI", "JKL"], 3, ["ABC", "DEF"]),
            TestCase(3, ["-o=ABC", "DEF"], 1, ["ABC"]),
            TestCase(3, ["-o=", "DEF"], 1, []),
            // dfmt on
        ]) {
        auto nArgs = fromText(c.n);
        auto result = new ParseResult();

        parseResultInitialize(id, nArgs, result);
        auto consume = defaultArgOptionalAction(c.args, id, nArgs, result);

        assert(consume == c.consume, text(consume, " <-> ", c));
        assert(id in result && result[id].as!(string[]) == c.result, text(result, " <-> ", c));
    }

    // Case for splitting by flag
    {
        auto nArgs = fromText(3);
        auto result = new ParseResult();
        parseResultInitialize(id, nArgs, result);
        assert(defaultArgOptionalAction(["-o", "ABC", "DEF", "-f", "FOO"], id, nArgs, result) == 3);
        assert(defaultArgOptionalAction(["-o", "GHI", "JKL"], id, nArgs, result) == 2);
        assert(id in result && result[id].as!(string[]) == ["ABC", "DEF", "GHI"], text(result));
    }
}

bool matchOption(string arg, ArgOptional optional) {
    auto opt = parseOption(arg);
    return optional.optShort == opt[0] || optional.optLong == opt[0];
}

enum ArgKind {
    someValue,
    optShort,
    optLong,
    seperator,
}

ArgKind detectArgKind(string arg) {
    import std.string;
    import std.regex;

    if (arg == "--") {
        return ArgKind.seperator;
    }
    if (isNumeric(arg)) {
        return ArgKind.someValue;
    }
    else {
        auto optShortPattern = regex(r"^-(\w)+(=.*)?$");
        if (matchFirst(arg, optShortPattern)) {
            return ArgKind.optShort;
        }
        auto optLongPattern = regex(r"^--\w[\w-_]*(=.*)?$");
        if (matchFirst(arg, optLongPattern)) {
            return ArgKind.optLong;
        }
        return ArgKind.someValue;
    }
}

unittest {
    with (ArgKind) {
        foreach (a; ["abc", "123", "-123"]) {
            assert(detectArgKind(a) == someValue, a);
        }
        foreach (a; ["-a", "-a=ABC", "-abc", "-abc=ABC", "-a=-1"]) {
            assert(detectArgKind(a) == optShort, a);
        }
        foreach (a; [
                "--a", "--abc", "--abc-def", "--abc_def", "--1", "--a=ABC",
                "--abc=ABC", "--abc-def=-1", "--abc_def=-1"
            ]) {
            assert(detectArgKind(a) == optLong, a);
        }
    }
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
