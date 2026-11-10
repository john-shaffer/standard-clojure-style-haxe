import CliUtil;
import FileDiscovery;
import haxe.io.Path;
import standardclj.Standard.FormatResult;
import sys.FileSystem;
import sys.io.File;

/**
	Unit tests for the CLI helpers, ported from upstream's `cli_util.test.js`
	and `cli_file_discovery.test.js`. Run via `cli-test.hxml`.

	The file discovery tests call the library directly instead of spawning
	the CLI; `smoke-test.sh` covers the CLI itself.
**/
class CliTests {
	static var passed = 0;
	static var failed:Array<String> = [];
	static var current = "";
	static var projectDir = "";

	static function main() {
		cliUtilTests();
		globTests();
		ednTests();
		argParserTests();
		fileDiscoveryTests();
		for (f in failed)
			Sys.println('FAIL $f\n');
		Sys.println('${passed} passed, ${failed.length} failed');
		Sys.exit(failed.length == 0 ? 0 : 1);
	}

	// =========================================================================
	// Harness
	// =========================================================================

	static function test(name:String, body:() -> Void) {
		current = name;
		final before = failed.length;
		try {
			body();
		} catch (e:Dynamic) {
			failed.push('$name\nexception: $e');
		}
		if (failed.length == before)
			passed++;
	}

	static function eq(actual:Dynamic, expected:Dynamic) {
		final a = show(actual);
		final e = show(expected);
		if (a != e)
			failed.push('$current\nexpected: $e\nactual:   $a');
	}

	static function show(v:Dynamic):String {
		return Std.isOfType(v, String) ? haxe.Json.stringify(v) : Std.isOfType(v, Array) ? "[" + (v : Array<Dynamic>).map(show).join(", ") + "]" : Std.string(v);
	}

	static function describe(c:Classification):String {
		return switch (c) {
			case AlreadyFormatted(t): 'already-formatted:$t';
			case Formatted(t): 'formatted:$t';
			case Error(m): 'error:$m';
		}
	}

	// =========================================================================
	// cli_util
	// =========================================================================

