# Nagi - A Collection of D libraries

| Package                          | Description                          |
| -------------------------------- | ------------------------------------ |
| [nagi:argparse](#nagiargparse)   | Provides argument parser             |
| [nagi:console](#nagiconsole)     | Provides console colorizer functions |
| [nagi:logging](#nagilogging)     | Provides Logger implementations      |
| [nagi:tabletool](#nagitabletool) | Provides table making functions      |

## nagi:argparse

Provides argument parser utilities. It supports the following functionalities.

- Required and non-required positional arguments and optional arguments
- Flag which has no following argument, typical option which has one following argument, array option which can be specified multiple times
- Auto help generation
- Sub parser (also sub-sub parser is supported)

*Basic usage*

```d name=argparse_example_1
import nagi.argparse;
import std.stdio;

// Sample command line argument
auto args = ["prog", "--help"];

ArgumentParser parser = Command()
    .help("Sample command line")
    .arg(Arg("name")
            .required()
            .help("Input your name"))
    .arg(Arg("flag")
            .optShort()
            .optLong()
            .nArgs(NArgs.zero)
            .help("A flag"))
    .arg(Arg("config")
            .optShort()
            .optLong()
            .help("Input a config"))
    .arg(Arg("numbers")
            .optShort('n')
            .optLong("num")
            .nArgs(NArgs.any)
            .help("Input numbers"))
    .build();

ParseResult ret = parser.parse(args);
if (ret is null) {
    // Help wanted.
    return;
}
/*
usage: prog [-h] [OPTION] <NAME> 

Sample command line

Required positional argument
============================
  <NAME>            Input your name

Non-required optional argument
==============================
  -f, --flag        A flag
  -c, --config <CONFIG>
                    Input a config
  -n, --num <NUMBERS...>
                    Input numbers
  -h, --help        Display this message.
*/

// Usage
// Parsed data can be accessed by using id which is set via Arg("<key>").
writeln("name is ", ret["name"].as!string);

// true if "--flag" is specified. false if "--flag" is not specified.
// "flag" 
writeln(ret["flag"].as!bool);

// "config" is not in the result. Which means "--config" option is not specified
if (auto config = "config" in ret) {
    writeln("config is ", config.as!string);
}

// "numbers" is array. [] if no "--num" is specified.
writeln("numbers is ", ret["numbers"].as!(int[]));
```

Another ArgumentParser can be set to the parent parser as sub parser. In that case, any positional argument is not allowed to prevent conflicting positional arguments and sub commands.

```d name=argparse_example_2
import nagi.argparse;
import std.stdio;
import std.functional : bind;

// Sample command line argument
auto args = ["prog", "--help"];

auto parser = Command()
    .subCommand(Command("add")
            .shortDescription("Add two value")
            .arg(Arg("a").required())
            .arg(Arg("b").required())
            .build()
    )
    .subCommand(Command("sub")
            .shortDescription("Subtract two value")
            .arg(Arg("a").required())
            .arg(Arg("b").required())
            .build()
    )
    .subCommand(Command("nest")
            .shortDescription("Call nested command")
            .subCommand(Command("nested")
                .arg(Arg("a").required())
                .build()
            )
            .arg(Arg("config").optShort())
            .build()
    )
    .build();

ParseResult ret = parser.parse(args);
if (ret is null) {
    // Help wanted.
    return;
}

// Usage example
ret.subCommand.bind!((subCmd, subRet) {
    switch (subCmd) {
    case "add":
        writeln("a + b = ", subRet["a"].as!double + subRet["b"].as!double);
        break;
    case "sub":
        writeln("a - b = ", subRet["a"].as!double - subRet["b"].as!double);
        break;
    case "nest":
        auto config = "config" in subRet;
        subRet.subCommand.bind!((subSubCmd, subSubRet) {
            switch (subSubCmd) {
            case "nested":
                writeln(subSubRet["a"].as!string, " with ", config); // config is pointer
                break;
            default:
                assert(false);
            }
        });
        break;
    default:
        assert(false);
    }
});
```


## nagi:console

Provides console colorizer functions with the following features.

- Support Posix(Linux, FreeBSD, OSX, Solaris, etc.) ANSI color (foreground/background color, glyphs and 256 colors)
- Stateless colorizing (You don't need to call reset after setting color)
- Build your original code combination (e.g. Red foreground, yellow background, bold and underline)

See [ANSI escape code#Colors](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) for more details about ANSI colors.

```d name=console_example
// Example
import std : format, writeln;
import nagi.console;

writeln("Hello Red World".red); // display in red
writeln("Hello Bold Red World".bold.red); // display in bold red
writeln(format("Hello %s World".bold, "RED".red)); // display in bold, only RED is red
writeln("Hello World".foreground256(100)); // display in 256 colors ID 100
// Build your original color code combination
// Of course it works by calling `"...".bold.underline.red`, but this may be useful if you want to
// reduce string length or count of re-creating string object (each colorize functions create new
// string object).
enum myOriginal = build(Code.bold, Code.underline, Code.foregroundRed);
writeln(myOriginal, "Hello World", reset("")); // Need to reset manually in this case
```

## nagi:logging

Provides some Logger implementation based on `std.logger`. The following `Logger` is defined.

- `FormatLogger` : Another file logger whose log message format can be modified by associating delegate.
- `EnvLogger` : A file logger whose `LogLevel` and colorization can be switched via environment variables `D_LOG` and `D_LOG_COLOR`.
- `TeeLogger` : A multi logger implementation the message is sent to both stdout and file.
    - `FormatTeeLogger` : Internal logger is `FormatLogger`
    - `EnvTeeLogger` : Internal logger is `EnvLogger`

```d name=logging_example_1
// Example
import nagi.logging;
import std.logger;
import std.stdio : stdout;

sharedLog = cast(shared(Logger)) new FormatLogger(stdout);

info("This is info");
error("This is error");
/* Output:
2022-12-18T10:45:36.545 info app.d:8: This is info
2022-12-18T10:45:36.546 error app.d:9: This is error
*/

sharedLog = cast(shared(Logger)) new FormatLogger(stdout).setFormatter((ref Record record) => record.msg);
 
info("This is info");
error("This is error");
/* Output:
This is info
This is error
*/
```

```d disabled name=logging_example
#!/usr/bin/env dub
/* dub.sdl:
    name "example"
    dependency "nagi:console"
*/
// logging_example.d
import nagi.logging;
import std.logger;
import std.stdio : stdout;

void main() {
    sharedLog = cast(shared(Logger)) new EnvLogger(stdout);

    info("This is info");
    error("This is error");
}

/* > ./logging_example.d
2022-12-18T10:51:26.062 info app.d:8: This is info
2022-12-18T10:51:26.062 error app.d:9: This is error
*/
/* > D_LOG=error ./logging_example.d
2022-12-18T10:52:00.262 error app.d:9: This is error
*/
```

## nagi:tabletool

Provides table making functions. The notable feature is the compatibility with east-asian characters. `tabulate` function calculates display width in the console and inserts spaces. As the result, the readable table will be shown.

- Compatible with east-asian charactors (Thanks to [`east_asian_width`](https://code.dlang.org/packages/east_asian_width))
- Generate a table from 2D array of data (Accepts all types which can be converted to string)
- Generate a table from 1D array of struct (Can override display name by UDA `@DisplayName("<name>")`)
- Generate a table from 1D array of associated array (Accepts all types which can be converted to string as the key/value)
- Configure the table appearance

```d name=table_example
// Example
// Note that the layout may be broken due to your browser/editor's font.
import std.stdio;
import nagi.tabletool;

const data = [
    ["D-man", "Programming Language"],
    ["D言語くん", "プログラミング言語"],
];
const header = ["マスコットキャラクタ", "about"];
writeln(tabulate(data, header));
/* Output:
 マスコットキャラクタ          about
---------------------- ----------------------
        D-man           Programming Language
      D言語くん          プログラミング言語
*/

// Also works with struct
struct Data {
    @DisplayName("マスコットキャラクタ")
    string name;
    string about;
}

const structData = [
    Data("D-man", "Programming Language"),
    Data("D言語くん", "プログラミング言語"),
];
writeln(tabulate(structData));
/* Output: ditto */

writeln(tabulate(structData, Config(Style.grid, Align.center, true)));
/* Output:
┌──────────────────────┬──────────────────────┐
│ マスコットキャラクタ │        about         │
├──────────────────────┼──────────────────────┤
│        D-man         │ Programming Language │
├──────────────────────┼──────────────────────┤
│      D言語くん       │  プログラミング言語  │
└──────────────────────┴──────────────────────┘
*/
```

