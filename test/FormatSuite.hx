package;

import haxe.io.Path;
import sys.io.File;
import Eno.Case;
import standardclj.Standard;

/**
	The test_format suite. Each case must format `input` to `expected`,
	be idempotent (formatting `expected` changes nothing) and have balanced
	brackets in `expected`. `extraChecks` holds the checks that are not eno cases.
**/
class FormatSuite {
	// cases to skip entirely, as upstream
	static final ignoreTests = ["Surrounding newlines removed 3", "ambiguous import comment"];

	static final filesByName:Map<String, Array<String>> = [];

	/** Returns null on success, else a failure message. **/
	public static function run(c:Case):Null<String> {
		if (!filesByName.exists(c.name))
			filesByName[c.name] = [];
		filesByName[c.name].push(c.file);
		if (ignoreTests.indexOf(c.name) >= 0)
			return null;

		final errors:Array<String> = [];
		switch Standard.format(c.input) {
			case Success(out, _):
				if (out != c.expected)
					errors.push('expected:\n${c.expected}\nactual:\n$out');
			case Failure(reason):
				errors.push('format failed: $reason');
		}
		switch Standard.format(c.expected) {
			case Success(out, _):
				if (out != c.expected)
					errors.push('not idempotent, formatting the expected output gives:\n$out');
			case Failure(reason):
				errors.push('format of expected failed: $reason');
		}
		final balance = bracketBalance(c.expected);
		if (balance.numOpen != balance.numClose || balance.strayClosers.length > 0)
			errors.push('unbalanced brackets in expected: ${balance.numOpen} open, ${balance.numClose} closed, stray closers: ${balance.strayClosers}');

		// the editor keeps trimming trailing whitespace in these cases
		if (c.name == "Trim trailing whitespace 1" && !StringTools.endsWith(c.input, ")   "))
			errors.push("test case input was trimmed");
		if (c.name == "Trim trailing whitespace 2" && c.input.indexOf("\"aaa\",   \n)(def") < 0)
			errors.push("test case input was trimmed");
		if (c.name == "Surrounding newlines removed additional" && c.input.indexOf("aaa  \n)") < 0)
			errors.push("test case input was trimmed");

		return errors.length == 0 ? null : errors.join("\n");
	}

	/** Checks beyond the eno cases. Call after all cases have run. Returns failure messages. **/
	public static function extraChecks(roots:Array<String>):Array<String> {
		final errors:Array<String> = [];

		final duplicates = [for (name => files in filesByName) if (files.length > 1) '$name (x${files.length}: ${files.join(", ")})'];
		if (duplicates.length > 0)
			errors.push('test_format cases should have unique names: $duplicates');

		for (root in roots) {
			final dir = Path.join([root, "test_format", "line_endings"]);
			if (!sys.FileSystem.exists(dir))
				continue;
			final input = File.getContent(Path.join([dir, "crlf_input.clj"]));
			final output = File.getContent(Path.join([dir, "lf_output.clj"]));
			if (input.indexOf("\r\n") < 0 || output.indexOf("\r\n") >= 0)
				errors.push("crlf test: bad line endings in the test files");
			switch Standard.format(input) {
				case Success(out, _):
					if (out + "\n" != output)
						errors.push('crlf to lf: unexpected output:\n$out');
				case Failure(reason):
					errors.push('crlf to lf: format failed: $reason');
			}
		}

		// a :gen-class key with no recognizable value must be an error, never the text "undefined"
		for (key in ["(ns foo (:gen-class :name))" => ":gen-class :name is missing a value.",
			"(ns foo (:gen-class :prefix))" => ":gen-class :prefix is missing a value.",
			"(ns foo (:gen-class :name foo.Bar :init))" => ":gen-class :init is missing a value."].keyValueIterator()) {
			switch Standard.format(key.key) {
				case Failure(reason):
					if (reason != key.value)
						errors.push('gen-class error for ${key.key}: unexpected reason "$reason"');
				case Success(out, _):
					errors.push('gen-class: ${key.key} should be an error, got:\n$out');
			}
		}

		for (input in [
			'(ns foo (:gen-class :prefix ""))',
			'(ns foo (:gen-class :name "" :extends "" :init "" :post-init "" :factory "" :state "" :impl-ns ""))',
			'(ns foo (:gen-class :implements [""]))',
			'(ns foo (:gen-class :name ^:private ""))'
		]) {
			switch Standard.format(input) {
				case Success(out, _):
					if (out.indexOf("undefined") >= 0 || out.indexOf("null") >= 0)
						errors.push('gen-class output for $input contains undefined or null:\n$out');
				case Failure(reason):
					errors.push('gen-class: $input failed: $reason');
			}
		}

		// brackets inside strings, regex literals, character literals and comments must not count
		final balanced = bracketBalance('(def x "(((") (def y \\() (def z #"[(]") ;; )))\n{:a [1 2]}');
		if (balanced.numOpen != 7 || balanced.numClose != 7 || balanced.strayClosers.length != 0)
			errors.push("bracketBalance: balanced input miscounted");
		final stray = bracketBalance("(def x 1))");
		if (stray.numOpen != 1 || stray.numClose != 1 || stray.strayClosers.join(",") != ")")
			errors.push("bracketBalance: stray closer not found");

		return errors;
	}

	/**
		Counts the brackets of `txt` using the parser, so that brackets in strings,
		regexes, characters and comments are ignored. A missing closer leaves an
		unmatched `.open` node; a stray closer becomes an `error` node.
	**/
	static function bracketBalance(txt:String):{numOpen:Int, numClose:Int, strayClosers:Array<String>} {
		var numOpen = 0;
		var numClose = 0;
		final strayClosers:Array<String> = [];
		for (node in Standard.parse(txt).flatten()) {
			if (node.name == ".open")
				numOpen++;
			else if (node.name == ".close")
				numClose++;
			else if (node.name == "error")
				strayClosers.push(node.text);
		}
		return {numOpen: numOpen, numClose: numClose, strayClosers: strayClosers};
	}
}
