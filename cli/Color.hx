/** ANSI styling, applied only when stdout supports colors (as yoctocolors does). **/
class Color {
	static var enabled:Null<Bool>;

	static function detect():Bool {
		final noColor = Sys.getEnv("NO_COLOR");
		if (noColor != null && noColor != "")
			return false;
		final force = Sys.getEnv("FORCE_COLOR");
		if (force != null)
			return force != "0" && force != "false";
		final term = Sys.getEnv("TERM");
		if (Sys.systemName() == "Windows" || term == "dumb")
			return false;
		// Haxe has no isatty, so ask the shell about our stdout
		return Sys.command("test", ["-t", "1"]) == 0;
	}

	static function wrap(open:Int, close:Int, s:String):String {
		if (enabled == null)
			enabled = detect();
		return enabled && s != "" ? '\x1b[${open}m$s\x1b[${close}m' : s;
	}

	public static function bold(s:String):String {
		return wrap(1, 22, s);
	}

	public static function dim(s:String):String {
		return wrap(2, 22, s);
	}

	public static function green(s:String):String {
		return wrap(32, 39, s);
	}

	public static function red(s:String):String {
		return wrap(31, 39, s);
	}

	public static function yellow(s:String):String {
		return wrap(33, 39, s);
	}
}
