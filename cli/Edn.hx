/**
	A small EDN reader sufficient for config files.

	Maps become anonymous objects (keyword keys lose their colon), vectors,
	lists and sets become arrays, and keywords and symbols become strings.
	Throws a `String` on malformed input.
**/
class Edn {
	final s:String;
	var i = 0;

	function new(s:String) {
		this.s = s;
	}

	public static function parse(text:String):Dynamic {
		final r = new Edn(text);
		r.skip();
		if (r.i >= r.s.length)
			throw "empty input";
		final v = r.read();
		r.skip();
		return v;
	}

	function skip() {
		while (i < s.length) {
			final c = s.charAt(i);
			if (c == " " || c == "\t" || c == "\n" || c == "\r" || c == ",")
				i++;
			else if (c == ";")
				while (i < s.length && s.charAt(i) != "\n")
					i++;
			else if (c == "#" && s.charAt(i + 1) == "_") {
				i += 2;
				skip();
				read();
			} else
				break;
		}
	}

	function isDelimiter(c:String):Bool {
		return c == "" || " \t\n\r,;()[]{}\"".indexOf(c) >= 0;
	}

	function read():Dynamic {
		skip();
		if (i >= s.length)
			throw "unexpected end of input";
		final c = s.charAt(i);
		switch (c) {
			case "{":
				i++;
				final items = readUntil("}");
				if (items.length % 2 != 0)
					throw "map literal must contain an even number of forms";
				final o:Dynamic = {};
				for (k in 0...items.length >> 1) {
					final key = items[2 * k];
					Reflect.setField(o, Std.isOfType(key, String) ? key : Std.string(key), items[2 * k + 1]);
				}
				return o;
			case "[":
				i++;
				return readUntil("]");
			case "(":
				i++;
				return readUntil(")");
			case "#":
				if (s.charAt(i + 1) == "{") {
					i += 2;
					return readUntil("}");
				}
				// a tagged element: ignore the tag
				i++;
				readToken();
				return read();
			case "\"":
				return readString();
			case ")" | "]" | "}":
				throw 'unexpected "$c"';
			default:
				return atom(readToken());
		}
	}

	function readUntil(close:String):Array<Dynamic> {
		final out:Array<Dynamic> = [];
		while (true) {
			skip();
			if (i >= s.length)
				throw 'missing "$close"';
			if (s.charAt(i) == close) {
				i++;
				return out;
			}
			out.push(read());
		}
	}

	function readToken():String {
		final start = i;
		while (i < s.length && !isDelimiter(s.charAt(i)))
			i++;
		return s.substring(start, i);
	}

	function atom(t:String):Dynamic {
		if (t == "nil")
			return null;
		if (t == "true")
			return true;
		if (t == "false")
			return false;
		if (StringTools.startsWith(t, ":"))
			return t.substr(1);
		if (~/^[+-]?[0-9]+$/.match(t))
			return Std.parseInt(t);
		if (~/^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?M?$/.match(t))
			return Std.parseFloat(t);
		return t;
	}

	function readString():String {
		i++;
		final b = new StringBuf();
		while (i < s.length) {
			final c = s.charAt(i++);
			if (c == "\"")
				return b.toString();
			if (c == "\\") {
				final e = s.charAt(i++);
				switch (e) {
					case "n":
						b.add("\n");
					case "t":
						b.add("\t");
					case "r":
						b.add("\r");
					case "u":
						b.addChar(Std.parseInt("0x" + s.substr(i, 4)));
						i += 4;
					default:
						b.add(e);
				}
			} else
				b.add(c);
		}
		throw "unterminated string";
	}
}
