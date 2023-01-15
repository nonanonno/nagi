module nagi.argparse.help_format;

import std.conv;
import std.string;
import std.array;
import std.algorithm;
import std.sumtype;

import nagi.argparse.types;
import nagi.argparse.parser;

string generateHelpItem(T)(in T item, int nameBoxWidth, int helpBoxWidth, int gapWidth) {
    auto name = sampleText(item);
    auto description = descriptionText(item);
    auto indent = replicate(" ", gapWidth + nameBoxWidth);
    auto first = leftJustify(text("  ", name), nameBoxWidth);
    // Add 2 for wrap function. Without it, wrap function wraps text even if the word width equals to width.
    if (first.length <= nameBoxWidth) {
        return wrap(description, nameBoxWidth + gapWidth + helpBoxWidth + 2, first ~ replicate(" ", gapWidth), indent);
    }
    else {
        return text(first, "\n", wrap(description, nameBoxWidth + gapWidth + helpBoxWidth + 2, indent, indent));
    }
}

@("Test for generateHelpItem")
unittest {
    assert(generateHelpItem(ArgPositional("name", "help"), 10, 60, 2)
            == "  [NAME]    help\n");
    assert(generateHelpItem(ArgPositional("12", "1234567890"), 6, 10, 2)
            == "  [12]  1234567890\n");
    assert(generateHelpItem(ArgPositional("12", "1234567890 1234567890"), 6, 10, 2)
            == "  [12]  1234567890\n        1234567890\n");
    assert(generateHelpItem(ArgPositional("123", "1234567890 1234567890"), 6, 10, 2)
            == "  [123]\n        1234567890\n        1234567890\n");
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, fromText(0)),
            24, 10, 2) == text(
            "  -o, --option            1234567890\n",
            "                          1234567890\n",
    ));
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, fromText(".")),
            24, 10, 2) == text(
            "  -o, --option <OPTION>   1234567890\n",
            "                          1234567890\n",
    ));
    assert(generateHelpItem(
            ArgOptional("option", "1234567890 1234567890", "-o", "--option", false, fromText("*")),
            24, 10, 2) == text(
            "  -o, --option <OPTION...>\n",
            "                          1234567890\n",
            "                          1234567890\n",
    ));
    auto parser = new ArgumentParser();
    parser.name_ = "command";
    parser.shortDescription_ = "short description";
    assert(generateHelpItem(parser, 10, 60, 2) == "  command   short description\n");
}

string generateHelpMessage(
    string commandName,
    string description,
    ArgPositional[] positionals,
    ArgumentParser[] subParsers,
    ArgOptional[] optionals,
    ArgOptional helpOption,
) {
    assert(positionals.length == 0 || subParsers.length == 0);
    enum nameBoxWidth = 18;
    enum helpBoxWidth = 60;
    enum gap = 2;
    string buffer;
    buffer ~= text("usage: ", commandName, " ");
    if (helpOption.id !is null) {
        auto helpFlag = helpOption.optShort ? helpOption.optShort : helpOption.optLong;
        buffer ~= text("[", helpFlag, "] ");
    }
    if (optionals.length > 0) {
        buffer ~= "[OPTION] ";
    }
    if (subParsers.length > 0) {
        buffer ~= format("{%-(%s,%)} ... ", subParsers.map!(p => p.name_));
    }
    if (positionals.length > 0) {
        buffer ~= format("%-(%s %) ", positionals.map!(p => sampleText(p)));
    }
    buffer ~= "\n";
    if (description) {
        buffer ~= "\n";
        buffer ~= wrap(description, nameBoxWidth + helpBoxWidth + gap);
    }

    void append(T)(T[] args, string title) {
        if (args) {
            buffer ~= text("\n",
                title, "\n",
                replicate("=", title.length), "\n"
            );
            args.each!((a) {
                buffer ~= generateHelpItem(a, nameBoxWidth, helpBoxWidth, gap);
            });
        }
    }

    append(subParsers, "Sub commands");
    append(positionals.filter!(a => a.isRequired).array(), "Required positional argument");
    append(positionals.filter!(a => !a.isRequired).array(), "Non-required positional argument");
    append(optionals.filter!(a => a.isRequired).array(), "Required optional argument");
    auto nonRequiredOptionals = optionals.filter!(a => !a.isRequired).array();
    if (helpOption.id) {
        nonRequiredOptionals ~= helpOption;
    }

    append(nonRequiredOptionals, "Non-required optional argument");

    return buffer;
}