	static function cliUtilTests() {
		test("normalizeLogLevel defaults to everything", () -> {
			for (v in ([null, "", "everything", "junk", 0] : Array<Dynamic>))
				eq(CliUtil.normalizeLogLevel(v), "everything");
		});
		test("normalizeLogLevel recognises ignore-already-formatted", () -> {
			for (v in (["ignore-already-formatted", "1", 1] : Array<Dynamic>))
				eq(CliUtil.normalizeLogLevel(v), "ignore-already-formatted");
		});
		test("normalizeLogLevel recognises quiet", () -> {
			for (v in (["quiet", "5", 5] : Array<Dynamic>))
				eq(CliUtil.normalizeLogLevel(v), "quiet");
		});

		final unknown = "error:Unknown error! Please help the standard-clj project by opening an issue to report this \u{1F64F}";
		test("classifyFormatResult already formatted", () -> {
			eq(describe(CliUtil.classifyFormatResult("(def x 1)\n", Success("(def x 1)", false))), "already-formatted:(def x 1)\n");
		});
		test("classifyFormatResult needs formatting", () -> {
			eq(describe(CliUtil.classifyFormatResult("(def x   1)\n", Success("(def x 1)", false))), "formatted:(def x 1)\n");
		});
		test("classifyFormatResult missing trailing newline", () -> {
			eq(describe(CliUtil.classifyFormatResult("(def x 1)", Success("(def x 1)", false))), "formatted:(def x 1)\n");
		});
		test("classifyFormatResult explicit error", () -> {
			eq(describe(CliUtil.classifyFormatResult("(def )", Failure("Unexpected EOF"))), "error:Unexpected EOF");
		});
		test("classifyFormatResult null result", () -> {
			eq(describe(CliUtil.classifyFormatResult("(def x 1)", null)), unknown);
		});
		test("classifyFormatResult appends exactly one newline", () -> {
			eq(describe(CliUtil.classifyFormatResult("anything", Success("(ns foo.core)", false))), "formatted:(ns foo.core)\n");
		});
		test("classifyFormatResult empty file", () -> {
			eq(describe(CliUtil.classifyFormatResult("\n", Success("", false))), "already-formatted:\n");
		});
		test("classifyFormatResult multiline ns form", () -> {
			final formatted = "(ns foo.core\n  (:require\n    [clojure.string :as str]))";
			eq(describe(CliUtil.classifyFormatResult(formatted + "\n", Success(formatted, false))), "already-formatted:" + formatted + "\n");
		});

		test("fileStr", () -> {
			eq(CliUtil.fileStr(1), "file");
			for (n in [0, 2, 100])
				eq(CliUtil.fileStr(n), "files");
		});
		test("addPeriodPrefix", () -> {
			eq(CliUtil.addPeriodPrefix("clj"), ".clj");
			eq(CliUtil.addPeriodPrefix(".edn"), ".edn");
			eq(CliUtil.addPeriodPrefix(null), null);
		});
		test("relativeFilename", () -> {
			eq(CliUtil.relativeFilename("/home/user/project/src/foo.clj", "/home/user/project"), "/src/foo.clj");
			eq(CliUtil.relativeFilename("/other/path/foo.clj", "/home/user/project"), "/other/path/foo.clj");
			eq(CliUtil.relativeFilename("/src/foo.clj", ""), "/src/foo.clj");
		});
		test("parseFileExt", () -> {
			eq(CliUtil.parseFileExt("clj,cljs,.edn"), [".clj", ".cljs", ".edn"]);
			eq(CliUtil.parseFileExt("clj"), [".clj"]);
			eq(CliUtil.parseFileExt("clj,.clj"), [".clj"]);
			eq(CliUtil.parseFileExt(""), CliUtil.defaultFileExtensions);
			eq(CliUtil.parseFileExt(null), CliUtil.defaultFileExtensions);
		});

		test("mergeConfigIntoArgv leaves argv alone for a null config", () -> {
			final argv = new Argv();
			eq(CliUtil.mergeConfigIntoArgv(argv, null) == argv, true);
			eq(argv.optionsLoadedViaConfigFile, false);
		});
		test("mergeConfigIntoArgv sets the flag", () -> {
			final argv = new Argv();
			CliUtil.mergeConfigIntoArgv(argv, {});
			eq(argv.optionsLoadedViaConfigFile, true);
		});
		test("mergeConfigIntoArgv log-level precedence", () -> {
			final argv = new Argv();
			CliUtil.mergeConfigIntoArgv(argv, {"log-level": "quiet"});
			eq(argv.logLevel, "quiet");
			final cli = new Argv();
			cli.logLevel = "everything";
			CliUtil.mergeConfigIntoArgv(cli, {"log-level": "quiet"});
			eq(cli.logLevel, "everything");
		});
		test("mergeConfigIntoArgv wraps strings and passes arrays", () -> {
			final argv = new Argv();
			CliUtil.mergeConfigIntoArgv(argv, {include: "src/**/*.clj", ignore: ["a", "b"]});
			eq(argv.includeFromConfig, ["src/**/*.clj"]);
			eq(argv.ignoreFromConfig, ["a", "b"]);
		});
		test("mergeConfigIntoArgv does not create missing lists", () -> {
			final argv = new Argv();
			CliUtil.mergeConfigIntoArgv(argv, {"log-level": "quiet"});
			eq(argv.includeFromConfig, null);
			eq(argv.ignoreFromConfig, null);
		});
		test("mergeConfigIntoArgv config values flow into selectPatterns", () -> {
			final argv = ArgParser.parse(["--include", "cli-override.clj"]);
			CliUtil.mergeConfigIntoArgv(argv, {include: ["src/**/*.clj"], ignore: "vendor/", "log-level": "quiet"});
			final p = CliUtil.selectPatterns(argv);
			eq(p.include, ["cli-override.clj"]);
			eq(p.ignore, ["vendor/"]);
			eq(argv.includeFromConfig, ["src/**/*.clj"]);
			eq(argv.logLevel, "quiet");
		});

		final noFiles = [];
		test("buildCheckSummary all formatted", () -> {
			final r = CliUtil.buildCheckSummary({filesThatDidNotRequireFormatting: ["a", "b", "c"], filesThatDidRequireFormatting: noFiles, filesWithErrors: noFiles});
			eq([r.total, r.numAlreadyFormatted, r.numNeedFormatting, r.numErrors, r.allFormatted, r.exitCode], [3, 3, 0, 0, true, 0]);
		});
		test("buildCheckSummary some need formatting", () -> {
			final r = CliUtil.buildCheckSummary({filesThatDidNotRequireFormatting: ["a"], filesThatDidRequireFormatting: ["b", "c"], filesWithErrors: noFiles});
			eq([r.total, r.numAlreadyFormatted, r.numNeedFormatting, r.allFormatted, r.exitCode], [3, 1, 2, false, 1]);
		});
		test("buildCheckSummary errors", () -> {
			final r = CliUtil.buildCheckSummary({filesThatDidNotRequireFormatting: ["a"], filesThatDidRequireFormatting: noFiles, filesWithErrors: ["bad"]});
			eq([r.numErrors, r.allFormatted, r.exitCode], [1, false, 1]);
		});
		test("buildCheckSummary empty", () -> {
			final r = CliUtil.buildCheckSummary({filesThatDidNotRequireFormatting: noFiles, filesThatDidRequireFormatting: noFiles, filesWithErrors: noFiles});
			eq([r.total, r.allFormatted, r.exitCode], [0, false, 1]);
		});
		test("buildFixSummary all already formatted", () -> {
			final r = CliUtil.buildFixSummary({filesThatDidNotRequireFormatting: ["a", "b"], filesThatWereFormatted: noFiles, filesWithErrors: noFiles});
			eq([r.total, r.numAlreadyFormatted, r.numWereFormatted, r.allSuccess, r.exitCode], [2, 2, 0, true, 0]);
		});
		test("buildFixSummary some were formatted", () -> {
			final r = CliUtil.buildFixSummary({filesThatDidNotRequireFormatting: ["a"], filesThatWereFormatted: ["b", "c"], filesWithErrors: noFiles});
			eq([r.total, r.numWereFormatted, r.allSuccess, r.exitCode], [3, 2, true, 0]);
		});
		test("buildFixSummary errors fail even if some succeeded", () -> {
			final r = CliUtil.buildFixSummary({filesThatDidNotRequireFormatting: ["a"], filesThatWereFormatted: ["b"], filesWithErrors: ["bad"]});
			eq([r.total, r.numErrors, r.allSuccess, r.exitCode], [3, 1, false, 1]);
		});
		test("buildFixSummary empty", () -> {
			final r = CliUtil.buildFixSummary({filesThatDidNotRequireFormatting: noFiles, filesThatWereFormatted: noFiles, filesWithErrors: noFiles});
			eq([r.total, r.allSuccess, r.exitCode], [0, false, 1]);
		});
		test("classify then buildCheckSummary", () -> {
			final results:Array<Null<FormatResult>> = [Success("(ns foo)", false), Success("(ns bar)", false), Failure("Unexpected EOF")];
			final originals = ["(ns foo)\n", "(ns  bar)\n", "(ns baz"];
			final check:CheckResult = {filesThatDidNotRequireFormatting: [], filesThatDidRequireFormatting: [], filesWithErrors: []};
			for (i in 0...3) {
				final name = 'file$i.clj';
				switch (CliUtil.classifyFormatResult(originals[i], results[i])) {
					case AlreadyFormatted(_):
						check.filesThatDidNotRequireFormatting.push(name);
					case Formatted(_):
						check.filesThatDidRequireFormatting.push(name);
					case Error(_):
						check.filesWithErrors.push(name);
				}
			}
			final s = CliUtil.buildCheckSummary(check);
			eq([s.numAlreadyFormatted, s.numNeedFormatting, s.numErrors, s.allFormatted, s.exitCode], [1, 1, 1, false, 1]);
		});
	}

