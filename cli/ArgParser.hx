/** Parses command-line arguments the way upstream's yargs setup does. **/
class ArgParser {
	static final aliases = [
		"c" => "config",
		"h" => "help",
		"ig" => "ignore",
		"in" => "include",
		"l" => "log-level",
		"v" => "version",
	];

	static final valueOptions = ["config", "file-ext", "ignore", "include", "log-level", "output"];

	public static function parse(args:Array<String>):Argv {
		final argv = new Argv();
		var i = 0;
		while (i < args.length) {
			final a = args[i++];
			if (a == "--") {
				while (i < args.length)
					argv.positional.push(args[i++]);
				break;
			}
			var name:String;
			if (StringTools.startsWith(a, "--") && a.length > 2)
				name = a.substr(2);
			else if (StringTools.startsWith(a, "-") && a.length > 1 && !~/^-[0-9.]/.match(a))
				name = a.substr(1);
			else {
				argv.positional.push(a);
				continue;
			}
			var value:Null<String> = null;
			final eq = name.indexOf("=");
			if (eq >= 0) {
				value = name.substr(eq + 1);
				name = name.substr(0, eq);
			}
			if (!StringTools.startsWith(a, "--") && aliases.exists(name))
				name = aliases[name];
			if (valueOptions.indexOf(name) >= 0) {
				if (value == null)
					value = i < args.length && (!StringTools.startsWith(args[i], "-") || args[i] == "-") ? args[i++] : "";
				set(argv, name, value);
			} else if (name == "help")
				argv.showHelp = true;
			else if (name == "version")
				argv.showVersion = true;
			// unknown options are ignored, as in yargs without strict mode
		}
		return argv;
	}

	static function set(argv:Argv, name:String, value:String) {
		switch (name) {
			case "config":
				argv.config = value;
			case "file-ext":
				argv.fileExt = value;
			case "ignore":
				if (argv.ignore == null)
					argv.ignore = [];
				argv.ignore.push(value);
			case "include":
				if (argv.include == null)
					argv.include = [];
				argv.include.push(value);
			case "log-level":
				argv.logLevel = value;
			case "output":
				argv.output = value;
		}
	}
}
