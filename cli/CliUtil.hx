import standardclj.Standard.FormatResult;

typedef CheckResult = {
	final filesThatDidNotRequireFormatting:Array<String>;
	final filesThatDidRequireFormatting:Array<String>;
	final filesWithErrors:Array<String>;
}

typedef CheckSummary = {
	final allFormatted:Bool;
	final exitCode:Int;
	final numAlreadyFormatted:Int;
	final numErrors:Int;
	final numNeedFormatting:Int;
	final total:Int;
}

enum Classification {
	AlreadyFormatted(outputText:String);
	Formatted(outputText:String);
	Error(errorMessage:String);
}

typedef FixResult = {
	final filesThatDidNotRequireFormatting:Array<String>;
	final filesThatWereFormatted:Array<String>;
	final filesWithErrors:Array<String>;
}

typedef FixSummary = {
	final allSuccess:Bool;
	final exitCode:Int;
	final numAlreadyFormatted:Int;
	final numErrors:Int;
	final numWereFormatted:Int;
	final total:Int;
}

/** Pure helper functions used by `Cli`: no filesystem, no console, no globals. **/
class CliUtil {
	public static final defaultFileExtensions = [".clj", ".cljs", ".cljc", ".jank", ".edn"];

	/**
		Converts a raw `--log-level` value into one of `everything`,
		`ignore-already-formatted` or `quiet`.
	**/
	public static function normalizeLogLevel(level:Dynamic):String {
		final s = level == null ? "" : Std.string(level);
		if (s == "ignore-already-formatted" || s == "1")
			return "ignore-already-formatted";
		if (s == "quiet" || s == "5")
			return "quiet";
		return "everything";
	}

	/**
		Classifies a format result against the original text, appending the
		trailing newline that `check` and `fix` both expect.
	**/
	public static function classifyFormatResult(originalText:String, result:Null<FormatResult>):Classification {
		switch (result) {
			case Success(out, _):
				final outputText = out + "\n";
				return outputText == originalText ? AlreadyFormatted(outputText) : Formatted(outputText);
			case Failure(reason) if (reason != null):
				return Error(reason);
			default:
				return Error("Unknown error! Please help the standard-clj project by opening an issue to report this \u{1F64F}");
		}
	}

	public static function fileStr(numFiles:Int):String {
		return numFiles == 1 ? "file" : "files";
	}

	public static function addPeriodPrefix(f:String):String {
		return f != null && !StringTools.startsWith(f, ".") ? "." + f : f;
	}

	/** Removes the first occurrence of `rootDir` from the filename. **/
	public static function relativeFilename(filename:String, rootDir:String):String {
		final idx = rootDir == "" ? -1 : filename.indexOf(rootDir);
		return idx < 0 ? filename : filename.substr(0, idx) + filename.substr(idx + rootDir.length);
	}

	/**
		Converts a comma-separated `--file-ext` value into extensions with
		leading periods. A missing or empty value gives the defaults.
	**/
	public static function parseFileExt(value:Null<String>):Array<String> {
		if (value == null || value == "")
			return defaultFileExtensions;
		final exts:Array<String> = [];
		for (e in value.split(",").map(addPeriodPrefix))
			if (exts.indexOf(e) < 0)
				exts.push(e);
		return exts;
	}

	static function truthy(v:Dynamic):Bool {
		return v != null && v != false && v != 0 && v != "";
	}

	static function stringList(v:Dynamic):Null<Array<String>> {
		if (Std.isOfType(v, String))
			return [v];
		if (Std.isOfType(v, Array))
			return [for (x in (v : Array<Dynamic>)) if (Std.isOfType(x, String)) x];
		return null;
	}

	/**
		Merges a parsed config object (from `.standard-clj.json` or `.edn`)
		into argv. Command-line flags take precedence. A null config leaves
		argv unchanged.
	**/
	public static function mergeConfigIntoArgv(argv:Argv, config:Dynamic):Argv {
		if (config == null)
			return argv;
		argv.optionsLoadedViaConfigFile = true;
		final logLevel = Reflect.field(config, "log-level");
		if (!truthy(argv.logLevel) && truthy(logLevel))
			argv.logLevel = Std.string(logLevel);
		final include = stringList(Reflect.field(config, "include"));
		if (include != null)
			argv.includeFromConfig = include;
		final ignore = stringList(Reflect.field(config, "ignore"));
		if (ignore != null)
			argv.ignoreFromConfig = ignore;
		return argv;
	}

	/**
		The include and ignore patterns to use, after applying precedence:
		any command-line file selection replaces the configured `include`, and
		a command-line `--ignore` replaces the configured `ignore`.
		`argv.positional` must not contain the command.
	**/
	public static function selectPatterns(argv:Argv):{include:Array<String>, ignore:Array<String>} {
		final cliIncludeWasPassed = argv.include != null;
		final anyCliFileSelection = argv.positional.length > 0 || cliIncludeWasPassed;
		var include = cliIncludeWasPassed ? argv.include : [];
		if (!anyCliFileSelection && argv.optionsLoadedViaConfigFile && argv.includeFromConfig != null)
			include = argv.includeFromConfig;
		var ignore = [];
		if (argv.ignore != null)
			ignore = argv.ignore;
		else if (argv.optionsLoadedViaConfigFile && argv.ignoreFromConfig != null)
			ignore = argv.ignoreFromConfig;
		return {include: include, ignore: ignore};
	}

	public static function buildCheckSummary(r:CheckResult):CheckSummary {
		final numAlreadyFormatted = r.filesThatDidNotRequireFormatting.length;
		final numNeedFormatting = r.filesThatDidRequireFormatting.length;
		final numErrors = r.filesWithErrors.length;
		final total = numAlreadyFormatted + numNeedFormatting + numErrors;
		final allFormatted = numAlreadyFormatted == total && total > 0;
		return {
			allFormatted: allFormatted,
			exitCode: allFormatted ? 0 : 1,
			numAlreadyFormatted: numAlreadyFormatted,
			numErrors: numErrors,
			numNeedFormatting: numNeedFormatting,
			total: total,
		};
	}

	public static function buildFixSummary(r:FixResult):FixSummary {
		final numAlreadyFormatted = r.filesThatDidNotRequireFormatting.length;
		final numWereFormatted = r.filesThatWereFormatted.length;
		final numErrors = r.filesWithErrors.length;
		final total = numAlreadyFormatted + numWereFormatted + numErrors;
		final allSuccess = numErrors == 0 && total > 0;
		return {
			allSuccess: allSuccess,
			exitCode: allSuccess ? 0 : 1,
			numAlreadyFormatted: numAlreadyFormatted,
			numErrors: numErrors,
			numWereFormatted: numWereFormatted,
			total: total,
		};
	}
}