	// =========================================================================
	// Glob, EDN and argument parsing (no upstream counterparts)
	// =========================================================================

	static function globTests() {
		test("expandBraces", () -> {
			eq(Glob.expandBraces("src/**/*.{clj,cljs}"), ["src/**/*.clj", "src/**/*.cljs"]);
			eq(Glob.expandBraces("{a,b}/{c,d}"), ["a/c", "a/d", "b/c", "b/d"]);
			eq(Glob.expandBraces("{a,{b,c}}x"), ["ax", "bx", "cx"]);
			eq(Glob.expandBraces("{a}"), ["{a}"]);
			eq(Glob.expandBraces("{a,b"), ["{a,b"]);
		});
		test("star stays within a segment", () -> {
			eq(Glob.matches("src/*.clj", "src/a.clj"), true);
			eq(Glob.matches("src/*.clj", "src/x/a.clj"), false);
		});
		test("globstar matches zero or more directories", () -> {
			eq(Glob.matches("src/**/*.clj", "src/a.clj"), true);
			eq(Glob.matches("src/**/*.clj", "src/x/y/a.clj"), true);
			eq(Glob.matches("src/**/*.clj", "test/a.clj"), false);
		});
		test("wildcards do not match dotfiles", () -> {
			eq(Glob.matches("src/*", "src/.hidden"), false);
			eq(Glob.matches("src/**/*.clj", "src/.git/a.clj"), false);
			eq(Glob.matches("src/.*", "src/.hidden"), true);
		});
		test("question mark and character classes", () -> {
			eq(Glob.matches("a?.clj", "ab.clj"), true);
			eq(Glob.matches("a?.clj", "a.clj"), false);
			eq(Glob.matches("[a-c]x", "bx"), true);
			eq(Glob.matches("[!a-c]x", "bx"), false);
		});
		test("braces in matches", () -> {
			eq(Glob.matches("{src,test}/**/*.{clj,cljc}", "test/a/b.cljc"), true);
			eq(Glob.matches("{src,test}/**/*.{clj,cljc}", "dev/b.cljc"), false);
		});
	}

