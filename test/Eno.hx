package;

typedef Case = {
	final file:String;
	final name:String;
	final input:String;
	final expected:String;
};

/**
	Reads the subset of the eno format used by the test files:

		# Test name

		--Input
		...
		--Input

		--Expected
		...
		--Expected

	A field value is the lines between the two markers joined with "\n".
**/
class Eno {
	public static function parse(file:String, text:String):Array<Case> {
		final cases:Array<Case> = [];
		final fieldRe = ~/^--\s*(\w+)\s*$/;
		var name:Null<String> = null;
		var input:Null<String> = null;
		var expected:Null<String> = null;
		var field:Null<String> = null;
		var lines:Array<String> = [];
		function flush() {
			if (name != null && input != null && expected != null)
				cases.push({
					file: file,
					name: name,
					input: input,
					expected: expected,
				});
		}
		for (line in text.split("\n")) {
			if (field != null) {
				if (fieldRe.match(line) && fieldRe.matched(1) == field) {
					final value = lines.join("\n");
					if (field == "Input")
						input = value;
					else if (field == "Expected")
						expected = value;
					field = null;
					lines = [];
				} else {
					lines.push(line);
				}
			} else if (fieldRe.match(line)) {
				field = fieldRe.matched(1);
			} else if (StringTools.startsWith(line, "# ")) {
				flush();
				name = StringTools.trim(line.substr(2));
				input = null;
				expected = null;
			}
		}
		flush();
		return cases;
	}
}
