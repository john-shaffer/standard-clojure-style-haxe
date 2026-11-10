package;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import Eno.Case;
import standardclj.Node;
import standardclj.Parser;

/**
	Runs the eno test suites. Usage: `Main <root>... [-- <name filter>]`

	Each root holds the suite directories `test_format`, `test_parse_ns`
	and `test_parser`, in the layout of the upstream test repository.
**/
class Main {
	static var passed = 0;
	static var failed:Array<String> = [];

	static function main() {
		final args = Sys.args();
		final roots = [for (a in args) a];
		final suites:Map<String, Case->Null<String>> = [
			"test_format" => FormatSuite.run,
			"test_parse_ns" => ParseNsSuite.run,
			"test_parser" => parserTest,
		];
		for (root in roots) {
			for (suite => run in suites) {
				final dir = Path.join([root, suite]);
				if (!FileSystem.exists(dir))
					continue;
				final files = FileSystem.readDirectory(dir).filter(f -> StringTools.endsWith(f, ".eno"));
				files.sort(Reflect.compare);
				for (f in files)
					for (c in Eno.parse(f, File.getContent(Path.join([dir, f])))) {
						final label = '$suite/${c.file}: ${c.name}';
						final err = run(c);
						if (err == null)
							passed++;
						else
							failed.push('$label\n$err');
					}
			}
		}
		for (e in FormatSuite.extraChecks(roots))
			failed.push('test_format extra checks\n$e');
		for (f in failed)
			Sys.println('FAIL $f\n');
		Sys.println('${passed} passed, ${failed.length} failed');
		Sys.exit(failed.length == 0 ? 0 : 1);
	}

	static function parserTest(c:Case):Null<String> {
		final out = nodeToString(Parser.parse(c.input), 0);
		return out == c.expected ? null : 'expected:\n${c.expected}\nactual:\n$out';
	}

	// the node tree as in the upstream parser tests; whitespace is skipped
	static function nodeToString(node:Node, indent:Int):String {
		if (node.name == "whitespace")
			return "";
		var out = node.name == "source" ? "" : "\n";
		out += StringTools.lpad("", " ", indent * 2) + '(${node.name} ${node.startIdx}..${node.endIdx}';
		if (node.hasText())
			out += " '" + node.text.split("\n").join("\\n") + "'";
		if (node.children != null)
			for (c in node.children)
				out += nodeToString(c, indent + 1);
		return out + ")";
	}
}