	static function ednTests() {
		test("edn reads the config shape", () -> {
			final c = Edn.parse('{:include ["src/" "test/"], ; comment\n :ignore "gen/" #_:skipped :log-level :quiet}');
			eq(Reflect.field(c, "include"), ["src/", "test/"]);
			eq(Reflect.field(c, "ignore"), "gen/");
			eq(Reflect.field(c, "log-level"), "quiet");
		});
		test("edn reads strings with escapes and scalars", () -> {
			final c = Edn.parse('{:a "x\\"y" :b 5 :c nil :d true :e #{1 2}}');
			eq(Reflect.field(c, "a"), 'x"y');
			eq(Reflect.field(c, "b"), 5);
			eq(Reflect.field(c, "d"), true);
			eq(Reflect.field(c, "e"), [1, 2]);
		});
		test("edn rejects malformed input", () -> {
			for (bad in ["", "{:a", "{:a 1 :b}", "[1 2}", "\"abc"])
				eq(Config.parse("x.edn", bad), null);
		});
		test("json config", () -> {
			eq(Reflect.field(Config.parse("c.json", '{"include": ["src"]}'), "include"), ["src"]);
			eq(Config.parse("c.json", "{"), null);
			eq(Config.parse("c.txt", "{}"), null);
		});
	}

	static function argParserTests() {
		test("argparser positional, options and aliases", () -> {
			final a = ArgParser.parse(["check", "src/", "-in", "x", "--include=y", "-ig", "z", "-l", "quiet", "-c", "c.edn", "--file-ext", "clj", "--output", "json", "-"]);
			eq(a.positional, ["check", "src/", "-"]);
			eq(a.include, ["x", "y"]);
			eq(a.ignore, ["z"]);
			eq(a.logLevel, "quiet");
			eq(a.config, "c.edn");
			eq(a.fileExt, "clj");
			eq(a.output, "json");
		});
		test("argparser flags and terminator", () -> {
			final a = ArgParser.parse(["-h", "-v", "--", "--include"]);
			eq([a.showHelp, a.showVersion], [true, true]);
			eq(a.positional, ["--include"]);
			eq(a.include, null);
		});
	}

	// =========================================================================
	// cli_file_discovery
	// =========================================================================

	static function writeFile(rel:String, contents:String) {
		final abs = Path.join([projectDir, rel]);
		mkdirs(Path.directory(abs));
		File.saveContent(abs, contents);
	}

	static function mkdirs(dir:String) {
		if (dir == "" || FileSystem.exists(dir))
			return;
		mkdirs(Path.directory(dir));
		FileSystem.createDirectory(dir);
	}

	static function rmrf(p:String) {
		if (FileSystem.isDirectory(p)) {
			for (f in FileSystem.readDirectory(p))
				rmrf(Path.join([p, f]));
			FileSystem.deleteDirectory(p);
		} else
			FileSystem.deleteFile(p);
	}

