import CliUtil.CheckResult;
import CliUtil.FixResult;
import haxe.Json;
import haxe.Timer;
import sys.FileSystem;
import sys.io.File;
import standardclj.Standard;

/** Command-line entry point: the `list`, `check` and `fix` commands. **/
class Cli {
	static final programVersion = "[dev]";
	static final startTime = Timer.stamp();

	static var atLeastOneFilePrinted = false;
	static var logLevel = "everything";
	static var rootDir = "";

	static final helpText = "standard-clj <cmd> [args]

Commands:
  standard-clj check  Checks if files are formatted according to Standard Clojure
                      Style. This command does not modify files. Returns exit
                      code 0 if all files are formatted, 1 otherwise.
  standard-clj fix    Formats files according to Standard Clojure Style. This
                      command will modify your files on disk. Returns exit code 0
                      if all files are formatted, 1 otherwise.
  standard-clj list   Prints a list of files that will be used by the \"check\" or
                      \"fix\" commands. Useful for debugging your .standard-clj.edn
                      file or glob patterns.

Options:
  -c, --config      Path to a .standard-clj.edn or .standard-clj.json file
      --file-ext    Comma-separated file extensions to select
                                  [default: .clj,.cljs,.cljc,.jank,.edn]
  -h, --help        Show help                                          [boolean]
  -ig, --ignore     File, directory, or glob pattern to ignore (repeatable)
  -in, --include    File, directory, or glob pattern to include (repeatable)
  -l, --log-level   Set the logging level: \"everything\",
                    \"ignore-already-formatted\", \"quiet\"
      --output      Output format of the \"list\" command: json, json-pretty, edn,
                    edn-pretty
  -v, --version     Show version number                                [boolean]

Examples:
  standard-clj list src/   List files that will be formatted in the src/
                           directory (recursive)
  standard-clj check src/  Check if files are already formatted in src/
  standard-clj fix src/    Format all files in src/
  standard-clj fix -       Reads from stdin, prints a formatted file to stdout

For more information, see the README at
https://github.com/oakmac/standard-clojure-style-js";

	static function main() {
		rootDir = Sys.getCwd();
		if (rootDir.length > 1 && StringTools.endsWith(rootDir, "/"))
			rootDir = rootDir.substr(0, rootDir.length - 1);
		final argv = ArgParser.parse(Sys.args());

		if (argv.showHelp) {
			Sys.println(helpText);
			Sys.exit(0);
		}
		if (argv.showVersion) {
			Sys.println(programVersion);
			Sys.exit(0);
		}
		if (argv.positional.length == 0) {
			Sys.stderr().writeString(helpText + "\n\nNot enough non-option arguments: got 0, need at least 1\n");
			Sys.exit(1);
		}

		final command = argv.positional.shift();
		if (command != "check" && command != "fix" && command != "list") {
			Sys.stderr().writeString(helpText + '\n\nUnknown command: $command\n');
			Sys.exit(1);
		}
		if (!injectConfigFile(argv))
			Sys.exit(1);

		switch (command) {
			case "check":
				Sys.exit(processCheck(argv));
			case "fix":
				Sys.exit(argv.positional[argv.positional.length - 1] == "-" ? processFixStdin() : processFix(argv));
			default:
				Sys.exit(processList(argv));
		}
	}

	// =========================================================================
	// Output
	// =========================================================================

	static function printToStdout(s:String) {
		if (logLevel != "quiet")
			Sys.println(s);
	}

	static function printToStderr(s:String) {
		if (logLevel != "quiet")
			Sys.stderr().writeString(s + "\n");
	}

	static function formatDuration(seconds:Float):String {
		return Color.dim("[" + Math.round(seconds * 1000 * 100) / 100 + "ms]");
	}

	static function printProgramInfo(command:String) {
		printToStdout(Color.bold("standard-clj " + command) + " " + Color.dim(programVersion));
		printToStdout("");
	}

	static function summaryLine(n:Int, what:String):String {
		return n + " " + CliUtil.fileStr(n) + " " + what;
	}

	// =========================================================================
	// Config file loading
	// =========================================================================

	static function readConfig(filename:String):Dynamic {
		return try Config.parse(filename, File.getContent(filename)) catch (e:Dynamic) null;
	}

