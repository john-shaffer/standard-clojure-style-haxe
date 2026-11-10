package standardclj;

/**
	A recursive-descent parser for Clojure source text.

	Parsing never fails: input that is not valid Clojure produces `error`
	nodes (stray closers) or unterminated forms (a missing `.close` node).

	Tree shape, by node name:

	- `source`: the root; children are gaps, forms and `error` nodes
	- `.body`, `.close`, `.marker`, `.meta`, `.open`, `.tag`: the parts of a compound form
	- `braces`, `brackets`, `parens`: `.open`, optional `.body`, optional `.close`
	- `comment`, `token`, `whitespace`: terminals with text
	- `discard`: `#_`, then `.body`
	- `meta`: one or more `.marker`/`.meta` pairs, then `.body`
	- `string`: `.open`, optional `.body`, optional `.close`
	- `tagged`: `.tag`, then `.body`
	- `wrap`: `.marker`, then `.body`
**/
class Parser {
	final s:String;
	final len:Int;

	function new(s:String) {
		this.s = s;
		this.len = s.length;
	}

	/** Parses `text` and returns the `source` node. **/
	public static function parse(text:String):Node {
		return new Parser(text).source();
	}

	// -------------------------------------------------------------------------
	// Character classes

	inline function cc(i:Int):Int {
		return i < len ? s.charCodeAt(i) : -1;
	}

	public static function isWhitespace(c:Int):Bool {
		return switch c {
			case 0x20 | 0x2C | 0x0A | 0x0D | 0x09 | 0x0C | 0x0B | 0x1C | 0x1D | 0x1E | 0x1F:
				true;
			case 0x2028 | 0x2029 | 0x1680 | 0x205F | 0x3000:
				true;
			default:
				c >= 0x2000 && c <= 0x200A && c != 0x2007;
		}
	}

	// ( ) [ ] { } " @ ~ ^ ; ` # '
	static function isTokenHead(c:Int):Bool {
		return switch c {
			case 0x28 | 0x29 | 0x5B | 0x5D | 0x7B | 0x7D | 0x22 | 0x40 | 0x7E | 0x5E | 0x3B | 0x60 | 0x23 | 0x27:
				true;
			default:
				false;
		}
	}

	// ( ) [ ] { } " @ ^ ; `
	static function isTokenTail(c:Int):Bool {
		return switch c {
			case 0x28 | 0x29 | 0x5B | 0x5D | 0x7B | 0x7D | 0x22 | 0x40 | 0x5E | 0x3B | 0x60:
				true;
			default:
				false;
		}
	}

	// -------------------------------------------------------------------------
	// Terminals

	function node(name:String, start:Int, end:Int):Node {
		return new Node(name, start, end, s.substring(start, end));
	}

	// the end of the token starting at `q`, or -1
	function tokenAlt(q:Int):Int {
		final c = cc(q);
		if (c < 0)
			return -1;
		if (c == 0x5C) {
			switch cc(q + 1) {
				case 0x28 | 0x29 | 0x5B | 0x5D | 0x7B | 0x7D | 0x22 | 0x40 | 0x5E | 0x3B | 0x60 | 0x2C | 0x20:
					return q + 2;
				default:
			}
		}
		if (isTokenHead(c) || isWhitespace(c))
			return -1;
		var i = q + 1;
		while (i < len) {
			final d = s.charCodeAt(i);
			if (isTokenTail(d) || isWhitespace(d))
				break;
			i++;
		}
		return i;
	}

	function token(pos:Int):Null<Node> {
		var end = -1;
		if (cc(pos) == 0x23 && cc(pos + 1) == 0x23)
			end = tokenAlt(pos + 2);
		if (end < 0)
			end = tokenAlt(pos);
		return end < 0 ? null : node("token", pos, end);
	}

	function whitespace(pos:Int):Node {
		var i = pos;
		while (i < len && isWhitespace(s.charCodeAt(i)))
			i++;
		return node("whitespace", pos, i);
	}

