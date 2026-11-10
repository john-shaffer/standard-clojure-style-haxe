package;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import standardclj.Node;
import standardclj.Standard;

/**
	Mutates the inputs of the eno format cases and checks properties that
	must hold for any input that formats successfully:

	- formatting is idempotent
	- the output has balanced brackets

	Mutations insert a comment line, add an end-of-line comment, or insert a
	blank line, at every line of the input. Usage: `Fuzz <root>...`
**/
class Fuzz {
	static final mutations:Array<{name:String, apply:(lines:Array<String>, i:Int) -> Array<String>}> = [
		{
			name: "blank line before",
			apply: (lines, i) -> lines.slice(0, i).concat([""]).concat(lines.slice(i)),
		},
		{
			name: "comment line before",
			apply: (lines, i) -> lines.slice(0, i).concat([";; fuzz"]).concat(lines.slice(i)),
		},
		{
			name: "end-of-line comment",
			apply: (lines, i) -> lines.slice(0, i).concat([lines[i] + " ;; fuzz"]).concat(lines.slice(i + 1)),
		},
	];

	static var runs = 0;
	static var skipped = 0;
	static final failures:Array<String> = [];

	static function main() {
		for (root in Sys.args()) {
			final dir = Path.join([root, "test_format"]);
			if (!FileSystem.exists(dir))
				continue;
			final files = FileSystem.readDirectory(dir).filter(f -> StringTools.endsWith(f, ".eno"));
			files.sort(Reflect.compare);
			for (f in files)
				for (c in Eno.parse(f, File.getContent(Path.join([dir, f]))))
					fuzzCase(c);
		}
		for (f in failures)
			Sys.println('FAIL $f\n');
		Sys.println('$runs runs, $skipped skipped, ${failures.length} failed');
		Sys.exit(failures.length == 0 ? 0 : 1);
	}

	static function fuzzCase(c:Eno.Case) {
		final base = balance(c.input);
		if (base == null || base.open != base.close || base.strays > 0)
			return;
		final lines = c.input.split("\n");
		for (m in mutations)
			for (i in 0...lines.length) {
				final input = m.apply(lines, i).join("\n");
				final label = '${c.file}: ${c.name} [${m.name}, line $i]\n$input';
				check(label, input);
			}
	}

	static function check(label:String, input:String) {
		runs++;
		final out = switch Standard.format(input) {
			case Success(out, _): out;
			case Failure(_):
				skipped++;
				return;
		};
		final b = balance(out);
		if (b == null || b.open != b.close || b.strays > 0)
			failures.push('$label\n--- unbalanced output:\n$out');
		else
			switch Standard.format(out) {
				case Success(out2, _) if (out2 == out):
				case Success(out2, _):
					failures.push('$label\n--- not idempotent:\n$out\n--- second pass:\n$out2');
				case Failure(reason):
					failures.push('$label\n--- output fails to format: $reason\n$out');
			}
	}

	static function balance(text:String):Null<{open:Int, close:Int, strays:Int}> {
		var open = 0;
		var close = 0;
		var strays = 0;
		Standard.parse(text).walk(n -> {
			switch n.name {
				case ".open": open++;
				case ".close": close++;
				case "error": strays++;
				default:
			}
		});
		return {open: open, close: close, strays: strays};
	}
}
