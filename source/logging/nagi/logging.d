module nagi.logging;

import std.experimental.logger;
import std.process : environment;
import std.concurrency : Tid;
import std.datetime : SysTime;
import std.stdio : File;
import std.typecons : Flag;

import nagi.console;

/// Flag to swich colorization.
alias Colorize = Flag!"Colorize";

/// Record struct to be logged
struct Record {
    /// The filename the log function was called from
    string file;
    /// The line number the log function was called from
    int line;
    /// The name of the function the log function was called from
    string funcName;
    /// The pretty formatted name of the function the log function was called from
    string prettyFuncName;
    /// The name of the module the log message is coming from
    string moduleName;
    /// THe `LogLevel` associated with the log message
    LogLevel logLevel;
    /// Thread id of the log message
    Tid threadId;
    /// The time the message was logged
    SysTime timestamp;
    /// The message of the log message
    string msg;
}

/**
 * Another file logger whose formatter is configurable..
 * The log message is written to the associated file. If the file is already present,
 * new log messages will be appended at its end.
 */
class FormatLogger : Logger {
    import std.file : exists, mkdirRecurse;
    import std.path : dirName;
    import std.conv : text;

    /**
     * Construct a new logger associated with a file specified as the filename.
     * Params:
     *   fn = The filename
     *   lv = `LogLevel`
     *   createFileNameFolder = Create a directory of the file or not
     *   colorize = Colorize log message
     */
    this(
        const string fn,
        const LogLevel lv = LogLevel.all,
        CreateFolder createFileNameFolder = CreateFolder.yes,
        Colorize colorize = Colorize.yes,
    ) @safe {
        super(lv);

        this.filename = fn;

        if (createFileNameFolder) {
            auto d = dirName(this.filename);
            mkdirRecurse(d);
            assert(exists(d), text("The folder the EnvLogger should have",
                    " created in '", d, "' could not be created."));
        }

        this.file_.open(this.filename, "a");
        this.formatter_ = (ref Record record) @safe => defaultFormatter(record, colorize);
    }

    /**
     * Construct a new logger associated with the file.
     * Params:
     *   file = The file handle
     *   lv = `LogLevel``
     *   colorize = Colorize log message
     */
    this(File file, const LogLevel lv = LogLevel.all, Colorize colorize = Colorize.yes) @safe {
        super(lv);
        this.file_ = file;
        this.formatter_ = (ref Record record) @safe => defaultFormatter(record, colorize);
    }

    /// The file handle.
    @property File file() @safe {
        return this.file_;
    }

    /**
     * Set formatter delegate which consume Record and make a message.
     * Params:
     *   formatter = Formatter delegate
     */
    auto setFormatter(string delegate(ref Record) @safe formatter) {
        this.formatter_ = formatter;
        return this;
    }

    /// ditto
    override protected void writeLogMsg(ref LogEntry payload) @safe {
        import std.format : formattedWrite;

        auto lt = this.file_.lockingTextWriter();
        auto record = Record(
            payload.file,
            payload.line,
            payload.funcName,
            payload.prettyFuncName,
            payload.moduleName,
            payload.logLevel,
            payload.threadId,
            payload.timestamp,
            payload.msg,
        );
        formattedWrite(lt, "%s\n", this.formatter_(record));
        this.file_.flush();
    }

    protected File file_;
    protected string delegate(ref Record) @safe formatter_;
    protected string filename;

}

@("Check if the formatter is set")
unittest {
    import std.file : deleteme, remove;
    import std.string : startsWith;
    import std.process : environment;

    scope (exit) {
        environment.remove("D_LOG");
    }
    environment["D_LOG"] = "critical";

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto l = new FormatLogger(filename).setFormatter((ref Record record) @safe => record.msg);

    scope (exit) {
        remove(filename);
    }

    string written = "this should be written to file";

    l.log(LogLevel.critical, written);
    destroy(l);

    auto file = File(filename, "r");
    string readLine = file.readln();
    assert(readLine.startsWith(written), readLine);
}

@("Show all log levels for FormatLogger")
debug (Example) unittest {
    import std.stdio;

    auto l = new FormatLogger(stdout);
    l.fatalHandler = () {};
    static foreach (lv; __traits(allMembers, LogLevel)) {
        l.log(__traits(getMember, LogLevel, lv), "this is FormatLogger " ~ lv);
    }
}

@("Show all log levels for FormatLogger - No Color")
debug (Example) unittest {
    import std.stdio;

    auto l = new FormatLogger(stdout, LogLevel.all, Colorize.no);
    l.fatalHandler = () {};
    static foreach (lv; __traits(allMembers, LogLevel)) {
        l.log(__traits(getMember, LogLevel, lv), "this is FormatLogger " ~ lv);
    }
}

