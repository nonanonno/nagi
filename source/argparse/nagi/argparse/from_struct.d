module nagi.argparse.from_struct;

import nagi.argparse.builder;
import nagi.argparse.types;
import nagi.argparse.parser;
import nagi.argparse.utils;

import std.traits;
import std.stdio;
import std.typecons;
import std.sumtype;
import std.conv;

private ArgumentParser[] getSubParsers(ST)() if (isSumType!ST) {
    ArgumentParser[] parsers;
    static foreach (T; ST.Types) {
        parsers ~= build!T;
    }
    return parsers;
}

private Command getCommand(T)() {
    Command cmd;
    static if (hasUDA!(T, Command)) {
        cmd = getUDAs!(T, Command)[0];
        if (cmd.id_ is null) {
            cmd.id_ = T.stringof;
        }
    }
    else {
        cmd = Command(T.stringof);
    }
    return cmd;
}

private Arg getArg(T, string mem)() {
    Arg arg;
    static if (hasUDA!(__traits(getMember, T, mem), Arg)) {
        arg = getUDAs!(__traits(getMember, T, mem), Arg)[0];
        if (arg.id_ is null) {
            arg.id_ = mem;
        }
    }
    else {
        arg = Arg(mem);
    }
    return getArgImpl!(typeof(__traits(getMember, T, mem)))(arg);
}

private Arg getArgImpl(T)(Arg arg) {
    static if (__traits(isSame, TemplateOf!T, Nullable)) {
        if (arg.isRequired_ == Ternary.unknown) {
            arg.isRequired_ = false;
        }
        return getArgImpl!(TemplateArgsOf!T)(arg);
    }
    else {
        if (arg.isRequired_ == Ternary.unknown) {
            arg.isRequired_ = true;
        }
        static if (isStaticArray!T && !isSomeString!T) {
            arg.nArgs_ = fromText(T.length);
        }
        else static if (isDynamicArray!T && !isSomeString!T) {
            arg.nArgs_ = fromText("*");
        }
        return arg;
    }
}

private Command command(T)() {
    Command cmd = getCommand!T;

    static foreach (mem; FieldNameTuple!T) {
        {
            static if (hasUDA!(__traits(getMember, T, mem), Hidden)) {
                // Do nothing
            }
            else {
                alias M = typeof(__traits(getMember, T, mem));
                static if (isSumType!(M)) {
                    cmd.subCommand(getSubParsers!(M));
                }
                else static if (hasUDA!(__traits(getMember, T, mem), Rest)) {
                    // Do nothing
                }
                else {
                    cmd.arg(getArg!(T, mem));
                }
            }
        }
    }
    return cmd;
}

enum Rest;
enum Hidden;

ArgumentParser build(T)() {
    return command!(T)().build();
}

T fillData(T)(ParseResult result) {
    T rslt;
    static foreach (mem; FieldNameTuple!T) {
        {
            alias M = typeof(__traits(getMember, T, mem));
            static if (hasUDA!(__traits(getMember, T, mem), Hidden)) {
                // Do nothing
            }
            else static if (isSumType!M) {
                __traits(getMember, rslt, mem) = fillDataSubParser!(M)(result.subCommand);
            }
            else static if (hasUDA!(__traits(getMember, T, mem), Rest)) {
                __traits(getMember, rslt, mem) = result.trail;
            }
            else {
                auto arg = getArg!(T, mem);
                if (auto r = arg.id_ in result) {
                    __traits(getMember, rslt, mem) = as!(typeof(__traits(getMember, rslt, mem)))(r);
                }
            }
        }
    }
    return rslt;
}

private ST fillDataSubParser(ST)(Tuple!(string, "name", ParseResult, "result") subResult)
        if (isSumType!ST) {
    static foreach (T; ST.Types) {
        if (getCommand!T.id_ == subResult.name) {
            return to!ST(fillData!(T)(subResult.result));
        }
    }
    assert(0);
}

Nullable!T parse(T)(string[] args) {
    auto parser = build!(T);
    auto parsed = parser.parse(args);

    if (!parsed) {
        return Nullable!T.init;
    }

    return fillData!T(parsed).nullable;
}