	// returns false when a --config file was passed but could not be loaded
	static function injectConfigFile(argv:Argv):Bool {
		var config:Dynamic = null;
		if (argv.config != null && argv.config != "") {
			config = readConfig(argv.config);
			if (config == null) {
				final isJSON = StringTools.endsWith(argv.config, ".json");
				final isEDN = StringTools.endsWith(argv.config, ".edn");
				// the log level is not set yet, so these always print
				printToStderr("Unable to load config file: " + argv.config);
				if (isJSON)
					printToStderr("Maybe the file is invalid JSON?");
				else if (isEDN)
					printToStderr("Maybe the file is invalid EDN?");
				else
					printToStderr("The filename does not end in .json or .edn. That is probably wrong.");
				return false;
			}
		} else {
			// the EDN config takes precedence when both exist
			final json = readConfig(rootDir + "/.standard-clj.json");
			final edn = readConfig(rootDir + "/.standard-clj.edn");
			config = edn != null ? edn : json;
		}
		CliUtil.mergeConfigIntoArgv(argv, config);
		return true;
	}

	// =========================================================================
	// File discovery
	// =========================================================================

	static function getFiles(argv:Argv):Array<String> {
		final files = FileDiscovery.discoverFromArgv(rootDir, argv, (kind, filename) -> {
			final ignoreText = kind == "ignore" ? " to ignore" : "";
			printToStderr(Color.bold(Color.yellow("WARN")) + " Could not find a file or directory" + ignoreText + ' at "' + filename + '"');
		});
		files.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return files;
	}

	// =========================================================================
	// Check and fix
	// =========================================================================

	static function readFile(filename:String):Null<String> {
		return try File.getContent(filename) catch (e:Dynamic) null;
	}

	static function formatText(text:String):Null<FormatResult> {
		return try Standard.format(text) catch (e:Dynamic) null;
	}

	static function reportUnreadable(filename:String, errors:Array<String>) {
		printToStderr("Unable to read file: " + filename);
		atLeastOneFilePrinted = true;
		errors.push(filename);
	}

	static function printAlreadyFormatted(filename:String, seconds:Float) {
		if (logLevel != "ignore-already-formatted") {
			printToStdout(Color.green("✓") + " " + Color.bold(CliUtil.relativeFilename(filename, rootDir)) + " " + formatDuration(seconds));
			atLeastOneFilePrinted = true;
		}
	}

	static function checkFile(r:CheckResult, filename:String) {
		final start = Timer.stamp();
		final text = readFile(filename);
		if (text == null)
			return reportUnreadable(filename, r.filesWithErrors);
		final classification = CliUtil.classifyFormatResult(text, formatText(text));
		final seconds = Timer.stamp() - start;
		switch (classification) {
			case AlreadyFormatted(_):
				printAlreadyFormatted(filename, seconds);
				r.filesThatDidNotRequireFormatting.push(filename);
			case Formatted(_):
				printToStderr(Color.red("✗") + " " + Color.bold(CliUtil.relativeFilename(filename, rootDir)) + " " + formatDuration(seconds));
				atLeastOneFilePrinted = true;
				r.filesThatDidRequireFormatting.push(filename);
			case Error(message):
				printToStderr("Failed to format file " + filename + ": " + message);
				atLeastOneFilePrinted = true;
				r.filesWithErrors.push(filename);
		}
	}

	static function fixFile(r:FixResult, filename:String) {
		final start = Timer.stamp();
		final text = readFile(filename);
		if (text == null)
			return reportUnreadable(filename, r.filesWithErrors);
		final classification = CliUtil.classifyFormatResult(text, formatText(text));
		final seconds = Timer.stamp() - start;
		switch (classification) {
			case Error(message):
				r.filesWithErrors.push(filename);
				printToStderr(Color.red("E")
					+ " "
					+ Color.bold(Color.red(CliUtil.relativeFilename(filename, rootDir)))
					+ " - "
					+ message
					+ " "
					+ formatDuration(seconds));
				atLeastOneFilePrinted = true;
			case Formatted(outputText):
				File.saveContent(filename, outputText);
				r.filesThatWereFormatted.push(filename);
				printToStdout(Color.green("F") + " " + Color.bold(CliUtil.relativeFilename(filename, rootDir)) + " " + formatDuration(seconds));
				atLeastOneFilePrinted = true;
			case AlreadyFormatted(_):
				r.filesThatDidNotRequireFormatting.push(filename);
				printAlreadyFormatted(filename, seconds);
		}
	}

