/** Parsing of `.standard-clj.json` and `.standard-clj.edn` config files. **/
class Config {
	/** Parses config text as JSON or EDN by filename; null when invalid. **/
	public static function parse(filename:String, text:String):Dynamic {
		try {
			if (StringTools.endsWith(filename, ".json"))
				return haxe.Json.parse(text);
			if (StringTools.endsWith(filename, ".edn"))
				return Edn.parse(text);
		} catch (e:Dynamic) {}
		return null;
	}
}
