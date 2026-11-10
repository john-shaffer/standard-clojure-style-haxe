package standardclj;

/**
	Predicates and accessors over flat lists of nodes (see `Node.flatten`).
	All predicates accept null and return false for it.
**/
class NodeUtil {
	static inline function isText(n:Null<Node>, text:String):Bool {
		return n != null && n.text == text;
	}

	static inline function isOpen(n:Null<Node>, text:String):Bool {
		return n != null && n.name == ".open" && n.text == text;
	}

	public static function hasText(n:Null<Node>):Bool {
		return n != null && n.hasText();
	}

	/** Text that does not start with a space. **/
	public static function hasNonBlankText(n:Null<Node>):Bool {
		return hasText(n) && n.text.charAt(0) != " ";
	}

	public static function hasTextAndNotWhitespace(n:Null<Node>):Bool {
		return hasText(n) && !isWhitespace(n);
	}

	// -------------------------------------------------------------------------
	// ns keywords. Most also match the bare symbol, as in `(ns foo (require x))`.

	public static function isNs(n:Null<Node>):Bool {
		return n != null && n.name == "token" && n.text == "ns";
	}

	public static function isUse(n:Null<Node>):Bool {
		return isText(n, ":use") || isText(n, "use");
	}

	public static function isRequire(n:Null<Node>):Bool {
		return isText(n, ":require") || isText(n, "require");
	}

	public static function isRequireMacrosKeyword(n:Null<Node>):Bool {
		return isText(n, ":require-macros");
	}

	public static function isReferClojure(n:Null<Node>):Bool {
		return isText(n, ":refer-clojure") || isText(n, "refer-clojure");
	}

	public static function isExcludeKeyword(n:Null<Node>):Bool {
		return isText(n, ":exclude");
	}

	public static function isOnlyKeyword(n:Null<Node>):Bool {
		return isText(n, ":only");
	}

	public static function isRenameKeyword(n:Null<Node>):Bool {
		return isText(n, ":rename");
	}

	public static function isAsKeyword(n:Null<Node>):Bool {
		return isText(n, ":as");
	}

	public static function isAsAliasKeyword(n:Null<Node>):Bool {
		return isText(n, ":as-alias");
	}

	public static function isReferKeyword(n:Null<Node>):Bool {
		return isText(n, ":refer");
	}

	public static function isDefaultKeyword(n:Null<Node>):Bool {
		return isText(n, ":default");
	}

	public static function isReferMacrosKeyword(n:Null<Node>):Bool {
		return isText(n, ":refer-macros");
	}

	public static function isIncludeMacros(n:Null<Node>):Bool {
		return isText(n, ":include-macros");
	}

	public static function isBoolean(n:Null<Node>):Bool {
		return isText(n, "true") || isText(n, "false");
	}

	public static function isAll(n:Null<Node>):Bool {
		return isText(n, ":all");
	}

	public static function isKeyword(n:Null<Node>):Bool {
		return n != null && n.text != null && StringTools.startsWith(n.text, ":");
	}

	public static function isImport(n:Null<Node>):Bool {
		return isText(n, ":import") || isText(n, "import");
	}

	// -------------------------------------------------------------------------
	// Whitespace, comments, discards

	public static function isNewline(n:Null<Node>):Bool {
		return n != null && n.name == "whitespace" && n.text != null && n.text.indexOf("\n") >= 0;
	}

	public static function isWhitespace(n:Null<Node>):Bool {
		return n != null && n.name == "whitespace";
	}

	public static function isComma(n:Null<Node>):Bool {
		return n != null && n.name == "whitespace" && n.text.indexOf(",") >= 0;
	}

	public static function isComment(n:Null<Node>):Bool {
		return n != null && n.name == "comment";
	}

	/** A `discard` node, the whole `#_ form`. **/
	public static function isReaderComment(n:Null<Node>):Bool {
		return n != null && n.name == "discard";
	}

	/** The `#_` marker inside a `discard` node. **/
	public static function isDiscardMarker(n:Null<Node>):Bool {
		return n != null && n.name == "marker" && n.text == "#_";
	}