	static function noFilesMessage(command:String):String {
		return 'No files were passed to the "$command" command. Please pass a filename, directory, or --include glob pattern.';
	}

	static function printAllFormatted(n:Int) {
		final what = n == 1 ? "1 file" : "All " + n + " files";
		printToStdout(Color.green(what + " formatted with Standard Clojure Style 👍") + " " + formatDuration(Timer.stamp() - startTime));
	}

	static function processCheck(argv:Argv):Int {
		logLevel = CliUtil.normalizeLogLevel(argv.logLevel);
		printProgramInfo("check");
		final files = getFiles(argv);
		if (files.length == 0) {
			printToStderr(noFilesMessage("check"));
			return 1;
		}
		final result:CheckResult = {
			filesThatDidNotRequireFormatting: [],
			filesThatDidRequireFormatting: [],
			filesWithErrors: [],
		};
		for (f in files)
			checkFile(result, f);
		final summary = CliUtil.buildCheckSummary(result);
		if (atLeastOneFilePrinted)
			printToStdout("");
		if (summary.allFormatted)
			printAllFormatted(files.length);
		else {
			printToStdout(Color.green(summaryLine(summary.numAlreadyFormatted, "formatted with Standard Clojure Style")));
			printToStdout(Color.red(summaryLine(summary.numNeedFormatting, "require formatting")));
			printToStdout("Checked " + summary.total + " " + CliUtil.fileStr(summary.total) + ". " + formatDuration(Timer.stamp() - startTime));
		}
		return summary.exitCode;
	}

	static function processFix(argv:Argv):Int {
		logLevel = CliUtil.normalizeLogLevel(argv.logLevel);
		printProgramInfo("fix");
		final files = getFiles(argv);
		if (files.length == 0) {
			printToStderr(noFilesMessage("fix"));
			return 1;
		}
		final result:FixResult = {
			filesThatDidNotRequireFormatting: [],
			filesThatWereFormatted: [],
			filesWithErrors: [],
		};
		for (f in files)
			fixFile(result, f);
		final summary = CliUtil.buildFixSummary(result);
		if (atLeastOneFilePrinted)
			printToStdout("");
		if (summary.allSuccess)
			printAllFormatted(files.length);
		else {
			// upstream always says "files" here, even for a count of 1
			printToStdout(Color.green((summary.numAlreadyFormatted + summary.numWereFormatted) + " files formatted with Standard Clojure Style"));
			printToStdout(Color.red(summary.numErrors + " files with errors"));
			printToStdout("Checked " + files.length + " files. " + formatDuration(Timer.stamp() - startTime));
		}
		return summary.exitCode;
	}

	static function processFixStdin():Int {
		final text = Sys.stdin().readAll().toString();
		if (text == "") {
			printToStderr('Nothing found on stdin. Please pipe some Clojure code to stdin when using "standard-clj fix -"');
			return 1;
		}
		switch (formatText(text)) {
			case Success(out, _):
				Sys.println(out);
				return 0;
			case Failure(reason) if (reason != null):
				printToStderr("Failed to format code: " + reason);
			default:
				printToStderr("Failed to format your code due to unknown error with the format() function. Please help the standard-clj project by opening an issue to report this 🙏");
		}
		return 1;
	}

	// =========================================================================
	// List
	// =========================================================================

	static function processList(argv:Argv):Int {
		// like upstream, "list" ignores --log-level and always prints
		final files = getFiles(argv);
		final json = Json.stringify(files);
		switch (argv.output) {
			case "json":
				printToStdout(json);
			case "json-pretty":
				printToStdout(Json.stringify(files, null, "  "));
			case "edn":
				printToStdout("[" + files.map(f -> Json.stringify(f)).join(" ") + "]");
			case "edn-pretty":
				printToStdout(StringTools.replace(json, '","', '"\n "'));
			default:
				for (f in files)
					printToStdout(f);
		}
		return 0;
	}
}
