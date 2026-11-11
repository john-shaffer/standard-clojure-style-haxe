package standardclj;

import standardclj.NsData;

enum FormatResult {
	/** The formatted text; `ignored` is set when the file opted out with `#_:standard-clj/ignore-file`. **/
	Success(out:String, ignored:Bool);

	/** The input could not be formatted, e.g. a malformed `ns` form. **/
	Failure(reason:String);
}

/** The public API of the library. **/
class Standard {
	/** Formats Clojure source text. **/
	public static function format(text:String):FormatResult {
		// replace any CRLF with LF before we do anything
		final input = FormatUtil.crlfToLf(text);
		final root = Parser.parse(input);
		final nodes = root.flatten();
		if (NsParser.lookForIgnoreFile(nodes))
			return Success(input, true);
		final parsedNs:Ns = try {
			NsParser.parse(nodes);
		} catch (e:haxe.Exception) {
			return Failure(e.message);
		}
		return NodesFormatter.format(root, parsedNs);
	}

	/** Parses Clojure source text into a syntax tree. Never fails. **/
	public static function parse(text:String):Node {
		return Parser.parse(text);
	}
}