@("help message for end point")
unittest {
    auto positionals = [
        ArgPositional("pos1", "Help message for pos1", true),
        ArgPositional("pos2", "Help message for pos2", false),
    ];
    auto optionals = [
        ArgOptional("o", "Help message for option 1", "-o", "--opt", false, fromText(0)),
        ArgOptional("p", "Help message for option 2", "-p", null, false, fromText(".")),
        ArgOptional("q", "Help message for option 3", null, "--qqq", false, fromText("*")),
    ];
    auto helpArg = ArgOptional("help", "Display this message", "-h", "--help", false, fromText(0));
    auto helpText = text(
        "This is a sample help message for testing. Since the message count is over 80, t",
        "he message will be wrapped.");

    auto expected = text("usage: prog [-h] [OPTION] <POS1> [POS2] \n",
        "\n",
        "This is a sample help message for testing. Since the message count is over 80,\n",
        "the message will be wrapped.\n",
        "\n",
        "Required positional argument\n",
        "============================\n",
        "  <POS1>            Help message for pos1\n",
        "\n",
        "Non-required positional argument\n",
        "================================\n",
        "  [POS2]            Help message for pos2\n",
        "\n",
        "Non-required optional argument\n",
        "==============================\n",
        "  -o, --opt         Help message for option 1\n",
        "  -p   <P>          Help message for option 2\n",
        "      --qqq <Q...>  Help message for option 3\n",
        "  -h, --help        Display this message\n",
    );

    assert(generateHelpMessage("prog", helpText, positionals, [], optionals, helpArg) == expected);

}

@("help message for sub parsers")
unittest {
    auto sub1 = new ArgumentParser();
    auto sub2 = new ArgumentParser();

    auto optionals = [
        ArgOptional("o", "", "-o", "--opt", false, fromText(0)),
    ];
    auto helpArg = ArgOptional("help", "Display this messages", "-h", "--help", false, fromText(0));

    sub1.name_ = "sub1";
    sub1.shortDescription_ = "Short description for sub1";
    sub2.name_ = "sub2";
    sub2.shortDescription_ = "Short description for sub2";

    auto helpText = text(
        "This is a sample help message for testing. Since the message count is over 80, t",
        "he message will be wrapped.");

    auto expected = text(
        "usage: prog [-h] [OPTION] {sub1,sub2} ... \n",
        "\n",
        "This is a sample help message for testing. Since the message count is over 80,\n",
        "the message will be wrapped.\n",
        "\n",
        "Sub commands\n",
        "============\n",
        "  sub1              Short description for sub1\n",
        "  sub2              Short description for sub2\n",
        "\n",
        "Non-required optional argument\n",
        "==============================\n",
        "  -o, --opt         \n",
        "  -h, --help        Display this messages\n",
    );
    assert(generateHelpMessage("prog", helpText, [], [sub1, sub2], optionals, helpArg) == expected);
}

string sampleText(in ArgPositional arg) {
    if (arg.isRequired) {
        return text("<", arg.id.toUpper(), ">");
    }
    else {
        return text("[", arg.id.toUpper(), "]");
    }
}

string sampleText(in ArgOptional arg) {
    auto displayName = () {
        auto state = (arg.optShort ? 0b10 : 0b00) | (arg.optLong ? 0b01 : 0b00);
        switch (state) {
        case 0b11:
            return text(arg.optShort, ", ", arg.optLong);
        case 0b10:
            return text(arg.optShort, "  ");
        case 0b01:
            return text("    ", arg.optLong);
        default:
            assert(false);
        }
    }();

    // dfmt off
    return arg.nArgs.match!(
        (NArgsOption n) {
            with (NArgsOption) final switch (n) {
            case one:
                return text(displayName, " <", arg.id.toUpper(), ">");
            case zeroOrOne:
                assert(0);
            case moreThanEqualZero:
                return text(displayName, " <", arg.id.toUpper(), "...>");
            case moreThanEqualOne:
                assert(0);
            }
        },
        (uint n) {
            switch (n) {
            case 0:
                return displayName;
            default:
                assert(0);
            }
        },
    );
    // dfmt on
}

string sampleText(in ArgumentParser arg) {
    return arg.name_;
}

string descriptionText(T)(in T arg) if (is(T == ArgPositional) || is(T == ArgOptional)) {
    return arg.helpText;
}

string descriptionText(T)(in T arg) if (is(T == ArgumentParser)) {
    return arg.shortDescription_;
}
