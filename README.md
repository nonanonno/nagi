# Nagi - A Collection of D libraries

| Package                          | Description                          |
| -------------------------------- | ------------------------------------ |
| [nagi:console](#nagiconsole)     | Provides console colorizer functions |
| [nagi:logging](#nagilogging)     | Provides Logger implementations      |
| [nagi:tabletool](#nagitabletool) | Provides table making functions      |

## nagi:console

Provides console colorizer functions with the following features.

- Support Posix(Linux, FreeBSD, OSX, Solaris, etc.) ANSI color (foreground/background color, glyphs and 256 colors)
- Stateless colorizing (You don't need to call reset after setting color)
- Build your original code combination (e.g. Red foreground, yellow background, bold and underline)

See [ANSI escape code#Colors](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) for more details about ANSI colors.

```d
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

```d
// Example
import nagi.logging;
import std.experimental.logger;
import std.stdio : stdout;

sharedLog = new FormatLogger(stdout);

info("This is info");
error("This is error");
/* Output:
2022-12-18T10:45:36.545 info app.d:8: This is info
2022-12-18T10:45:36.546 error app.d:9: This is error
*/

sharedLog = new FormatLogger(stdout).setFormatter((ref Record record) => record.msg);

info("This is info");
error("This is error");
/* Output:
This is info
This is error
*/
```

```d
// Example (app.d)
import nagi.logging;
import std.experimental.logger;
import std.stdio : stdout;

void main() {
    sharedLog = new FormatLogger(stdout);

    info("This is info");
    error("This is error");
}

/* > rdmd app.d
2022-12-18T10:51:26.062 info app.d:8: This is info
2022-12-18T10:51:26.062 error app.d:9: This is error
*/
/* > D_LOG=error rdmd app.d
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

```d
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