	public static function isStandardCljIgnoreKeyword(n:Null<Node>):Bool {
		return n != null && n.name == "token" && n.text == ":standard-clj/ignore";
	}

	public static function isStandardCljIgnoreFileKeyword(n:Null<Node>):Bool {
		return n != null && n.name == "token" && n.text == ":standard-clj/ignore-file";
	}

	// -------------------------------------------------------------------------
	// Openers and closers

	public static function isParenOpener(n:Null<Node>):Bool {
		if (n == null || n.name != ".open")
			return false;
		return switch n.text {
			case "(" | "[" | "{" | "#{" | "#(" | "#?(" | "#?@(":
				true;
			default:
				isNamespacedMapOpener(n);
		}
	}

	public static function isParenCloser(n:Null<Node>):Bool {
		return n != null && n.name == ".close" && (n.text == ")" || n.text == "]" || n.text == "}");
	}

	public static function isMapLiteralOpener(n:Null<Node>):Bool {
		return isOpen(n, "{");
	}

	public static function isVectorLiteralOpener(n:Null<Node>):Bool {
		return isOpen(n, "[");
	}

	public static function isSingleParenOpener(n:Null<Node>):Bool {
		return isOpen(n, "(");
	}

	public static function isAnonFnOpener(n:Null<Node>):Bool {
		return isOpen(n, "#(");
	}

	public static function isSetLiteralOpener(n:Null<Node>):Bool {
		return isOpen(n, "#{");
	}

	public static function isNamespacedMapOpener(n:Null<Node>):Bool {
		return n != null && n.name == ".open" && StringTools.startsWith(n.text, "#:") && StringTools.endsWith(n.text, "{");
	}

	public static function isReaderConditionalOpener(n:Null<Node>):Bool {
		return isOpen(n, "#?(") || isOpen(n, "#?@(");
	}

	public static function isMetaMarker(n:Null<Node>):Bool {
		return n != null && n.name == ".marker" && (n.text == "^" || n.text == "#^");
	}

	public static function isStringOpener(n:Null<Node>):Bool {
		return isOpen(n, "\"") || isOpen(n, "#?\"");
	}

	public static function isStringCloser(n:Null<Node>):Bool {
		return n != null && n.name == ".close" && n.text == "\"";
	}

	// -------------------------------------------------------------------------
	// Compound nodes

	public static function isToken(n:Null<Node>):Bool {
		return n != null && n.name == "token";
	}

	public static function isTag(n:Null<Node>):Bool {
		return n != null && n.name == ".tag";
	}

	/** A `string` node with `.open`, optional `.body` and `.close` children. **/
	public static function isString(n:Null<Node>):Bool {
		if (n == null || n.name != "string" || n.children == null)
			return false;
		final c = n.children;
		if (c.length == 2)
			return c[0].name == ".open" && c[1].name == ".close";
		return c.length == 3 && c[1].name == ".body";
	}

	/** The text between the quotes of a string node. **/
	public static function stringText(n:Node):String {
		return n.children.length == 2 ? "" : n.children[1].text;
	}

	public static function isMapLiteral(n:Null<Node>):Bool {
		return isCollection(n, "braces", "{", "}");
	}

	public static function isVectorLiteral(n:Null<Node>):Bool {
		return isCollection(n, "brackets", "[", "]");
	}

	static function isCollection(n:Null<Node>, name:String, open:String, close:String):Bool {
		if (n == null || n.name != name || n.children == null)
			return false;
		final c = n.children;
		final last = c[c.length - 1];
		return c.length >= 2 && isOpen(c[0], open) && last.name == ".close" && last.text == close;
	}

	// -------------------------------------------------------------------------
	// Tree accessors

	/** All the text found within a node, with `#` added for `.tag` nodes. **/
	public static function textOf(root:Node):String {
		final b = new StringBuf();
		root.walk(n -> {
			if (isTag(n))
				b.add("#");
			if (hasText(n))
				b.add(n.text);
		});
		return b.toString();
	}

	/** The last node with text under `root`, or null. **/
	public static function lastNodeWithText(root:Node):Null<Node> {
		var last = null;
		root.walk(n -> {
			if (hasText(n))
				last = n;
		});
		return last;
	}
}
