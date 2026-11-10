package;

import Eno.Case;
import standardclj.NsParser;
import standardclj.Parser;

/** The test_parse_ns suite: the ns data parsed from `input` must equal the JSON in `expected`. **/
class ParseNsSuite {
	// the files each case name was seen in, to check that names are unique
	static final filesByName:Map<String, Array<String>> = [];

	/** Returns null on success, else a failure message. **/
	public static function run(c:Case):Null<String> {
		final files = filesByName.exists(c.name) ? filesByName.get(c.name) : [];
		files.push(c.file);
		filesByName.set(c.name, files);
		if (files.length > 1)
			return 'duplicate test name (x${files.length}: ${files.join(", ")})';

		var expected:Dynamic;
		try {
			expected = haxe.Json.parse(c.expected);
		} catch (e:Dynamic) {
			return "the Expected text is not valid JSON: " + Std.string(e);
		}

		final flatNodes = Parser.parse(c.input).flatten();
		try {
			final actual = NsParser.parse(flatNodes);
			if (equal(actual, expected))
				return null;
			return 'expected:\n${c.expected}\nactual:\n${haxe.Json.stringify(actual, null, "  ")}';
		} catch (e:haxe.Exception) {
			if (expected != null && expected.parsingShouldError == true && e.message == expected.errorMessage)
				return null;
			return 'unexpected error: ${e.message}';
		}
	}

	// deep equality; the order of object keys is irrelevant, the order of arrays is not
	static function equal(a:Dynamic, b:Dynamic):Bool {
		if (a == null || b == null)
			return a == null && b == null;
		if (Std.isOfType(a, Array) || Std.isOfType(b, Array)) {
			if (!Std.isOfType(a, Array) || !Std.isOfType(b, Array))
				return false;
			final x:Array<Dynamic> = a;
			final y:Array<Dynamic> = b;
			if (x.length != y.length)
				return false;
			for (i in 0...x.length)
				if (!equal(x[i], y[i]))
					return false;
			return true;
		}
		if (Type.typeof(a) == TObject || Type.typeof(b) == TObject) {
			if (Type.typeof(a) != TObject || Type.typeof(b) != TObject)
				return false;
			final fa = Reflect.fields(a);
			final fb = Reflect.fields(b);
			if (fa.length != fb.length)
				return false;
			for (f in fa)
				if (!Reflect.hasField(b, f) || !equal(Reflect.field(a, f), Reflect.field(b, f)))
					return false;
			return true;
		}
		return a == b;
	}
}
