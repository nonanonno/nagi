module nagi.argparse.types;

import std.variant;
import std.typecons;
import std.conv;

struct ArgValue {
    Variant value;
    alias value this;

    this(T)(T value) {
        this.value = value;
    }

    auto opAssign(T)(T value) {
        this.value = value;
        return this;
    }

    T as(T)() const {
        import std.traits;
        import std.conv : to, text;
        import std.exception;

        static if (isNumeric!T || isBoolean!T) {
            if (value.convertsTo!real) {
                return to!T(value.get!real);
            }
            else if (value.convertsTo!(const(char)[])) {
                return to!T(value.get!(const(char)[]));
            }
            else if (value.convertsTo!(immutable(char)[])) {
                return to!T(value.get!(immutable(char)[]));
            }
            else {
                enforce(false, text("Type ", value.type(), " does not convert to ", typeid(T)));
                assert(0);
            }
        }
        else static if (is(T : Object)) {
            return to!(T)(value.get!(Object));
        }
        else static if (isSomeString!(T)) {
            return to!(T)((cast(Variant*)&value).toString());
        }
        else static if (isArray!(T)) {
            if (value.convertsTo!(T)) {
                return to!T(value.get!(T));
            }
            else if (value.convertsTo!(const(char)[][])) {
                return to!T(value.get!(const(char)[][]));
            }
            else if (value.convertsTo!(immutable(char)[][])) {
                return to!T(value.get!(immutable(char)[][]));
            }
            else {
                enforce(false, text("Type ", value.type(), " does not convert to ", typeid(T)));
                assert(0);
            }
        }
        else {
            static assert(false, text("unsupported type for as: ", typeid(T)));
        }
    }

    string toString() const @trusted {
        return (cast(Variant*)&value).toString();
    }
}

@("ArgValue can hold many types of value and `as` function can get it with expected type")
unittest {
    assert(ArgValue("abc").as!string == "abc");
    assert(ArgValue("123").as!int == 123);
    assert(ArgValue(123).as!int == 123);
    assert(ArgValue(123).as!string == "123");

    assert(ArgValue("123.45").as!float == 123.45f);
    assert(ArgValue(123.45).as!double == 123.45);
    assert(ArgValue("true").as!bool == true);
    assert(ArgValue(true).as!bool == true);
    assert(ArgValue("false").as!bool == false);

    assert(ArgValue(["abc", "def"]).as!(string[]) == ["abc", "def"]);
    assert(ArgValue(["123", "456"]).as!(int[]) == [123, 456]);
    assert(ArgValue(["123.45", "456.78"]).as!(double[]) == [
            123.45, 456.78
        ]);
    assert(ArgValue([123, 456]).as!(int[]) == [123, 456]);
    assert(ArgValue([123.45, 456.78]).as!(double[]) == [123.45, 456.78]);
}

@("Invalid convertion raises an exception")
unittest {
    import std.exception;

    assertThrown(ArgValue("abc").as!int);
    assertThrown(ArgValue(["abc", "def"]).as!(int[]));
    assertThrown(ArgValue([123, 456]).as!(double[]));
    assertThrown(ArgValue([123, 456]).as!(string[]));
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

enum NArgs {
    zero,
    one,
    any,
}

struct ArgPositional {
    string id;
    string helpText;
    bool isRequired;
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

alias ActionFunc = int function(in string[] args, ref Counter!ArgOptional optional, ParseResult result);

class ArgumentException : Exception {
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}
