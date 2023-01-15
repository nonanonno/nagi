module nagi.argparse.builder;

import nagi.argparse.parser;
import nagi.argparse.types;
import nagi.argparse.action;

import std.algorithm;
import std.array;

struct Arg {
    this(string name) {
        this.name_ = name;
    }

    Arg help(string helpText) {
        this.helpText_ = helpText;
        return this;
    }

    Arg optShort(char opt) {
        this.optShort_ = opt;
        return this;
    }

    Arg optShort() {
        this.optShort_ = '-'; // auto gen
        return this;
    }

    Arg optLong(string opt) {
        this.optLong_ = opt;
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

    Arg nArgs(NArgs n) {
        this.nArgs_ = n;
        return this;
    }

    package string name_;
    package string helpText_ = null;
    package char optShort_ = '\0';
    package string optLong_ = null;
    package bool isRequired_ = false;
    package NArgs nArgs_ = NArgs.one;

    package bool isOptional() const @nogc pure @safe {
        return optShort_ != '\0' || optLong_ != null;
    }

    package string genShort() const {
        return optShort_ == '-' ? ("-" ~ name_[0]) : optShort_ != '\0' ? ("-" ~ optShort_) : null;
    }

    package string genLong() const {
        return optLong_ == "--" ? ("--" ~ name_) : optLong_ != null ? ("--" ~ optLong_) : null;
    }
}

struct Command {
    this(string name) {
        this.name_ = name;
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
        auto parser = new ArgumentParser();

        parser.name_ = this.name_;
        parser.helpText_ = this.helpText_;
        parser.shortDescription_ = this.shortDescription_;
        parser.positionals_ = generateArgPositionals();
        parser.optionals_ = generateArgOptionals(generateHelpOption_);

        if (this.generateHelpOption_) {
            parser.helpOption_ = ArgOptional(
                "help", "Display this message.", "-h", "--help", false, NArgs.zero, &defaultAction);
        }

        parser.subParsers_ = this.subParsers_;

        return parser;
    }

    package string name_;
    package string helpText_ = null;
    package string shortDescription_ = null;
    package bool generateHelpOption_ = true;
    package Arg[] args_;
    package ArgumentParser[] subParsers_;

    private ArgPositional[] generateArgPositionals() {
        auto args = this.args_.filter!(a => !a.isOptional());
        return args.map!(a => ArgPositional(
                a.name_,
                a.helpText_,
                a.isRequired_,
        )).array();
    }

    private ArgOptional[] generateArgOptionals(bool genHelp) {
        auto args = this.args_.filter!(a => a.isOptional()).array();
        return args.map!(a => ArgOptional(
                a.name_,
                a.helpText_,
                a.genShort(),
                a.genLong(),
                a.isRequired_,
                a.nArgs_,
                &defaultAction,
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
                .nArgs(NArgs.zero))
        .arg(Arg("environment")
                .optLong("env")
                .help("Help for environment.")
                .nArgs(NArgs.any))
        .arg(Arg("foo").optLong())
        .build();

    assert(parser.name_ == "command");
    assert(parser.helpText_ == "Help for command.");
    assert(parser.shortDescription_ == "summary");
    assert(parser.positionals_ == [
            ArgPositional("name", "Help for name.", true),
            ArgPositional("num", null, false),
        ], text(parser.positionals_));

    assert(parser.optionals_ == [
            ArgOptional("config", "Help for config.", "-c", "--config", true, NArgs.one, &defaultAction),
            ArgOptional("flag", "Help for flag.", "-f", null, false, NArgs.zero, &defaultAction),
            ArgOptional("environment", "Help for environment.", null, "--env", false, NArgs.any, &defaultAction),
            ArgOptional("foo", null, null, "--foo", false, NArgs.one, &defaultAction),
        ], text(parser.optionals_));
    assert(parser.helpOption_ == ArgOptional("help", "Display this message.", "-h", "--help", false, NArgs
            .zero, &defaultAction));

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

    assert(parser.name_ == "command");
    assert(parser.positionals_.length == 0);
    assert(parser.optionals_.length == 1);
    assert(parser.subParsers_.length == 2);

    assert(parser.subParsers_[0].name_ == "sub1");
    assert(parser.subParsers_[0].positionals_.length == 1);
    assert(parser.subParsers_[0].positionals_[0].id == "foo");

    assert(parser.subParsers_[1].name_ == "sub2");
    assert(parser.subParsers_[1].positionals_.length == 1);
    assert(parser.subParsers_[1].positionals_[0].id == "bar");
}