/**
 * A logger implementation whose `LogLevel` is set by the enviornment variable `D_LOG`.
 * The log message is written to the associated file. If the file is already present,
 * new log messages will be appended at its end. By default, the log message is colorized.
 * If the log message shoud be no color, set `D_LOG_COLOR=0`.
 * `D_LOG` should be selected from the following
 * - `all` (default)
 * - `trace`
 * - `info`
 * - `warning`
 * - `error`
 * - `critical`
 * - `fatal`
 * - `off`
 */
class EnvLogger : FormatLogger {
    /**
     * Construct a new logger associated with a file specified as the filename.
     * Params:
     *   fn = The filename
     *   defaultLv = Default log level
     *   createFileNameFolder = Create a directory of the file or not
     *   defaultColorize = Colorize log message by default
     */
    this(
        const string fn,
        const LogLevel defaultLv = LogLevel.all,
        CreateFolder createFileNameFolder = CreateFolder.yes,
        Colorize defaultColorize = Colorize.yes,
    ) @safe {
        super(fn, getEnvLogLevel(defaultLv), createFileNameFolder, getEnvColorize(defaultColorize));
    }

    /**
     * Construct a new logger associated with the file.
     * Params:
     *   file = The file handle
     *   defaultLv = Default log level
     *   defaultColorize = Colorize log message by default
     */
    this(File file, const LogLevel defaultLv = LogLevel.all, Colorize defaultColorize = Colorize
            .yes) @safe {
        super(file, getEnvLogLevel(defaultLv), getEnvColorize(defaultColorize));
    }
}

@("Check if the log level can be set by D_LOG")
unittest {
    import std.file : deleteme, remove;
    import std.string : indexOf;
    import std.process : environment;

    scope (exit) {
        environment.remove("D_LOG");
    }
    environment["D_LOG"] = "critical";

    string filename = deleteme ~ __FUNCTION__ ~ ".tempLogFile";
    auto l = new EnvLogger(filename);

    scope (exit) {
        remove(filename);
    }

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    l.log(LogLevel.warning, notWritten);
    l.log(LogLevel.critical, written);
    destroy(l);

    auto file = File(filename, "r");
    string readLine = file.readln();
    assert(readLine.indexOf(written) != -1, readLine);
    readLine = file.readln();
    assert(readLine.indexOf(notWritten) == -1, readLine);
}

@("Show all log levels for EnvLogger")
debug (Example) unittest {
    import std.stdio;

    scope (exit) {
        environment.remove("D_LOG");
    }
    environment["D_LOG"] = "warning";

    auto l = new EnvLogger(stdout);
    l.fatalHandler = () {};
    static foreach (lv; __traits(allMembers, LogLevel)) {
        l.log(__traits(getMember, LogLevel, lv), "this is EnvLogger " ~ lv);
    }
}

@("Show all log levels for EnvLogger - No Color")
debug (Example) unittest {
    import std.stdio;

    scope (exit) {
        environment.remove("D_LOG");
        environment.remove("D_LOG_COLOR");
    }
    environment["D_LOG"] = "warning";
    environment["D_LOG_COLOR"] = "0";

    auto l = new EnvLogger(stdout, LogLevel.all, Colorize.no);
    l.fatalHandler = () {};
    static foreach (lv; __traits(allMembers, LogLevel)) {
        l.log(__traits(getMember, LogLevel, lv), "this is EnvLogger " ~ lv);
    }
}

/**
 * MultiLogger implementation which outputs both stdout and file.
 */
class TeeLogger(LoggerImpl : FormatLogger) : MultiLogger {

    /// ditto
    this(string fn) {
        import std.stdio : stdout;

        super();
        this.stdoutLogger_ = new EnvLogger(stdout);
        this.fileLogger_ = new EnvLogger(fn)
            .setFormatter((ref Record record) @safe => defaultFormatter(record, Colorize.no));
        this.insertLogger("stdout", this.stdoutLogger_);
        this.insertLogger("file", this.fileLogger_);
    }

    /// ditto
    this(File file) {
        import std.stdio : stdout;

        super();
        this.stdoutLogger_ = new EnvLogger(stdout);
        this.fileLogger_ = new EnvLogger(file)
            .setFormatter((ref Record record) @safe => defaultFormatter(record, Colorize.no));
        this.insertLogger("stdout", this.stdoutLogger_);
        this.insertLogger("file", this.fileLogger_);
    }

    /// ditto
    FormatLogger stdoutLogger() @nogc nothrow @safe {
        return this.stdoutLogger_;
    }

