module nagi.argparse.types;

import std.variant;
import std.typecons;
import std.conv;
import std.sumtype;
import std.exception;
import std.algorithm;
import std.array;
import std.traits;

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

struct NArgs {
    alias config this;

    this(T)(T txt) {
        this = txt;
    }

    auto opAssign(T)(T n) if (isIntegral!T)
    in (n >= 0, text("`n` should be greater than equal 0")) {
        this.config = to!uint(n);
        return this;
    }

    auto opAssign(T)(T txt) if (isSomeString!T)
    in (canFind([EnumMembers!NArgsOption], txt), text("Unknown nArgs : ", txt)) {
        foreach (mem; EnumMembers!NArgsOption) {
            if (mem == txt) {
                this.config = mem;
                return;
            }
        }
        assert(0);
    }

    string toString() const @safe pure {
        return this.config.toString();
    }

    SumType!(NArgsOption, uint) config;
}

unittest {
    auto select(T)(NArgs args) {
        return args.match!((T a) => a, (_) => assert(0));
    }

    assert(select!NArgsOption(NArgs.init) == NArgsOption.one);
    assert(select!uint(NArgs(0)) == 0);
    assert(select!uint(NArgs(1)) == 1);
    assert(select!uint(NArgs(2)) == 2);
    assert(select!NArgsOption(NArgs(".")) == NArgsOption.one);
    assert(select!NArgsOption(NArgs("?")) == NArgsOption.zeroOrOne);
    assert(select!NArgsOption(NArgs("*")) == NArgsOption.moreThanEqualZero);
    assert(select!NArgsOption(NArgs("+")) == NArgsOption.moreThanEqualOne);
}

package struct ArgPositional {
    string id;
    string helpText;
    bool isRequired;
    NArgs nArgs;
    ActionFunc action;
    ArgValue defaultValue;
}

package struct ArgOptional {
    string id;
    string helpText;
    string optShort;
    string optLong;
    bool isRequired;
    NArgs nArgs;
    ActionFunc action;
    ArgValue defaultValue;
}

package struct Counter(T) {
    T data;
    int count = 0;
    alias data this;

    this(T data) {
        this.data = data;
    }
}

package Counter!(T)[] counted(T)(T[] t) {
    import std.algorithm : map;
    import std.array : array;

    return t.map!(u => Counter!T(u)).array();
}

alias ActionFunc = int function(string[] args, string id, NArgs nargs, ParseResult result);

class ArgumentException : Exception {
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}

bool isEmpty(T)(in T arg) {
    return arg.id is null;
}