	function comment(pos:Int):Node {
		var i = pos;
		while (i < len && s.charCodeAt(i) != 0x0A)
			i++;
		return node("comment", pos, i);
	}

	// -------------------------------------------------------------------------
	// Compound forms

	// wraps a form in a named node, like `.body` or `.meta`
	static function named(name:String, form:Node):Node {
		return new Node(name, form.startIdx, form.endIdx, null, [form]);
	}

	function gap(pos:Int):Null<Node> {
		final c = cc(pos);
		if (c == 0x3B)
			return comment(pos);
		if (c == 0x23)
			return discard(pos);
		if (c >= 0 && isWhitespace(c))
			return whitespace(pos);
		return null;
	}

	// appends gaps starting at `pos`, returns the new position
	function gaps(into:Array<Node>, pos:Int):Int {
		while (true) {
			final g = gap(pos);
			if (g == null)
				return pos;
			into.push(g);
			pos = g.endIdx;
		}
	}

	function discard(pos:Int):Null<Node> {
		if (cc(pos) != 0x23 || cc(pos + 1) != 0x5F)
			return null;
		final children = [node("marker", pos, pos + 2)];
		final p = gaps(children, pos + 2);
		final body = form(p);
		if (body == null)
			return null;
		children.push(named(".body", body));
		return new Node("discard", pos, body.endIdx, null, children);
	}

	function string(pos:Int):Null<Node> {
		var p = pos;
		if (cc(p) == 0x23)
			p++;
		if (cc(p) != 0x22)
			return null;
		final children = [node(".open", pos, p + 1)];
		p++;
		final bodyStart = p;
		while (p < len) {
			final c = s.charCodeAt(p);
			if (c == 0x5C) {
				if (p + 1 >= len)
					break;
				p += 2;
			} else if (c == 0x22) {
				break;
			} else {
				p++;
			}
		}
		if (p > bodyStart)
			children.push(node(".body", bodyStart, p));
		if (cc(p) == 0x22) {
			children.push(node(".close", p, p + 1));
			p++;
		}
		return new Node("string", pos, p, null, children);
	}

	// the end of the opener of a collection starting at `pos`, or -1
	function openerEnd(name:String, pos:Int):Int {
		switch name {
			case "parens":
				var p = pos;
				if (cc(p) == 0x23) {
					p++;
					if (cc(p) == 0x3F) {
						p++;
						if (cc(p) == 0x40)
							p++;
					} else if (cc(p) == 0x3D) {
						p++;
					}
				}
				return cc(p) == 0x28 ? p + 1 : -1;
			case "brackets":
				return cc(pos) == 0x5B ? pos + 1 : -1;
			default:
				if (cc(pos) == 0x7B)
					return pos + 1;
				if (cc(pos) != 0x23)
					return -1;
				if (cc(pos + 1) == 0x7B)
					return pos + 2;
				if (cc(pos + 1) == 0x3A && cc(pos + 2) == 0x3A && cc(pos + 3) == 0x7B)
					return pos + 4;
				return namespacedMapOpenerEnd(pos);
		}
	}

	// #:alias{ or #::alias{
	function namespacedMapOpenerEnd(pos:Int):Int {
		var p = pos + 1;
		if (cc(p) != 0x3A)
			return -1;
		p++;
		if (cc(p) == 0x3A)
			p++;
		final c = cc(p);
		if (c < 0 || c == 0x3A || isTokenHead(c) || isWhitespace(c))
			return -1;
		p++;
		while (p < len) {
			final d = s.charCodeAt(p);
			if (isTokenTail(d) || isWhitespace(d))
				break;
			p++;
		}
		return cc(p) == 0x7B ? p + 1 : -1;
	}

