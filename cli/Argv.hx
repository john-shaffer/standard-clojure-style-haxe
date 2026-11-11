/** The parsed command line, plus options merged in from the config file. **/
class Argv {
	/** The `--config` filename. **/
	public var config:Null<String>;

	/** The raw `--file-ext` value, comma-separated. **/
	public var fileExt:Null<String>;

	/** `--ignore` values; null when the option was not passed. **/
	public var ignore:Null<Array<String>>;

	public var ignoreFromConfig:Null<Array<String>>;

	/** `--include` values; null when the option was not passed. **/
	public var include:Null<Array<String>>;

	public var includeFromConfig:Null<Array<String>>;
	public var logLevel:Null<String>;

	/** Set when a config file was loaded and merged in. **/
	public var optionsLoadedViaConfigFile = false;

	/** The `--output` format of the `list` command. **/
	public var output:Null<String>;

	/** Positional arguments, including the command. **/
	public var positional:Array<String> = [];

	public var showHelp = false;
	public var showVersion = false;

	public function new() {}
}
