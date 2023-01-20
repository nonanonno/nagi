module nagi.argparse.builder;

import nagi.argparse.parser;
import nagi.argparse.types;
import nagi.argparse.action;

import std.algorithm;
import std.array;
import std.traits;
import std.typecons;

struct Arg {
    this(string id) {
        this.id_ = id;
    }

    Arg help(string helpText) {
        this.helpText_ = helpText;
        return this;
    }

    Arg optShort(char opt) {
        this.optShort_ = "-" ~ opt;
        return this;
    }

    Arg optShort() {
        this.optShort_ = "-"; // auto gen
        return this;
    }

    Arg optLong(string opt) {
        this.optLong_ = "--" ~ opt;
        return this;
    }

    Arg optLong() {
        this.optLong_ = "--"; // auto gen
        return this;
    }

    Arg required(bool isRequired = true) {
        this.isRequired_ = isRequired;
        return this;
    }

    Arg nArgs(T)(T txt) if (isIntegral!T || is(T : string)) {
        this.nArgs_ = fromText(txt);
        return this;
    }

    Arg defaultValue(T)(T value) {
        this.defaultValue_ = ArgValue(value);
        return this;
    }

    package string id_;
    package string helpText_ = null;
    package string optShort_ = null;
    package string optLong_ = null;
    package bool isRequired_;
    package NArgs nArgs_ = NArgs.init;
    package ArgValue defaultValue_;

    package bool isOptional() const @nogc pure @safe {
        return this.optShort_.length > 0 || this.optLong_.length > 0;
    }

    package string genShort() const {
        return optShort_ == "-" ? ("-" ~ id_[0]) : optShort_;
    }

    package string genLong() const {
        return optLong_ == "--" ? ("--" ~ id_) : optLong_;
    }
}

struct Command {
    this(string id) {
        this.id_ = id;
    }

    Command help(string helpText) {
        this.helpText_ = helpText;
        return this;
    }

    Command helpOption(bool generateHelpOption) {
        this.generateHelpOption_ = generateHelpOption;
        return this;
    }

    Command shortDescription(string description) {
        this.shortDescription_ = description;
        return this;
    }

    Command arg(Arg a) {
        this.args_ ~= a;
        return this;
    }

    Command subCommand(ArgumentParser parser) {
        this.subParsers_ ~= parser;
        return this;
    }

    ArgumentParser build() {
        ArgOptional helpOption;
        if (this.generateHelpOption_) {
            helpOption = ArgOptional("help", "Display this message.", "-h", "--help", false,
                fromText(0), &defaultArgOptionalAction);
        }
        auto parser = new ArgumentParser(
            this.id_,
            this.helpText_,
            this.shortDescription_,
            generateArgPositionals(),
            generateArgOptionals(),
            helpOption,
            this.subParsers_,
        );

        parser.checkConfiguration();

        return parser;
    }

    package string id_;
    package string helpText_ = null;
    package string shortDescription_ = null;
    package bool generateHelpOption_ = true;
    package Arg[] args_;
    package ArgumentParser[] subParsers_;

    private ArgPositional[] generateArgPositionals() {
        auto args = this.args_.filter!(a => !a.isOptional());
        return args.map!(a => ArgPositional(
                a.id_,
                a.helpText_,
                a.isRequired_,
                a.nArgs_,
                &defaultArgPositionalAction,
                a.defaultValue_,
        )).array();
    }

    private ArgOptional[] generateArgOptionals() {
        auto args = this.args_.filter!(a => a.isOptional()).array();
        return args.map!(a => ArgOptional(
                a.id_,
                a.helpText_,
                a.genShort(),
                a.genLong(),
                a.isRequired_,
                a.nArgs_,
                &defaultArgOptionalAction,
                a.defaultValue_,
        )).array();
    }
}

unittest {
    import std.conv : text;

    ArgumentParser parser = Command("command")
        .help("Help for command.")
        .shortDescription("summary")
        .arg(Arg("name")
                .help("Help for name.")
                .required())
        .arg(Arg("num"))
        .arg(Arg("config")
                .optShort()
                .optLong()
                .help("Help for config.")
                .required())
        .arg(Arg("flag")
                .optShort()
                .help("Help for flag.")
                .nArgs(0))
        .arg(Arg("environment")
                .optLong("env")
                .help("Help for environment.")
                .nArgs("*"))
        .arg(Arg("foo").optLong())
        .arg(Arg("default")
                .defaultValue("ABC"))
        .arg(Arg("defaultOpt")
                .optShort()
                .defaultValue(123))
        .build();

    assert(parser.id_ == "command");
    assert(parser.helpText_ == "Help for command.");
    assert(parser.shortDescription_ == "summary");
    assert(parser.positionals_ == [
            ArgPositional("name", "Help for name.", true, fromText("."), &defaultArgPositionalAction),
            ArgPositional("num", null, false, fromText("."), &defaultArgPositionalAction),
            ArgPositional("default", null, false, fromText("."), &defaultArgPositionalAction, ArgValue(
                "ABC")),
        ], text(parser.positionals_));

    assert(parser.optionals_ == [
            ArgOptional("config", "Help for config.", "-c", "--config", true, fromText("."), &defaultArgOptionalAction),
            ArgOptional("flag", "Help for flag.", "-f", null, false, fromText(0), &defaultArgOptionalAction),
            ArgOptional("environment", "Help for environment.", null, "--env", false, fromText("*"),
                &defaultArgOptionalAction),
            ArgOptional("foo", null, null, "--foo", false, fromText("."), &defaultArgOptionalAction),
            ArgOptional("defaultOpt", null, "-d", null, false, fromText("."), &defaultArgOptionalAction, ArgValue(
                123)),
        ], text(parser.optionals_));
    assert(parser.helpOption_ == ArgOptional("help", "Display this message.", "-h", "--help", false,
            fromText(0), &defaultArgOptionalAction));

    assert(parser.subParsers_.length == 0);
}

unittest {
    ArgumentParser parser = Command("command")
        .subCommand(Command("sub1")
                .arg(Arg("foo"))
                .build())
        .subCommand(Command("sub2")
                .arg(Arg("bar")
                    .help(""))
                .build())
        .arg(Arg("baz")
                .optShort())
        .build();

    assert(parser.id_ == "command");
    assert(parser.positionals_.length == 0);
    assert(parser.optionals_.length == 1);
    assert(parser.subParsers_.length == 2);

    assert(parser.subParsers_[0].id_ == "sub1");
    assert(parser.subParsers_[0].positionals_.length == 1);
    assert(parser.subParsers_[0].positionals_[0].id == "foo");

    assert(parser.subParsers_[1].id_ == "sub2");
    assert(parser.subParsers_[1].positionals_.length == 1);
    assert(parser.subParsers_[1].positionals_[0].id == "bar");
}