	static function createTestProject() {
		final tmp = Sys.getEnv("TMPDIR") != null ? Sys.getEnv("TMPDIR") : "/tmp";
		projectDir = FileSystem.fullPath(tmp) + "/standard-clj-file-discovery-" + Std.random(1 << 30);
		mkdirs(projectDir);
		final files = [
			"dev/user.clj" => "(ns user)\n",
			"resources/config.edn" => "{:enabled true}\n",
			"src/browser.cljs" => "(ns browser)\n",
			"src/core.clj" => "(ns core)\n",
			"src/data.edn" => '{:hello "world"}\n',
			"src/experimental.jank" => "(ns experimental)\n",
			"src/generated/generated.clj" => "(ns generated)\n",
			"src/generated/generated.cljs" => "(ns generated-browser)\n",
			"src/nested/deep.clj" => "(ns nested.deep)\n",
			"src/nested/deep.cljs" => "(ns nested.deep-browser)\n",
			"src/nested/deep.cljc" => "(ns nested.deep-shared)\n",
			"src/nested/notes.md" => "# notes\n",
			"src/notes.txt" => "not Clojure\n",
			"src/shared.cljc" => "(ns shared)\n",
			"test/core_test.clj" => "(ns core-test)\n",
			"test/nested/browser_test.cljs" => "(ns browser-test)\n",
		];
		for (name => contents in files)
			writeFile(name, contents);
	}

	static function absoluteFiles(rels:Array<String>):Array<String> {
		final out = rels.map(r -> projectDir + "/" + r);
		out.sort(cmp);
		return out;
	}

	static function cmp(a:String, b:String):Int {
		return a < b ? -1 : a > b ? 1 : 0;
	}

	/** Runs the same pipeline as the `list` command; returns sorted files. **/
	static function runList(args:Array<String>, ?config:String, ?warnings:Array<String>):Array<String> {
		final argv = ArgParser.parse(args);
		if (config != null)
			CliUtil.mergeConfigIntoArgv(argv, Config.parse(config.charAt(0) == "{" && config.indexOf('"') == 1 ? "c.json" : "c.edn", config));
		final files = FileDiscovery.discoverFromArgv(projectDir, argv, (kind, name) -> if (warnings != null) warnings.push(kind + ":" + name));
		files.sort(cmp);
		return files;
	}

	static function discoveryCase(name:String, args:Array<String>, expected:Array<String>, ?config:String) {
		test(name, () -> eq(runList(args, config), absoluteFiles(expected)));
	}

	static final allSrc = [
		"src/browser.cljs", "src/core.clj", "src/data.edn", "src/experimental.jank", "src/generated/generated.clj", "src/generated/generated.cljs",
		"src/nested/deep.clj", "src/nested/deep.cljs", "src/nested/deep.cljc", "src/shared.cljc",
	];
	static final srcNested = ["src/nested/deep.clj", "src/nested/deep.cljs", "src/nested/deep.cljc"];
	static final srcCljFamily = [
		"src/browser.cljs", "src/core.clj", "src/generated/generated.clj", "src/generated/generated.cljs", "src/nested/deep.clj", "src/nested/deep.cljs",
		"src/nested/deep.cljc", "src/shared.cljc",
	];
	static final srcNoGenerated = [
		"src/browser.cljs", "src/core.clj", "src/data.edn", "src/experimental.jank", "src/nested/deep.clj", "src/nested/deep.cljs", "src/nested/deep.cljc",
		"src/shared.cljc",
	];
	static final srcTopLevel = ["src/browser.cljs", "src/core.clj", "src/data.edn", "src/experimental.jank", "src/shared.cljc"];
	static final srcClj = ["src/core.clj", "src/generated/generated.clj", "src/nested/deep.clj"];
	static final srcCljCljcShared = ["src/core.clj", "src/generated/generated.clj", "src/nested/deep.clj", "src/nested/deep.cljc", "src/shared.cljc"];
	static final testFiles = ["test/core_test.clj", "test/nested/browser_test.cljs"];
	static final srcCljNoGenerated = ["src/browser.cljs", "src/core.clj", "src/nested/deep.clj", "src/nested/deep.cljs", "src/nested/deep.cljc", "src/shared.cljc"];

