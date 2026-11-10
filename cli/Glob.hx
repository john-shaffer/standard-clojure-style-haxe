/**
	A small glob matcher supporting `*`, `?`, `[...]`, `**` and `{a,b}`.

	Patterns use `/` as the separator. Like most glob libraries (and
	upstream's tinyglobby), wildcards do not match names that start with a dot.
**/
class Glob {
	/** Expands `{a,b}` alternatives (which may nest) into plain patterns. **/
	public static function expandBraces(pattern:String):Array<String> {
		return expandFrom(pattern, 0);
	}

	static function expandFrom(pattern:String, start:Int):Array<String> {
		var open = -1;
		var i = start;
		while (i < pattern.length) {
			final c = pattern.charAt(i);
			if (c == "\\") {
				i += 2;
				continue;
			}
			if (c == "{") {
				open = i;
				break;
			}
			i++;
		}
		if (open < 0)
			return [pattern];

		// find the matching close brace and the top-level commas
		var depth = 0;
		var close = -1;
		final commas:Array<Int> = [];
		i = open;
		while (i < pattern.length) {
			final c = pattern.charAt(i);
			if (c == "\\") {
				i += 2;
				continue;
			}
			if (c == "{")
				depth++;
			else if (c == "}") {
				depth--;
				if (depth == 0) {
					close = i;
					break;
				}
			} else if (c == "," && depth == 1)
				commas.push(i);
			i++;
		}
		// an unbalanced or comma-less brace is literal
		if (close < 0)
			return [pattern];
		if (commas.length == 0)
			return expandFrom(pattern, open + 1);

		final head = pattern.substring(0, open);
		final tail = pattern.substring(close + 1);
		final bounds = [open].concat(commas).concat([close]);
		final out:Array<String> = [];
		for (k in 0...bounds.length - 1) {
			final alt = pattern.substring(bounds[k] + 1, bounds[k + 1]);
			for (p in expandFrom(head + alt + tail, 0))
				out.push(p);
		}
		return out;
	}

	/** Whether the text contains glob syntax. **/
	public static function hasMagic(s:String):Bool {
		for (c in ["*", "?", "[", "]", "{", "}"])
			if (s.indexOf(c) >= 0)
				return true;
		return false;
	}

	/** Whether a slash-separated path matches the pattern. Expands braces. **/
	public static function matches(pattern:String, path:String):Bool {
		final segs = path.split("/");
		for (p in expandBraces(pattern))
			if (matchSegments(p.split("/"), 0, segs, 0))
				return true;
		return false;
	}

	/** Matches pattern segments (no braces) against path segments. **/
	public static function matchSegments(pat:Array<String>, i:Int, segs:Array<String>, j:Int):Bool {
		if (i == pat.length)
			return j == segs.length;
		if (pat[i] == "**") {
			if (matchSegments(pat, i + 1, segs, j))
				return true;
			return j < segs.length && !isHidden(segs[j]) && matchSegments(pat, i, segs, j + 1);
		}
		return j < segs.length && matchSegment(pat[i], segs[j]) && matchSegments(pat, i + 1, segs, j + 1);
	}

	static function isHidden(name:String):Bool {
		return StringTools.startsWith(name, ".");
	}

	/** Matches one path segment against one pattern segment. **/
	public static function matchSegment(pat:String, name:String):Bool {
		if (isHidden(name) && pat.length > 0 && "*?[".indexOf(pat.charAt(0)) >= 0)
			return false;
		return matchChars(pat, 0, name, 0);
	}

	static function matchChars(p:String, pi:Int, s:String, si:Int):Bool {
		while (pi < p.length) {
			final c = p.charAt(pi);
			switch (c) {
				case "*":
					while (pi < p.length && p.charAt(pi) == "*")
						pi++;
					for (k in si...s.length + 1)
						if (matchChars(p, pi, s, k))
							return true;
					return false;
				case "?":
					if (si >= s.length)
						return false;
					pi++;
					si++;
				case "[":
					final close = p.indexOf("]", pi + 2);
					if (close < 0) {
						if (si >= s.length || s.charAt(si) != "[")
							return false;
						pi++;
						si++;
					} else {
						if (si >= s.length || !classMatches(p.substring(pi + 1, close), s.charAt(si)))
							return false;
						pi = close + 1;
						si++;
					}
				case "\\" if (pi + 1 < p.length):
					if (si >= s.length || s.charAt(si) != p.charAt(pi + 1))
						return false;
					pi += 2;
					si++;
				default:
					if (si >= s.length || s.charAt(si) != c)
						return false;
					pi++;
					si++;
			}
		}
		return si == s.length;
	}

	static function classMatches(spec:String, ch:String):Bool {
		var negate = false;
		if (spec.length > 0 && (spec.charAt(0) == "!" || spec.charAt(0) == "^")) {
			negate = true;
			spec = spec.substr(1);
		}
		var found = false;
		var i = 0;
		while (i < spec.length) {
			if (i + 2 < spec.length && spec.charAt(i + 1) == "-") {
				if (ch >= spec.charAt(i) && ch <= spec.charAt(i + 2))
					found = true;
				i += 3;
			} else {
				if (ch == spec.charAt(i))
					found = true;
				i++;
			}
		}
		return found != negate;
	}
}
