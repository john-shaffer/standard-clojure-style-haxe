import haxe.io.Path;
import sys.FileSystem;

typedef DiscoverOptions = {
	final directArgs:Array<String>;
	final fileExtensions:Array<String>;
	final ignorePatterns:Array<String>;
	final includePatterns:Array<String>;
	/** Called with `"include"` or `"ignore"` and the path that was not found. **/
	final ?onMissingPath:(kind:String, filename:String) -> Void;
	final rootDir:String;
}

/**
	Filesystem-backed file discovery: positional files and directories,
	`--include` patterns and `--ignore` patterns.
**/
class FileDiscovery {
	static final maxDepth = 64;

	public static function absolutePath(rootDir:String, filename:String):String {
		final full = isAbsolute(filename) ? filename : rootDir + "/" + filename;
		return stripTrailingSlash(Path.normalize(full));
	}

	static function isAbsolute(p:String):Bool {
		return StringTools.startsWith(p, "/") || ~/^[A-Za-z]:[\\\/]/.match(p);
	}

	static function stripTrailingSlash(p:String):String {
		return p.length > 1 && StringTools.endsWith(p, "/") ? p.substr(0, p.length - 1) : p;
	}

	/** Like node's `path.extname`: `".clj"` for `a.clj`, `""` for `.bashrc`. **/
	public static function extname(filename:String):String {
		final base = Path.withoutDirectory(filename);
		final dot = base.lastIndexOf(".");
		return dot <= 0 ? "" : base.substr(dot);
	}

	static function hasAllowedExtension(filename:String, exts:Array<String>):Bool {
		return exts.indexOf(extname(filename)) >= 0;
	}

	static function isFile(p:String):Bool {
		return FileSystem.exists(p) && !FileSystem.isDirectory(p);
	}

	static function isDirectory(p:String):Bool {
		return FileSystem.exists(p) && FileSystem.isDirectory(p);
	}

	static function join(dir:String, name:String):String {
		return StringTools.endsWith(dir, "/") ? dir + name : dir + "/" + name;
	}

	static function readDir(dir:String):Array<String> {
		return try FileSystem.readDirectory(dir) catch (e:Dynamic) [];
	}

	static function addFilesFromDirectory(files:Map<String, Bool>, dir:String, shouldInclude:String->Bool, depth = 0) {
		if (depth > maxDepth)
			return;
		for (name in readDir(dir)) {
			final p = join(dir, name);
			if (isDirectory(p))
				addFilesFromDirectory(files, p, shouldInclude, depth + 1);
			else if (isFile(p) && shouldInclude(p))
				files[p] = true;
		}
	}

	/** The files (not directories) matching a glob pattern. **/
	public static function filesFromGlob(rootDir:String, pattern:String):Array<String> {
		final found:Map<String, Bool> = [];
		for (expanded in Glob.expandBraces(pattern)) {
			var p = expanded;
			while (StringTools.startsWith(p, "./"))
				p = p.substr(2);
			var base = rootDir;
			if (StringTools.startsWith(p, "/")) {
				base = "/";
				p = p.substr(1);
			}
			final segs = p.split("/").filter(s -> s != "");
			// the literal leading segments name the directory to search
			final prefix:Array<String> = [];
			while (segs.length > 0 && !Glob.hasMagic(segs[0]) && segs[0].indexOf("\\") < 0)
				prefix.push(segs.shift());
			if (segs.length == 0)
				continue;
			final absBase = absolutePath(base, prefix.join("/") == "" ? "." : prefix.join("/"));
			final recursive = segs.indexOf("**") >= 0;
			final wantsDot = segs.filter(s -> StringTools.startsWith(s, ".")).length > 0;
			walkGlob(found, absBase, [], segs, recursive ? maxDepth : segs.length, wantsDot);
		}
		return [for (f in found.keys()) f];
	}

	static function walkGlob(found:Map<String, Bool>, dir:String, rel:Array<String>, pat:Array<String>, depthLeft:Int, wantsDot:Bool) {
		if (depthLeft <= 0)
			return;
		for (name in readDir(dir)) {
			final p = join(dir, name);
			final segs = rel.concat([name]);
			if (isDirectory(p)) {
				if (wantsDot || !StringTools.startsWith(name, "."))
					walkGlob(found, p, segs, pat, depthLeft - 1, wantsDot);
			} else if (isFile(p) && Glob.matchSegments(pat, 0, segs, 0))
				found[p] = true;
		}
	}

	static function addDirectArgument(files:Map<String, Bool>, rootDir:String, directArg:String, exts:Array<String>, onMissing:(String, String) -> Void) {
		final p = absolutePath(rootDir, directArg);
		if (isFile(p))
			// a directly named file is explicit, so allow any extension
			files[p] = true;
		else if (isDirectory(p))
			addFilesFromDirectory(files, p, f -> hasAllowedExtension(f, exts));
		else
			onMissing("include", directArg);
	}

	static function addIncludePattern(files:Map<String, Bool>, rootDir:String, pattern:String, exts:Array<String>) {
		final p = absolutePath(rootDir, pattern);
		if (isFile(p)) {
			if (hasAllowedExtension(p, exts))
				files[p] = true;
		} else if (isDirectory(p))
			addFilesFromDirectory(files, p, f -> hasAllowedExtension(f, exts));
		else
			for (f in filesFromGlob(rootDir, pattern))
				if (hasAllowedExtension(f, exts))
					files[f] = true;
	}

	static function addIgnorePattern(files:Map<String, Bool>, rootDir:String, pattern:String, onMissing:(String, String) -> Void) {
		final p = absolutePath(rootDir, pattern);
		if (isFile(p))
			files[p] = true;
		else if (isDirectory(p))
			// no extension filter: an ignored directory removes everything beneath it
			addFilesFromDirectory(files, p, _ -> true);
		else {
			final globFiles = filesFromGlob(rootDir, pattern);
			for (f in globFiles)
				files[f] = true;
			// a glob that matches nothing is silent; a missing literal path warns
			if (globFiles.length == 0 && !Glob.hasMagic(pattern))
				onMissing("ignore", pattern);
		}
	}

	/** Returns the unique absolute filenames selected by the options. **/
	public static function discoverFiles(opts:DiscoverOptions):Array<String> {
		final include:Map<String, Bool> = [];
		final ignore:Map<String, Bool> = [];
		final onMissing = opts.onMissingPath != null ? opts.onMissingPath : (_, _) -> {};
		for (a in opts.directArgs)
			addDirectArgument(include, opts.rootDir, a, opts.fileExtensions, onMissing);
		for (p in opts.includePatterns)
			addIncludePattern(include, opts.rootDir, p, opts.fileExtensions);
		for (p in opts.ignorePatterns)
			addIgnorePattern(ignore, opts.rootDir, p, onMissing);
		return [for (f in include.keys()) if (!ignore.exists(f)) f];
	}

	/**
		Discovers the files for an argv that has been merged with its config
		(see `CliUtil.mergeConfigIntoArgv`) and has had its command removed.
	**/
	public static function discoverFromArgv(rootDir:String, argv:Argv, ?onMissingPath:(String, String) -> Void):Array<String> {
		final patterns = CliUtil.selectPatterns(argv);
		return discoverFiles({
			directArgs: argv.positional,
			fileExtensions: CliUtil.parseFileExt(argv.fileExt),
			ignorePatterns: patterns.ignore,
			includePatterns: patterns.include,
			onMissingPath: onMissingPath,
			rootDir: rootDir,
		});
	}
}