	static function fileDiscoveryTests() {
		createTestProject();

		// direct file and directory arguments
		discoveryCase("includes a directly named file", ["src/core.clj"], ["src/core.clj"]);
		discoveryCase("allows a directly named file with a non-default extension", ["src/notes.txt"], ["src/notes.txt"]);
		discoveryCase("recursively discovers supported files in a directory", ["src"], allSrc);
		discoveryCase("uses --file-ext when discovering files from a directory", ["src", "--file-ext", "clj,cljs"], [
			"src/browser.cljs", "src/core.clj", "src/generated/generated.clj", "src/generated/generated.cljs", "src/nested/deep.clj", "src/nested/deep.cljs",
		]);

		// --include files and directories
		discoveryCase("--include a file with a supported extension", ["--include", "src/core.clj"], ["src/core.clj"]);
		discoveryCase("--include filters a file with a non-default extension", ["--include", "src/notes.txt"], []);
		discoveryCase("--include a literal directory", ["--include", "src"], allSrc);
		discoveryCase("--include accepts a trailing slash", ["--include", "src/"], allSrc);
		discoveryCase("--include a nested literal directory", ["--include", "src/nested"], srcNested);
		test("--include an absolute literal directory", () -> eq(runList(["--include", projectDir + "/src/nested"]), absoluteFiles(srcNested)));
		discoveryCase("--include combines literal directories", ["--include", "dev", "--include", "test"], ["dev/user.clj"].concat(testFiles));
		discoveryCase("--include combines a directory with a glob", ["--include", "dev", "--include", "src/**/*.cljc"], [
			"dev/user.clj", "src/nested/deep.cljc", "src/shared.cljc",
		]);
		discoveryCase("--include deduplicates a directory and an overlapping glob", ["--include", "src", "--include", "src/**/*.clj"], allSrc);
		discoveryCase("--include a directory uses --file-ext", ["--include", "src", "--file-ext", "clj,cljc"], srcCljCljcShared);
		discoveryCase("literal directory ignore applies to an include directory", ["--include", "src", "--ignore", "src/generated"], srcNoGenerated);
		discoveryCase("ignore globs apply to an include directory", ["--include", "src", "--ignore", "src/{generated,nested}/**/*"], srcTopLevel);
		discoveryCase("--include . searches the current directory", ["--include", "."], ["dev/user.clj", "resources/config.edn"].concat(allSrc).concat(testFiles));
		test("--include an empty directory", () -> {
			mkdirs(projectDir + "/empty");
			eq(runList(["--include", "empty"]), []);
		});

		// --include patterns
		discoveryCase("* matches within one directory level", ["--include", "src/*.clj"], ["src/core.clj"]);
		discoveryCase("** recursively matches directories", ["--include", "src/**/*.clj"], srcClj);
		discoveryCase("brace expansion for extensions", ["--include", "src/**/*.{clj,cljs,cljc}"], srcCljFamily);
		discoveryCase("brace expansion for directory names", ["--include", "{src,test}/**/*.clj"], srcClj.concat(["test/core_test.clj"]));
		discoveryCase("multiple include patterns", ["--include", "src/**/*.clj", "--include", "test/**/*.clj"], srcClj.concat(["test/core_test.clj"]));
		discoveryCase("deduplicates overlapping include patterns", ["--include", "src/**/*.clj", "--include", "src/core.clj"], srcClj);
		discoveryCase("direct arguments combine with --include", ["dev/user.clj", "--include", "src/*.clj"], ["dev/user.clj", "src/core.clj"]);
		discoveryCase("broad patterns return only supported regular files", ["--include", "src/**/*"], allSrc);
		discoveryCase("--file-ext filters pattern results", ["--include", "src/**/*", "--file-ext", "clj,cljc"], srcCljCljcShared);
		discoveryCase("a pattern that matches nothing yields nothing", ["--include", "does-not-exist/**/*.clj"], []);

		// --ignore patterns
		discoveryCase("ignores a relative filename", ["--include", "src/**/*.clj", "--ignore", "src/nested/deep.clj"], ["src/core.clj", "src/generated/generated.clj"]);
		discoveryCase("ignores everything beneath a directory", ["--include", "src/**/*.{clj,cljs,cljc}", "--ignore", "src/generated"], srcCljNoGenerated);
		discoveryCase("recursive ignore globs", ["--include", "src/**/*.{clj,cljs,cljc}", "--ignore", "src/generated/**/*"], srcCljNoGenerated);
		discoveryCase("brace expansion in ignore patterns", [
			"--include", "src/**/*.{clj,cljs,cljc}", "--ignore", "src/{generated,nested}/**/*.{clj,cljs,cljc}",
		], ["src/browser.cljs", "src/core.clj", "src/shared.cljc"]);
		discoveryCase("multiple ignore patterns", [
			"--include", "src/**/*.clj", "--ignore", "src/generated/**/*.clj", "--ignore", "src/nested/**/*.clj",
		], ["src/core.clj"]);
		discoveryCase("ignores apply to a directory argument", ["src", "--ignore", "src/{generated,nested}/**/*"], srcTopLevel);

		// configuration files and command-line precedence
		discoveryCase("config: literal include directory from JSON", [], allSrc, '{"include": ["src"]}');
		discoveryCase("config: literal include with trailing slash from EDN", [], allSrc, '{:include ["src/"]}\n');
		discoveryCase("config: multiple literal include directories", [], ["dev/user.clj"].concat(testFiles), '{"include": ["dev", "test"]}');
		discoveryCase("config: ignore applies to a configured directory", [], srcTopLevel, '{"include": ["src"], "ignore": ["src/{generated,nested}/**/*"]}');
		discoveryCase("config: command-line directory replaces configured include", ["--include", "src/nested"], srcNested, '{"include": ["test/**/*.clj"]}');
		discoveryCase("config: include and ignore from JSON", [], srcCljNoGenerated, '{"include": ["src/**/*.{clj,cljs,cljc}"], "ignore": ["src/generated/**/*"]}');
		discoveryCase("config: include and ignore from EDN", [], srcCljNoGenerated, '{:include ["src/**/*.{clj,cljs,cljc}"]\n :ignore ["src/generated/**/*"]}\n');
		discoveryCase("config: command-line include replaces configured include", ["--include", "src/*.clj"], ["src/core.clj"], '{"include": ["test/**/*.clj"]}');
		discoveryCase("config: direct arguments replace configured include", ["dev/user.clj"], ["dev/user.clj"], '{"include": ["test/**/*.clj"]}');
		discoveryCase("config: configured ignore still applies with command-line include", ["--include", "src/**/*.clj"], ["src/core.clj", "src/nested/deep.clj"], '{"include": ["test/**/*.clj"], "ignore": ["src/generated/**/*"]}');
		discoveryCase("config: command-line ignore replaces configured ignore", ["--ignore", "src/nested/**/*"], ["src/core.clj", "src/generated/generated.clj"], '{"include": ["src/**/*.clj"], "ignore": ["src/generated/**/*"]}');

		// warnings for missing paths
		test("warns when a direct argument does not exist", () -> {
			final w = [];
			eq(runList(["does-not-exist.clj", "src/core.clj"], null, w), absoluteFiles(["src/core.clj"]));
			eq(w, ["include:does-not-exist.clj"]);
		});
		test("warns when a literal --ignore path does not exist", () -> {
			final w = [];
			eq(runList(["src/core.clj", "--ignore", "no-such-path"], null, w), absoluteFiles(["src/core.clj"]));
			eq(w, ["ignore:no-such-path"]);
		});
		test("an --ignore glob that matches nothing is silent", () -> {
			final w = [];
			eq(runList(["--include", "src/*.clj", "--ignore", "does-not-exist/**/*"], null, w), absoluteFiles(["src/core.clj"]));
			eq(w, []);
		});

		// ignoring explicitly named files
		discoveryCase("ignores a directly named file with a non-default extension", ["src/notes.txt", "--ignore", "src/notes.txt"], []);
		discoveryCase("a directory ignore removes a directly named non-default file", ["src/notes.txt", "--ignore", "src"], []);

		// patterns that also match directories
		discoveryCase("a pattern matching only a directory yields no files", ["--include", "src*"], []);
		test("a pattern matching a directory does not shadow sibling files", () -> {
			writeFile("srcfile.clj", "(ns srcfile)\n");
			eq(runList(["--include", "src*"]), absoluteFiles(["srcfile.clj"]));
		});

		rmrf(projectDir);
	}
}
