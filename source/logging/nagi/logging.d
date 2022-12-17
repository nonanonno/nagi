module nagi.logging;

import std.experimental.logger;
import std.process : environment;
import std.concurrency : Tid;
import std.datetime : SysTime;
import std.stdio : File;
import nagi.console;

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
 * A logger implementation whose `LogLevel` is set by the enviornment variable `D_LOG`.
 * The log message is written to the associated file. If the file is already present,
 * new log messages will be appended at its end.
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
class EnvLogger : Logger {
    import std.file : exists, mkdirRecurse;
    import std.path : dirName;
    import std.conv : text;

    /**
     * Construct a new logger associated with a file specified as the filename.
     * Params:
     *   fn = The filename
     *   defaultLv = Default log level
     *   createFileNameFolder = Create a directory of the file or not
     */
    this(const string fn, const LogLevel defaultLv = LogLevel.all, CreateFolder createFileNameFolder = CreateFolder
            .yes) @safe {
        super(getEnvLogLevel(defaultLv));

        this.filename = fn;

        if (createFileNameFolder) {
            auto d = dirName(this.filename);
            mkdirRecurse(d);
            assert(exists(d), text("The folder the EnvLogger should have",
                    " created in '", d, "' could not be created."));
        }

        this.file_.open(this.filename, "a");
        this.formatter = (ref Record record) @safe => defaultFormatter(record);
    }

    /**
     * Construct a new logger associated with the file.
     * Params:
     *   file = The file handle
     *   defaultLv = Default log level
     */
    this(File file, const LogLevel defaultLv = LogLevel.all) @safe {
        super(getEnvLogLevel(defaultLv));
        this.file_ = file;
        this.formatter = (ref Record record) @safe => defaultFormatter(record);
    }

    /// The file handle.
    @property File file() @safe {
        return this.file_;
    }

    /// The formatter delegate which consume Record and make a message.
    string delegate(ref Record) @safe formatter;

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
        formattedWrite(lt, "%s\n", formatter(record));
        this.file_.flush();
    }

    protected File file_;
    protected string filename;
}

@("Check if the log is written")
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
    auto l = new EnvLogger(filename);

    scope (exit) {
        remove(filename);
    }

    l.formatter = (ref Record record) @safe => record.msg;

    string written = "this should be written to file";

    l.log(LogLevel.critical, written);
    destroy(l);

    auto file = File(filename, "r");
    string readLine = file.readln();
    assert(readLine.startsWith(written), readLine);
}

@("Show all log levels")
debug (Example) unittest {
    import std.stdio;

    auto l = new EnvLogger(stdout);
    l.fatalHandler = () => writeln("Fatal handler is called");
    static foreach (lv; __traits(allMembers, LogLevel)) {
        l.log(__traits(getMember, LogLevel, lv), "this is " ~ lv);
    }
}

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

private string defaultFormatter(ref Record record) @safe {
    import std.format : format;
    import std.string : lastIndexOf;

    ptrdiff_t fnIdx = record.file.lastIndexOf('/') + 1;

    auto pos = format!"%s:%u:"(
        record.file[fnIdx .. $],
        record.line,
    );

    return format!"%s %s %s %s"(
        systimeToISO(record.timestamp).dim,
        colorizeLogLevel(record.logLevel),
        pos.dim,
        record.msg,
    );
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