    /// ditto
    FormatLogger fileLogger() @nogc nothrow @safe {
        return this.fileLogger_;
    }

    private FormatLogger stdoutLogger_;
    private FormatLogger fileLogger_;
}

/// ditto
alias FormatTeeLogger = TeeLogger!FormatLogger;
/// ditto
alias EnvTeeLogger = TeeLogger!EnvLogger;

/**
 * Create a colorized string from the `LogLevel`
 * Params:
 *   lv = Log level
 * Returns: Colorized log level string
 */
string colorizeLogLevel(const LogLevel lv) @safe {
    with (LogLevel) final switch (lv) {
    case all:
        return "all";
    case trace:
        return "trace".green;
    case info:
        return "info".cyan;
    case warning:
        return "warning".yellow;
    case error:
        return "error".red;
    case critical:
        return "critical".magenta;
    case fatal:
        return "fatal".red.bold;
    case off:
        return "off";
    }
}

/**
 * Convert to ISO format datetime from systime
 * Params:
 *   time = SysTime
 * Returns: ISO format datetime string
 */
string systimeToISO(in SysTime time) @safe {
    import std.format : format;
    import std.datetime : DateTime;

    const dt = cast(DateTime) time;
    const fsec = time.fracSecs.total!"msecs";

    return format!"%04d-%02d-%02dT%02d:%02d:%02d.%03d"(
        dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, fsec
    );
}

private string defaultFormatter(ref Record record, Colorize colorize = Colorize.yes) @safe {
    import std.format : format;
    import std.conv : to;
    import std.string : lastIndexOf;

    ptrdiff_t fnIdx = record.file.lastIndexOf('/') + 1;

    auto locationText = format!"%s:%u:"(
        record.file[fnIdx .. $],
        record.line,
    );

    auto time = colorize ? systimeToISO(record.timestamp).dim : systimeToISO(record.timestamp);
    auto loc = colorize ? locationText.dim : locationText;
    auto msg = record.msg;
    if (record.logLevel > LogLevel.all) {
        auto lv = colorize ? colorizeLogLevel(record.logLevel) : record.logLevel.to!string;
        return format!"%s %s %s %s"(time, lv, loc, msg);
    }
    else {
        return format!"%s %s %s"(time, loc, msg);
    }
}

private LogLevel getEnvLogLevel(LogLevel defaultLv = LogLevel.all) @safe {
    import std.conv : to;

    auto lvValue = environment.get("D_LOG", defaultLv.to!string);
    switch (lvValue) {
        static foreach (lv; __traits(allMembers, LogLevel)) {
    case lv:
            return __traits(getMember, LogLevel, lv);
        }
    default:
        assert(0);
    }
}

unittest {
    scope (exit) {
        environment.remove("D_LOG");
    }

    environment.remove("D_LOG");
    assert(getEnvLogLevel(LogLevel.info) == LogLevel.info);
    environment["D_LOG"] = "all";
    assert(getEnvLogLevel() == LogLevel.all);
    environment["D_LOG"] = "trace";
    assert(getEnvLogLevel() == LogLevel.trace);
    environment["D_LOG"] = "info";
    assert(getEnvLogLevel() == LogLevel.info);
    environment["D_LOG"] = "warning";
    assert(getEnvLogLevel() == LogLevel.warning);
    environment["D_LOG"] = "error";
    assert(getEnvLogLevel() == LogLevel.error);
    environment["D_LOG"] = "critical";
    assert(getEnvLogLevel() == LogLevel.critical);
    environment["D_LOG"] = "fatal";
    assert(getEnvLogLevel() == LogLevel.fatal);
    environment["D_LOG"] = "off";
    assert(getEnvLogLevel() == LogLevel.off);
}

private Colorize getEnvColorize(Colorize defaultColorize) @safe {
    if ("D_LOG_COLOR" in environment) {
        if (environment["D_LOG_COLOR"] == "0") {
            return Colorize.no;
        }
        else {
            return Colorize.yes;
        }
    }
    return defaultColorize;
}

unittest {
    scope (exit) {
        environment.remove("D_LOG_COLOR");
    }
    environment.remove("D_LOG_COLOR");
    assert(getEnvColorize(Colorize.yes) == Colorize.yes);
    assert(getEnvColorize(Colorize.no) == Colorize.no);

    environment["D_LOG_COLOR"] = "0";
    assert(getEnvColorize(Colorize.yes) == Colorize.no);
    assert(getEnvColorize(Colorize.no) == Colorize.no);

    environment["D_LOG_COLOR"] = "1";
    assert(getEnvColorize(Colorize.yes) == Colorize.yes);
    assert(getEnvColorize(Colorize.no) == Colorize.yes);

}
