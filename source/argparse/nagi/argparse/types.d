module nagi.argparse.types;

import std.variant;
import std.typecons;
import std.conv;
import std.sumtype;
import std.exception;
import std.algorithm;
import std.array;

struct ArgValue {
    Variant value;
    alias value this;

    this(T)(T value) if (isArray!T && !isSomeString!T) {
        this.value = value.map!(v => Variant(v)).array();
    }

    this(T)(T value) if (!isArray!T || isSomeString!T) {
        this.value = value;
    }

    auto opAssign(T)(T value) if (isArray!T && !isSomeString!T) {
        this.value = value.map!(v => Variant(v)).array();
        return this;
    }

    auto opAssign(T)(T value) if (!isArray!T || isSomeString!T) {
        this.value = value;
        return this;
    }

    string toString() const @trusted {
        return (cast(Variant*)&value).toString();
    }
}

class ParseResult {
    ArgValue[string] args;
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

enum NArgsOption {
    one = ".",
    zeroOrOne = "?",
    moreThanEqualZero = "*",
    moreThanEqualOne = "+",
}

alias NArgs = SumType!(NArgsOption, uint);

import std.traits;

NArgs fromText(T)(T txt) if (isIntegral!T || is(T : string)) {

    static if (isIntegral!T) {
        assert(txt >= 0, text("nargs should be greater than equal 0"));
        NArgs a = txt;
        return a;
    }
    else static if (is(T : string)) {
        foreach (mem; EnumMembers!NArgsOption) {
            if (mem == txt) {
                NArgs a = mem;
                return a;
            }
        }
        assert(false, text("Unknown nargs identifier: ", txt));
    }
}

unittest {
    assert(NArgs.init == NArgs(NArgsOption.one));

    assert(fromText(0) == NArgs(0));
    assert(fromText(1) == NArgs(1));
    assert(fromText(".") == NArgs(NArgsOption.one));
    assert(fromText("?") == NArgs(NArgsOption.zeroOrOne));
    assert(fromText("*") == NArgs(NArgsOption.moreThanEqualZero));
    assert(fromText("+") == NArgs(NArgsOption.moreThanEqualOne));
}

struct ArgPositional {
    string id;
    string helpText;
    bool isRequired;
    NArgs nArgs;
    ActionFunc action;
}

struct ArgOptional {
    string id;
    string helpText;
    string optShort;
    string optLong;
    bool isRequired;
    NArgs nArgs;
    ActionFunc action;
}

struct Counter(T) {
    T data;
    int count = 0;
    alias data this;

    this(T data) {
        this.data = data;
    }
}

Counter!(T)[] counted(T)(T[] t) {
    import std.algorithm : map;
    import std.array : array;

    return t.map!(u => Counter!T(u)).array();
}

alias ActionFunc = int function(string[] args, string id, NArgs nargs, ParseResult result);

class ArgumentException : Exception {
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}
