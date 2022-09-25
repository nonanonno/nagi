# Nagi - A Collection of D libraries

| Package                      | Description                          |
| ---------------------------- | ------------------------------------ |
| [nagi:console](#nagiconsole) | Provides console colorizer functions |

## nagi:console

Provides console colorizer functions with the following features.

- Support linux ANSI color (foreground/background color, glyphs and 256 colors)
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
