module nagi.argparse.utils;

import std.variant;

/** 
 * Returns the vaalue stored in the Variant object, explicitly converted to the requested type T.
 * If T is a string type, the value is formatted as a string. If the Variant object is a string, 
 * a parse of the string to type T is attempted. If the variant object is an array of string, and
 * T is an array type, parses of the strings to type T are attempted. If the variant object is an
 * array of Variant, `as` operation is attempted for each Variant object.
 * 
 * Params:
 *   v = a Variant
 * Returns: T object
 */
T as(T)(Variant v) {
    import std.conv;
    import std.exception;
    import std.traits;
    import std.array;
    import std.algorithm;
    import std.range;

    static if (isNumeric!T || isBoolean!T) {
        if (v.convertsTo!real) {
            return to!T(v.get!real);
        }
        else if (v.convertsTo!(const(char[]))) {
            return to!T(v.get!(const(char)[]));
        }
        else if (v.convertsTo!(immutable(char)[])) {
            return to!T(v.get!(const(char)[]));
        }
        else {
            enforce!ConvException(false, text("Type '", v.type(), "' does not convert to ",
                    typeid(T)));
            assert(0);
        }
    }
    else static if (is(T : Object)) {
        return to!(T)(v.get!(Object));
    }
    else static if (isSomeString!T) {
        return to!T(v.toString());
    }
    else static if (isArray!T) {
        if (v.convertsTo!T) {
            return to!T(v.get!T);
        }
        else if (v.convertsTo!(const(char)[][])) {
            return to!T(v.get!(const(char)[][]));
        }
        else if (v.convertsTo!(immutable(char)[][])) {
            return to!T(v.get!(immutable(char)[][]));
        }
        else if (v.convertsTo!(Variant[])) {
            alias E = ElementEncodingType!T;
            return v.get!(Variant[])
                .map!(e => as!E(e))
                .array();
        }
        else {
            enforce!ConvException(false, text("Type '", v.type(), "' does not convert to ",
                    typeid(T)));
            assert(0);
        }
    }
    else {
        static assert(false, text("unsuported type for as: ", typeid(T)));
    }
}

unittest {
    import std.exception;
    import std.conv;

    assert(as!bool(Variant("true")) == true);
    assert(as!bool(Variant("false")) == false);
    assert(as!int(Variant(123)) == 123);
    assert(as!int(Variant("123")) == 123);
    assert(as!string(Variant(123)) == "123");
    assert(as!string(Variant([123, 456])) == "[123, 456]");
    assert(as!(int[])(Variant([123, 456])) == [123, 456]);
    assert(as!(int[])(Variant(["123", "456"])) == [123, 456]);
    assert(as!(int[])(Variant([Variant("123"), Variant("456")])) == [123, 456]);
    assert(as!(string[])(Variant([Variant(123), Variant(456)])) == [
            "123", "456"
        ]);

    assertThrown!ConvException(as!(string[])(Variant([123, 456])));
}