	function collection(name:String, closer:Int, pos:Int):Null<Node> {
		final openEnd = openerEnd(name, pos);
		if (openEnd < 0)
			return null;
		final children = [node(".open", pos, openEnd)];
		final body:Array<Node> = [];
		var p = openEnd;
		while (p < len) {
			var n = gap(p);
			if (n == null)
				n = form(p);
			if (n == null) {
				if (s.charCodeAt(p) == closer)
					break;
				n = node("error", p, p + 1);
			}
			body.push(n);
			p = n.endIdx;
		}
		if (body.length > 0)
			children.push(new Node(".body", openEnd, p, null, body));
		if (cc(p) == closer) {
			children.push(node(".close", p, p + 1));
			p++;
		}
		return new Node(name, pos, p, null, children);
	}

	function wrap(pos:Int):Null<Node> {
		var markerEnd = -1;
		switch cc(pos) {
			case 0x40 | 0x27 | 0x60:
				markerEnd = pos + 1;
			case 0x7E:
				markerEnd = cc(pos + 1) == 0x40 ? pos + 2 : pos + 1;
			case 0x23:
				if (cc(pos + 1) == 0x27)
					markerEnd = pos + 2;
			default:
		}
		if (markerEnd < 0)
			return null;
		final children = [node(".marker", pos, markerEnd)];
		final p = gaps(children, markerEnd);
		final body = form(p);
		if (body == null)
			return null;
		children.push(named(".body", body));
		return new Node("wrap", pos, body.endIdx, null, children);
	}

	function meta(pos:Int):Null<Node> {
		final children:Array<Node> = [];
		var p = pos;
		var count = 0;
		while (true) {
			var q = p;
			if (cc(q) == 0x23)
				q++;
			if (cc(q) != 0x5E)
				break;
			final iter = [node(".marker", p, q + 1)];
			q = gaps(iter, q + 1);
			final m = form(q);
			if (m == null)
				break;
			iter.push(named(".meta", m));
			q = gaps(iter, m.endIdx);
			for (n in iter)
				children.push(n);
			p = q;
			count++;
		}
		if (count == 0)
			return null;
		final body = form(p);
		if (body == null)
			return null;
		children.push(named(".body", body));
		return new Node("meta", pos, body.endIdx, null, children);
	}

	function tagged(pos:Int):Null<Node> {
		if (cc(pos) != 0x23)
			return null;
		final children:Array<Node> = [];
		var p = gaps(children, pos + 1);
		final tag = token(p);
		if (tag == null)
			return null;
		children.push(named(".tag", tag));
		p = gaps(children, tag.endIdx);
		final body = form(p);
		if (body == null)
			return null;
		children.push(named(".body", body));
		return new Node("tagged", pos, body.endIdx, null, children);
	}

	function form(pos:Int):Null<Node> {
		switch cc(pos) {
			case -1:
				return null;
			case 0x28:
				return collection("parens", 0x29, pos);
			case 0x5B:
				return collection("brackets", 0x5D, pos);
			case 0x7B:
				return collection("braces", 0x7D, pos);
			case 0x22:
				return string(pos);
			case 0x40 | 0x27 | 0x60 | 0x7E:
				return wrap(pos);
			case 0x5E:
				return meta(pos);
			case 0x23:
				// '#' is ambiguous: ##Inf, #"str", #(fn), #?(cond), #{set},
				// #:ns{map}, #'var, #^meta, #tag
				var n = token(pos);
				if (n == null)
					n = string(pos);
				if (n == null)
					n = collection("parens", 0x29, pos);
				if (n == null)
					n = collection("braces", 0x7D, pos);
				if (n == null)
					n = wrap(pos);
				if (n == null)
					n = meta(pos);
				if (n == null)
					n = tagged(pos);
				return n;
			default:
				return token(pos);
		}
	}

	function source():Node {
		final children:Array<Node> = [];
		var p = 0;
		while (p < len) {
			var n = gap(p);
			if (n == null)
				n = form(p);
			if (n == null)
				n = node("error", p, p + 1);
			children.push(n);
			p = n.endIdx;
		}
		return new Node("source", 0, p, null, children);
	}
}
