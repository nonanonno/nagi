module nagi.argparse.parser;

import std.variant;
import std.typecons;

class ArgumentParser {
    alias This = typeof(this);

    package this() {
    }

    package string name_;
    package string helpText_;
    package string shortDescription_;
    package ArgPositional[] positionals_;
    package ArgOptional[] optionals_;
    package ArgumentParser[] subParsers_;

}

class Argumentexception : Exception {
    import std.exception : basicExceptionCtors;

    mixin basicExceptionCtors;
}

class ParseResult {
    Variant[string] args;
    Tuple!(string, "name", ParseResult, "result") subCommand;

    alias args this;
}

enum NArgs {
    zero,
    one,
    any,
}

package struct ArgPositional {
    string name;
    string helpText;
    bool isRequied;
}

package struct ArgOptional {
    string name;
    string helpText;
    char optShort;
    string optLong;
    bool isRequired;
    NArgs nArgs;
}
