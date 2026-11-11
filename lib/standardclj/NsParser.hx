package standardclj;

import standardclj.NodeUtil.*;
import standardclj.NsData;

/** A form of a container, with the platform of the reader conditional it came from. **/
private typedef Slot = {
	final node:Node;
	final platform:Null<String>;
	/** The outermost reader conditional the form came from. **/
	@:optional final origin:Node;
};

/** Where a comment at the end of a line goes: the item that ends on one of the lines `from` to `to`. **/
private typedef Target = {
	final from:Int;
	var to:Int;
	final set:String->Void;
};

/** The comments of a prefix list, which are printed with the first of its requires. **/
private typedef PrefixList = {
	final above:Null<Array<String>>;
	var after:Null<String>;
	var applied:Bool;
};

private typedef RequireEntry = {
	final data:Require;
	final prefixList:Null<PrefixList>;
};

/**
	Extracts the data of an ns form from the syntax tree.

	The ns form is found in the tree and walked section by section. Reader
	conditionals are expanded into their forms with the platform each one
	applies to (see `slots`). Comments and `#_` discards follow these rules:

	- one that starts its line is a comment above the next item
	- one after an item on the same line belongs to the nearest item to its left
**/
class NsParser {
	/**
		Searches for a `#_ :standard-clj/ignore-file`, stopping when we reach
		the first (ns) form.
	**/
	public static function lookForIgnoreFile(nodes:Array<Node>):Bool {
		for (node in nodes) {
			if (node.name == "discard") {
				if (discardsIgnoreFile(node))
					return true;
			} else if (isNs(node)) {
				return false;
			}
		}
		return false;
	}

	// #_ :standard-clj/ignore-file or #_ {:standard-clj/ignore-file true}
	static function discardsIgnoreFile(discard:Node):Bool {
		final form = singleBody(discard);
		if (isStandardCljIgnoreFileKeyword(form))
			return true;
		if (form != null && form.name == "braces") {
			final forms = bodyOf(form).filter(n -> !isGap(n));
			return forms.length >= 2 && isStandardCljIgnoreFileKeyword(forms[0]) && isToken(forms[1]) && forms[1].text == "true";
		}
		return false;
	}

	/**
		Extracts namespace information from a flat array of nodes (see
		`Node.flatten`), the first of which is the root. Returns a data
		structure of the ns form that can be used to "print from scratch".
	**/
	public static function parse(nodes:Array<Node>):Ns {
		return new NsParser(nodes).run();
	}

	// -------------------------------------------------------------------------
	// Tree helpers

	static function isGap(n:Node):Bool {
		return isWhitespace(n) || isTrivia(n) || n.name == "error";
	}

	static function isTrivia(n:Node):Bool {
		return isComment(n) || isReaderComment(n);
	}

	static function isCollection(n:Node):Bool {
		return n.name == "parens" || n.name == "brackets" || n.name == "braces";
	}

	static function isReaderConditional(n:Node):Bool {
		return n.name == "parens" && StringTools.startsWith(n.children[0].text, "#?");
	}

	/** The children of the `.body` of a compound node. **/
	static function bodyOf(n:Node):Array<Node> {
		for (c in n.children)
			if (c.name == ".body")
				return c.children;
		return [];
	}

	/** The form inside a `.body` node, e.g. what a `discard` discards. **/
	static function singleBody(n:Node):Null<Node> {
		for (c in n.children)
			if (c.name == ".body")
				return c.children[0];
		return null;
	}

	static function lastDescendant(n:Node):Node {
		var last = n;
		while (last.children != null && last.children.length > 0)
			last = last.children[last.children.length - 1];
		return last;
	}

	static function parseJavaPackageWithClass(s:String):{pkg:String, className:String} {
		final lastDotIdx = s.lastIndexOf(".");
		if (lastDotIdx == -1)
			return {pkg: "", className: s};
		return {pkg: s.substr(0, lastDotIdx), className: s.substr(lastDotIdx + 1)};
	}

	/** The array behind a nullable array field, created when absent. **/
	static inline function lazy<T>(a:Null<Array<T>>, create:Array<T>->Void):Array<T> {
		if (a != null)
			return a;
		final fresh:Array<T> = [];
		create(fresh);
		return fresh;
	}

	// -------------------------------------------------------------------------
	// State

	final root:Null<Node>;
	// the line of each node, counting the newline nodes before it
	final lineOf:Map<Int, Int> = [];
	// nodes that come directly after a newline
	final startsLine:Map<Int, Bool> = [];
	final result = new Ns();

	final importKeys:Array<String> = [];
	final importsByPackage:Map<String, Import> = [];
	final requires:Array<RequireEntry> = [];

	// comments above the next item
	var pending:Array<String> = [];
	// the line of an own-line discard that a comment on the same line merges onto
	var pendingDiscardLine = -1;
	// metadata strings above the next libspec
	var metadata:Array<String> = [];
	// where the next comment at the end of a line goes
	var target:Null<Target> = null;
	// the last comment recorded at the end of a line, so that more on the line merge with it
	var lastComment = "";
	var lastCommentLine = -1;
	var nsEndLine = -1;
	var afterNsForm = false;

	function new(nodes:Array<Node>) {
		root = nodes.length > 0 ? nodes[0] : null;
		var line = 0;
		for (i in 0...nodes.length) {
			final node = nodes[i];
			lineOf[node.id] = line;
			if (i > 0 && isNewline(nodes[i - 1]))
				startsLine[node.id] = true;
			if (isNewline(node))
				line++;
		}
	}

	function line(n:Node):Int {
		return lineOf[n.id];
	}

	// -------------------------------------------------------------------------
	// Slots

	/**
		The forms and trivia of a compound node, in order. A reader conditional
		is replaced by its forms, each with the platform keyword before it; a
		splicing one by the forms of its collections.
	**/
	function slots(container:Node, platform:Null<String>):Array<Slot> {
		final out:Array<Slot> = [];
		for (c in bodyOf(container))
			if (!isWhitespace(c) && c.name != "error")
				addSlot(c, platform, false, out);
		return out;
	}

	function addSlot(n:Node, platform:Null<String>, splice:Bool, out:Array<Slot>):Void {
		if (isReaderConditional(n))
			expandReaderConditional(n, out);
		else if (splice && (n.name == "parens" || n.name == "brackets"))
			for (s in slots(n, platform))
				out.push(s);
		else
			out.push({node: n, platform: platform});
	}

	function expandReaderConditional(rc:Node, out:Array<Slot>):Void {
		final splice = rc.children[0].text == "#?@(";
		final first = out.length;
		var platform:Null<String> = null;
		for (c in bodyOf(rc)) {
			if (isWhitespace(c) || c.name == "error")
				continue;
			if (isToken(c) && isKeyword(c))
				platform = c.text;
			else if (isTrivia(c))
				out.push({node: c, platform: platform});
			else
				addSlot(c, platform, splice, out);
		}
		for (i in first...out.length)
			out[i] = {node: out[i].node, platform: out[i].platform, origin: rc};
	}

	/** Records the trivia from `i` on and returns the index of the next form. **/
	function skipTrivia(ss:Array<Slot>, i:Int):Int {
		while (i < ss.length && isTrivia(ss[i].node)) {
			trivia(ss[i].node);
			i++;
		}
		return i;
	}

	/** The index of the next form, leaving the trivia for later. **/
	static function peekForm(ss:Array<Slot>, i:Int):Int {
		while (i < ss.length && isTrivia(ss[i].node))
			i++;
		return i;
	}

	/** Records all the trivia inside `n`. **/
	function drainTrivia(n:Node):Void {
		if (isTrivia(n)) {
			trivia(n);
		} else if (n.children != null) {
			for (c in n.children)
				drainTrivia(c);
		}
	}

	/** Calls `f` with each token inside the collection `form`, however deep. **/
	function eachToken(form:Node, platform:Null<String>, f:Node->Null<String>->Void):Void {
		if (!isCollection(form))
			return;
		final ss = slots(form, platform);
		for (s in ss) {
			if (isTrivia(s.node))
				trivia(s.node);
			else if (isToken(s.node))
				f(s.node, s.platform);
			else
				eachToken(s.node, s.platform, f);
		}
	}

	/** Pairs up the tokens inside `form`, as in `{print core-print, get g}`. Returns false if a token is left over. **/
	function eachPair(form:Node, platform:Null<String>, f:Node->Node->Null<String>->Void):Bool {
		var from:Null<Node> = null;
		eachToken(form, platform, (n, p) -> {
			if (from == null) {
				from = n;
			} else {
				f(from, n, p);
				from = null;
			}
		});
		return from == null;
	}

	// -------------------------------------------------------------------------
	// Comments

	function takePending():Null<Array<String>> {
		if (pending.length == 0)
			return null;
		final taken = pending;
		pending = [];
		return taken;
	}

	function takeMetadata():Null<Array<String>> {
		if (metadata.length == 0)
			return null;
		final taken = metadata;
		metadata = [];
		return taken;
	}

	function targetLine(n:Node, set:String->Void):Void {
		final l = line(n);
		target = {from: l, to: l, set: set};
	}

	// a comment after the closing bracket of a multi-line libspec or package list belongs to it
	function extendTargetToEndOf(form:Node):Void {
		if (target != null)
			target.to = Std.int(Math.max(target.to, line(lastDescendant(form))));
	}

	function trivia(n:Node):Void {
		final isDiscard = isReaderComment(n);
		final text = isDiscard ? textOf(n) : n.text;
		final l = line(n);

		if (startsLine.exists(n.id)) {
			pending.push(text);
			if (isDiscard)
				pendingDiscardLine = l;
			return;
		}

		// a comment after a discard that starts its line goes with the discard
		if (!isDiscard && pendingDiscardLine == l && pending.length > 0) {
			pending[pending.length - 1] += " " + text;
			pendingDiscardLine = -1;
			return;
		}

		var comment = text;
		if (lastCommentLine == l && lastComment != "")
			comment = lastComment + " " + comment;
		lastComment = comment;
		if (target != null && l >= target.from && l <= target.to) {
			target.set(comment);
			lastCommentLine = l;
		}
		if (afterNsForm && lastCommentLine == l)
			result.commentOutsideNsForm = comment;
	}

	// -------------------------------------------------------------------------
	// The ns form

	function run():Ns {
		if (root == null || root.children == null)
			return result;
		for (i in 0...root.children.length) {
			final form = root.children[i];
			if (isNsForm(form)) {
				nsForm(form);
				trailingComments(root.children, i + 1);
				return finish();
			}
		}
		return result;
	}

	/** Is this top-level node the `(ns ...)` form? **/
	public static function isNsForm(form:Node):Bool {
		return form.name == "parens" && form.children[0].text == "(" && headText(form) == "ns";
	}

	// the text of the first form, which a discard or a comment must not come before
	static function headText(form:Node):Null<String> {
		for (c in bodyOf(form)) {
			if (!isWhitespace(c) && !isComment(c))
				return isToken(c) ? c.text : null;
		}
		return null;
	}

	// comments after the closing paren of the ns form, on the same line
	function trailingComments(siblings:Array<Node>, from:Int):Void {
		afterNsForm = true;
		for (i in from...siblings.length) {
			final n = siblings[i];
			if (isNewline(n) || !isGap(n))
				return;
			if (isTrivia(n))
				trivia(n);
		}
	}

	function nsForm(form:Node):Void {
		nsEndLine = line(lastDescendant(form));
		final ss = slots(form, null);
		var i = peekForm(ss, 0) + 1;
		var beyondSections = false;
		var hasSymbol = false;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final s = ss[i++];
			final n = s.node;
			switch n.name {
				case "token" if (!hasSymbol):
					result.nsSymbol = n.text;
					hasSymbol = true;
				case "meta" if (!hasSymbol):
					nsMetadata(n);
					final body = singleBody(n);
					if (body != null && isToken(body)) {
						result.nsSymbol = body.text;
						hasSymbol = true;
					}
				case "string" if (!beyondSections && isString(n)):
					result.docstring = stringText(n);
				case "braces" if (!beyondSections && n.children[0].text == "{"):
					nsMetadataMap(n);
				case "brackets" | "parens":
					beyondSections = section(n, s.platform) || beyondSections;
				default:
			}
		}
	}

	/** Reads one section of the ns form; returns whether it is one we know. **/
	function section(n:Node, platform:Null<String>):Bool {
		switch headText(n) {
			case ":refer-clojure" | "refer-clojure":
				referClojureSection(n, platform);
			case ":require" | "require":
				requireSection(n, platform);
			case ":import" | "import":
				importSection(n, platform);
			case ":require-macros":
				requireMacrosSection(n, platform);
			case ":gen-class":
				genClassSection(n, platform);
			case ":use" | "use":
				throw new haxe.Exception("Standard Clojure Style does not support :use inside of the ns form. Please refactor with :require as appropriate.");
			default:
				drainTrivia(n);
				return false;
		}
		return true;
	}

	/** Starts a section: records the trivia before its keyword and returns the slots and the index after the keyword. **/
	function openSection(n:Node, platform:Null<String>):{ss:Array<Slot>, head:Node, next:Int} {
		final ss = slots(n, platform);
		final i = skipTrivia(ss, 0);
		return {ss: ss, head: ss[i].node, next: i + 1};
	}

	// -------------------------------------------------------------------------
	// ns metadata

	function addNsMetadata(key:String, value:String):Void {
		lazy(result.nsMetadata, a -> result.nsMetadata = a).push(new NsMetadata(key, value));
	}

	// ^:shorthand ^{:key value} ^Tag
	function nsMetadata(meta:Node):Void {
		for (c in meta.children) {
			if (c.name != ".meta" || c.children.length == 0)
				continue;
			final form = c.children[0];
			if (isToken(form))
				addNsMetadata(form.text, "true");
			else if (form.name == "braces")
				nsMetadataMap(form);
		}
	}

	function nsMetadataMap(map:Node):Void {
		final forms = bodyOf(map).filter(n -> !isGap(n));
		for (i in 0...forms.length >> 1)
			addNsMetadata(textOf(forms[2 * i]), textOf(forms[2 * i + 1]));
	}

	// -------------------------------------------------------------------------
	// :refer-clojure

	function referClojureSection(n:Node, platform:Null<String>):Void {
		final sec = openSection(n, platform);
		final ss = sec.ss;
		final above = takePending();
		if (above != null)
			result.referClojureCommentsAbove = above;
		// NOTE: a comment at the end of any line of the ns form after the keyword goes
		// after the form, unless another section starts first
		target = {
			from: line(sec.head),
			to: nsEndLine,
			set: c -> {
				if (result.referClojure == null)
					result.referClojureCommentAfter = c;
				else
					result.referClojureCommentAfterForm = c;
			}
		};

		var i = sec.next;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final key = ss[i++].node;
			if (!isToken(key) || (key.text != ":exclude" && key.text != ":only" && key.text != ":rename"))
				continue;
			if (result.referClojure == null)
				result.referClojure = new ReferClojure();
			final rc = result.referClojure;
			// the array exists as soon as the key does, even if it ends up empty
			final symbols = switch key.text {
				case ":exclude": lazy(rc.exclude, a -> rc.exclude = a);
				case ":only": lazy(rc.only, a -> rc.only = a);
				default: null;
			};
			final renames = key.text == ":rename" ? lazy(rc.rename, a -> rc.rename = a) : null;
			i = skipTrivia(ss, i);
			if (i >= ss.length)
				break;
			final value = ss[i++];
			if (renames != null)
				eachPair(value.node, value.platform, (from, to, p) -> renames.push(new Rename(from.text, to.text, p)));
			else
				eachToken(value.node, value.platform, (symbol, p) -> symbols.push(new Symbol(symbol.text, p)));
		}
	}

	// -------------------------------------------------------------------------
	// :require

	function requireSection(n:Node, platform:Null<String>):Void {
		final sec = openSection(n, platform);
		final ss = sec.ss;
		final above = takePending();
		if (above != null)
			result.requireCommentsAbove = above;
		targetLine(sec.head, c -> result.requireCommentAfter = c);

		var i = sec.next;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final s = ss[i++];
			final form = unwrapMetadata(s.node);
			if (form == null)
				continue;
			if (isToken(form)) {
				if (!isKeyword(form))
					newRequire(form.text, form, s.platform);
			} else if (form.name == "brackets" || form.name == "parens") {
				libspec(form, s.platform);
			}
		}
	}

	/** Collects the metadata of a `meta` node for the next libspec and returns the form it is on. **/
	function unwrapMetadata(n:Node):Null<Node> {
		if (n.name != "meta")
			return n;
		for (m in NodeSearch.metadataStrings(n))
			metadata.push(m);
		// comments between the metadata and the libspec are comments above the libspec
		for (c in NodeSearch.metaComments(n))
			pending.push(c);
		return singleBody(n);
	}

	function newRequire(symbol:String, at:Node, platform:Null<String>):Require {
		final req = new Require(symbol);
		req.metadata = takeMetadata();
		req.commentsAbove = takePending();
		req.platform = platform;
		requires.push({data: req, prefixList: null});
		targetLine(at, c -> req.commentAfter = c);
		return req;
	}

	// [symbol :as alias], ["string" :default Name] or [prefix [symbol] [symbol :as alias]]
	function libspec(form:Node, platform:Null<String>):Void {
		final ss = slots(form, platform);
		var i = skipTrivia(ss, 0);
		if (i >= ss.length)
			return;
		final first = ss[i++];
		final symbol = first.node;
		if (isString(symbol)) {
			final req = newRequire('"' + stringText(symbol) + '"', symbol, first.platform);
			req.symbolIsString = true;
			requireOptions(ss, i, req);
			extendTargetToEndOf(form);
		} else if (isToken(symbol) && !isKeyword(symbol)) {
			if (isPrefixList(ss, i)) {
				prefixList(symbol, ss, i);
			} else {
				requireOptions(ss, i, newRequire(symbol.text, symbol, first.platform));
				extendTargetToEndOf(form);
			}
		}
	}

	// a symbol followed by anything but options
	static function isPrefixList(ss:Array<Slot>, i:Int):Bool {
		i = peekForm(ss, i);
		if (i >= ss.length)
			return false;
		final next = ss[i].node;
		return (isToken(next) && !isKeyword(next)) || next.name == "brackets" || next.name == "parens" || next.name == "meta";
	}

	function prefixList(prefix:Node, ss:Array<Slot>, i:Int):Void {
		final list:PrefixList = {above: takePending(), after: null, applied: false};
		final prefixLine = line(prefix);
		targetLine(prefix, c -> list.after = c);

		// an entry on the line of the prefix leaves the comments there with the prefix list
		function entry(symbol:Node, platform:Null<String>):Require {
			final req = new Require(prefix.text + "." + symbol.text);
			req.metadata = takeMetadata();
			req.platform = platform;
			requires.push({data: req, prefixList: list});
			if (line(symbol) != prefixLine)
				targetLine(symbol, c -> req.commentAfter = c);
			return req;
		}

		while ((i = skipTrivia(ss, i)) < ss.length) {
			final s = ss[i++];
			final form = unwrapMetadata(s.node);
			if (form == null)
				continue;
			if (isToken(form)) {
				if (!isKeyword(form))
					entry(form, s.platform);
			} else if (form.name == "brackets" || form.name == "parens") {
				final spec = slots(form, s.platform);
				var j = skipTrivia(spec, 0);
				if (j < spec.length && isToken(spec[j].node) && !isKeyword(spec[j].node)) {
					requireOptions(spec, j + 1, entry(spec[j].node, spec[j].platform));
					extendTargetToEndOf(form);
				}
			}
		}
	}

	static function symbolExpected(option:String):haxe.Exception {
		return new haxe.Exception(':require $option must be followed by a symbol.');
	}

	// :as, :refer and so on, after the symbol of a libspec
	function requireOptions(ss:Array<Slot>, i:Int, req:Require):Void {
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final key = ss[i++].node;
			if (!isToken(key))
				throw new haxe.Exception(":require options must be keywords.");
			final option = key.text;
			switch option {
				case ":as" | ":as-alias" | ":default" | ":include-macros" | ":refer" | ":refer-macros" | ":rename" | ":exclude":
				default:
					throw new haxe.Exception(':require $option is not a supported option.');
			}
			i = skipTrivia(ss, i);
			final needsSymbol = option == ":as" || option == ":as-alias" || option == ":default";
			if (i >= ss.length) {
				if (needsSymbol)
					throw symbolExpected(option);
				return;
			}
			final value = ss[i++];
			final v = value.node;
			if (needsSymbol && (!isToken(v) || isKeyword(v)))
				throw symbolExpected(option);
			if (option == ":include-macros" && !isBoolean(v))
				throw new haxe.Exception(":require :include-macros must be followed by true or false.");
			if (option == ":refer" && !isCollection(v) && !(isToken(v) && v.text == ":all"))
				throw new haxe.Exception(":require :refer must be followed by :all or a collection.");
			if ((option == ":exclude" || option == ":refer-macros" || option == ":rename") && !isCollection(v))
				throw new haxe.Exception(':require $option must be followed by a collection.');
			switch option {
				case ":as" if (isToken(v)):
					req.alias = v.text;
				case ":as-alias" if (isToken(v)):
					req.asAlias = v.text;
				case ":default" if (isToken(v)):
					req.defaultName = v.text;
				case ":include-macros" if (isBoolean(v)):
					req.includeMacros = v.text == "true";
				case ":refer" if (isToken(v) && v.text == ":all"):
					req.referAll = true;
					req.refer = null;
				case ":refer":
					eachToken(v, value.platform, (symbol, _) -> {
						req.referAll = false;
						lazy(req.refer, a -> req.refer = a).push(new Symbol(symbol.text, null));
					});
				case ":refer-macros":
					for (s in slots(v, value.platform))
						if (isTrivia(s.node))
							trivia(s.node);
						else if (isToken(s.node))
							lazy(req.referMacros, a -> req.referMacros = a).push(s.node.text);
				case ":rename":
					if (!eachPair(v, value.platform, (from, to, p) -> lazy(req.rename, a -> req.rename = a).push(new Rename(from.text, to.text, p))))
						throw new haxe.Exception(":require :rename must be followed by pairs of symbols.");
				case ":exclude":
					final exclude:Array<Symbol> = [];
					req.exclude = exclude;
					eachToken(v, value.platform, (symbol, _) -> exclude.push(new Symbol(symbol.text, null)));
				default:
			}
		}
	}

	// -------------------------------------------------------------------------
	// :import

	function importSection(n:Node, platform:Null<String>):Void {
		final sec = openSection(n, platform);
		final ss = sec.ss;
		final above = takePending();
		if (above != null)
			result.importCommentsAbove = above;
		targetLine(sec.head, c -> result.importCommentAfter = c);

		var i = sec.next;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final s = ss[i++];
			final form = s.node;
			if (isToken(form)) {
				if (isKeyword(form))
					throw new haxe.Exception(":import " + form.text + " must be a class symbol.");
				final parsed = parseJavaPackageWithClass(form.text);
				addImport(parsed.pkg, form, s.platform).classes.push(parsed.className);
			} else if (form.name == "brackets" || form.name == "parens") {
				packageList(form, s.platform);
			}
		}
	}

	// (java.util Date UUID)
	function packageList(form:Node, platform:Null<String>):Void {
		final ss = slots(form, platform);
		var i = skipTrivia(ss, 0);
		if (i >= ss.length || !isToken(ss[i].node))
			return;
		final first = ss[i++];
		final imported = addImport(first.node.text, first.node, first.platform);
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final c = ss[i++].node;
			if (isToken(c))
				imported.classes.push(c.text);
		}
		extendTargetToEndOf(form);
	}

	function addImport(packageName:String, at:Node, platform:Null<String>):Import {
		var imported = importsByPackage.get(packageName);
		if (imported == null) {
			imported = new Import(packageName, []);
			importsByPackage.set(packageName, imported);
			importKeys.push(packageName);
		}
		final above = takePending();
		if (above != null)
			imported.commentsAbove = above;
		if (platform != null)
			imported.platform = platform;
		final i = imported;
		targetLine(at, c -> i.commentAfter = c);
		return imported;
	}

	// -------------------------------------------------------------------------
	// :require-macros

	function requireMacrosSection(n:Node, platform:Null<String>):Void {
		final sec = openSection(n, platform);
		final ss = sec.ss;
		// comments inside the section, above the first libspec, belong to that libspec
		final above = takePending();
		if (above != null)
			result.requireMacrosCommentsAbove = above;
		targetLine(sec.head, c -> result.requireMacrosCommentAfter = c);

		var i = sec.next;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final s = ss[i++];
			final form = unwrapMetadata(s.node);
			if (form == null)
				continue;
			if (isToken(form)) {
				if (!isKeyword(form))
					newRequireMacros(form.text, form, s.platform);
			} else if (form.name == "brackets" || form.name == "parens") {
				requireMacrosLibspec(form, s.platform);
			}
		}
	}

	function newRequireMacros(symbol:String, at:Node, platform:Null<String>):Require {
		if (result.requireMacros == null) {
			result.requireMacros = [];
		}
		final req = new Require(symbol);
		req.metadata = takeMetadata();
		req.commentsAbove = takePending();
		req.platform = platform;
		result.requireMacros.push(req);
		targetLine(at, c -> req.commentAfter = c);
		return req;
	}

	// [symbol :as alias :refer [macro]]
	function requireMacrosLibspec(form:Node, platform:Null<String>):Void {
		final ss = slots(form, platform);
		var i = skipTrivia(ss, 0);
		if (i >= ss.length)
			return;
		final first = ss[i++];
		if (!isToken(first.node) || isKeyword(first.node))
			return;
		final req = newRequireMacros(first.node.text, first.node, first.platform);

		while ((i = skipTrivia(ss, i)) < ss.length) {
			final key = ss[i++].node;
			if (!isToken(key))
				throw new haxe.Exception(":require-macros options must be keywords.");
			if (key.text != ":as" && key.text != ":refer" && key.text != ":rename")
				throw new haxe.Exception(':require-macros ${key.text} is not a supported option.');
			i = skipTrivia(ss, i);
			if (i >= ss.length)
				return;
			final value = ss[i++];
			final v = value.node;
			switch key.text {
				case ":as" if (isToken(v)):
					req.alias = v.text;
				case ":refer" if (isToken(v) && v.text == ":all"):
					req.referAll = true;
					req.refer = null;
				case ":refer" if (isToken(v)):
					req.referAll = false;
					lazy(req.refer, a -> req.refer = a).push(new Symbol(v.text, value.platform));
				case ":refer":
					eachToken(v, value.platform, (symbol, p) -> {
						req.referAll = false;
						lazy(req.refer, a -> req.refer = a).push(new Symbol(symbol.text, p));
					});
				case ":rename":
					eachPair(v, value.platform, (from, to, p) -> lazy(req.rename, a -> req.rename = a).push(new Rename(from.text, to.text, p)));
				default:
			}
		}
	}

	// -------------------------------------------------------------------------
	// :gen-class

	function genClassSection(n:Node, platform:Null<String>):Void {
		final sec = openSection(n, platform);
		final ss = sec.ss;
		final genClass = new NsGenClass();
		result.genClass = genClass;
		genClass.platform = platform;
		genClass.commentsAbove = takePending();
		targetLine(sec.head, c -> genClass.commentAfter = c);

		var i = sec.next;
		while ((i = skipTrivia(ss, i)) < ss.length) {
			final key = ss[i++].node;
			if (!GenClass.isKeyword(key)) {
				i = genClassOther(genClass, key, ss, i);
				continue;
			}
			genClass.isEmpty = false;
			final above = takePending();

			i = skipTrivia(ss, i);
			final value = i < ss.length ? ss[i++] : null;
			final entry = genClassKey(genClass, key.text.substr(1), above, value);
			if (entry == null) {
				// a kind of value this key does not take is kept as it is written
				addOther(genClass, key, value.node, above);
			} else if (value == null) {
				return;
			} else if (entry.hasValue()) {
				// a comment after the value belongs to the key
				final end = line(lastDescendant(value.node));
				target = {from: end, to: end, set: c -> entry.commentAfter = c};
			}
		}
	}

	/**
		Stores the key and its value in `genClass`. Returns the key, or null when
		the value is not a kind that the key takes.
	**/
	function genClassKey(genClass:NsGenClass, name:String, above:Null<Array<String>>, value:Null<Slot>):Null<GenClassKeyBase> {
		switch name {
			case "constructors":
				return genClass.constructors = keyOf(above, value, (v, _) -> isMapLiteral(v.node) ? GenClass.parseConstructors(v.node) : null);
			case "exposes":
				return genClass.exposes = keyOf(above, value, (v, _) -> {
					if (!isMapLiteral(v.node))
						throw new haxe.Exception(":gen-class :exposes must be a map of protected-field names to accessor maps.");
					return GenClass.parseExposes(v.node);
				});
			case "exposes-methods":
				return genClass.exposesMethods = keyOf(above, value, (v, _) -> {
					if (!isMapLiteral(v.node))
						throw new haxe.Exception(":gen-class :exposes-methods must be a map of superclass-method names to exposed names.");
					return GenClass.parseExposesMethods(v.node);
				});
			case "extends":
				return genClass.extendsClass = keyOf(above, value, nameValue.bind(name));
			case "factory":
				return genClass.factory = keyOf(above, value, nameValue.bind(name));
			case "impl-ns":
				return genClass.implNs = keyOf(above, value, nameValue.bind(name));
			case "implements":
				return genClass.implementsInterfaces = keyOf(above, value, (v, _) -> {
					if (!isCollection(v.node))
						return null;
					final symbols:Array<Symbol> = [];
					collectImplements(v.node, v.platform, symbols);
					return symbols;
				});
			case "init":
				return genClass.init = keyOf(above, value, nameValue.bind(name));
			case "load-impl-ns":
				return genClass.loadImplNs = keyOf(above, value, booleanValue);
			case "main":
				return genClass.main = keyOf(above, value, booleanValue);
			case "methods":
				return genClass.methods = keyOf(above, value, (v, _) -> {
					if (!isVectorLiteral(v.node))
						throw new haxe.Exception(":gen-class :methods must be a vector of method vectors.");
					return GenClass.parseMethods(v.node);
				});
			case "name":
				return genClass.name = keyOf(above, value, nameValue.bind(name));
			case "post-init":
				return genClass.postInit = keyOf(above, value, nameValue.bind(name));
			case "prefix":
				return genClass.prefix = keyOf(above, value, (v, _) -> isString(v.node) ? GenClass.symbolText(v.node) : null);
			case "state":
				return genClass.state = keyOf(above, value, nameValue.bind(name));
			default:
				return null;
		}
	}

	static function keyOf<T>(above:Null<Array<String>>, value:Null<Slot>, parse:(Slot, GenClassKey<T>) -> Null<T>):Null<GenClassKey<T>> {
		final key = new GenClassKey<T>();
		key.commentsAbove = above;
		if (value != null) {
			key.value = parse(value, key);
			if (key.value == null)
				return null;
		}
		return key;
	}

	static function booleanValue(v:Slot, _):Null<Bool> {
		return isBoolean(v.node) ? v.node.text == "true" : null;
	}

	// a symbol or string, possibly with metadata
	static function nameValue(name:String, v:Slot, key:GenClassKey<String>):Null<String> {
		if (v.node.name == "meta") {
			final form = GenClass.splitMetadataForm(v.node);
			final symbol = GenClass.symbolText(form.bodyNode);
			if (symbol == null || symbol == "")
				throw new haxe.Exception(":gen-class :" + name + " must be a symbol or string.");
			if (form.metadata != null && form.metadata != "")
				key.metadata = form.metadata;
			return symbol;
		}
		return isToken(v.node) || isString(v.node) ? GenClass.symbolText(v.node) : null;
	}

	// a key we do not know, or a form that is not a key: kept as it is written
	function genClassOther(genClass:NsGenClass, first:Node, ss:Array<Slot>, i:Int):Int {
		genClass.isEmpty = false;
		final above = takePending();
		var value:Null<Node> = null;
		if (isToken(first) && isKeyword(first)) {
			final next = skipTrivia(ss, i);
			if (next < ss.length && !(isToken(ss[next].node) && isKeyword(ss[next].node))) {
				final origin = ss[next].origin;
				value = origin ?? ss[next].node;
				i = next + 1;
				// a reader conditional value is kept whole, not as a form per platform
				while (origin != null && i < ss.length && ss[i].origin == origin)
					i++;
			}
		}
		addOther(genClass, first, value, above);
		return i;
	}

	function addOther(genClass:NsGenClass, key:Node, value:Null<Node>, above:Null<Array<String>>):Void {
		final item = new GenClassOther(shape(key, 0) + (value == null ? "" : " " + shape(value, textOf(key).length + 1)));
		item.commentsAbove = above;
		lazy(genClass.other, a -> genClass.other = a).push(item);
		final end = line(lastDescendant(value == null ? key : value));
		target = {from: end, to: end, set: c -> item.commentAfter = c};
	}

	/**
		A form with its elements separated by spaces. Commas and comments inside it
		are kept, and a comment is followed by a line break. Lines after the first
		are indented from column 0, where `col` is the column of the form's first line.
	**/
	static function shape(n:Node, col:Int):String {
		if (isReaderComment(n)) {
			final body = singleBody(n);
			return "#_" + (body == null ? "" : shape(body, col + 2));
		}
		if (!isCollection(n))
			return textOf(n);
		final open = n.children[0].text;
		final last = n.children[n.children.length - 1];
		final close = last.name == ".close" ? last.text : "";
		final indent = "\n" + [for (_ in 0...col + open.length) " "].join("");
		var out = open;
		var hasElement = false;
		var breakBefore = false;
		var comma = false;
		for (c in bodyOf(n)) {
			if (isWhitespace(c)) {
				if (isComma(c) && !comma && hasElement) {
					comma = true;
					out += ",";
				}
				continue;
			}
			if (c.name == "error")
				continue;
			comma = false;
			if (isComment(c)) {
				out += (hasElement ? " " : "") + c.text;
				breakBefore = true;
				hasElement = true;
				continue;
			}
			if (hasElement)
				out += breakBefore ? indent : " ";
			final lineStart = out.lastIndexOf("\n");
			final c2 = lineStart < 0 ? col + out.length : out.length - lineStart - 1;
			out += shape(c, c2);
			hasElement = true;
			breakBefore = false;
		}
		// a closing paren after a comment would be commented out
		return out + (breakBefore ? indent : "") + close;
	}

	function collectImplements(collection:Node, platform:Null<String>, symbols:Array<Symbol>):Void {
		for (s in slots(collection, platform)) {
			final n = s.node;
			if (isTrivia(n)) {
				trivia(n);
			} else if (isCollection(n)) {
				collectImplements(n, s.platform, symbols);
			} else if (isToken(n) || isString(n) || n.name == "meta") {
				final symbol = GenClass.symbolText(n);
				if (symbol == null || symbol == "")
					throw new haxe.Exception(":gen-class :implements values must be symbols or strings.");
				symbols.push(new Symbol(symbol, s.platform));
			}
		}
	}

	// -------------------------------------------------------------------------
	// Finishing

	function finish():Ns {
		final referClojure = result.referClojure;
		if (referClojure != null) {
			sortSymbols(referClojure.exclude);
			sortSymbols(referClojure.only);
			sortRenames(referClojure.rename);
		}

		final implementsInterfaces = result.genClass == null ? null : result.genClass.implementsInterfaces;
		if (implementsInterfaces != null)
			sortSymbols(implementsInterfaces.value);

		final requireMacros = result.requireMacros;
		if (requireMacros != null) {
			NsSort.sortArray(requireMacros, NsSort.compareSymbolsThenPlatform);
			for (rm in requireMacros)
				sortSymbols(rm.refer);
		}

		finishRequires();
		finishImports();
		finishNsMetadata();
		return result;
	}

	static function sortSymbols(symbols:Null<Array<Symbol>>):Void {
		if (symbols != null)
			NsSort.sortArray(symbols, NsSort.compareSymbolsThenPlatform);
	}

	static function sortRenames(renames:Null<Array<Rename>>):Void {
		if (renames != null)
			NsSort.sortArray(renames, NsSort.compareFromSymbol);
	}

	function finishRequires():Void {
		if (requires.length == 0)
			return;
		NsSort.sortArray(requires, (a, b) -> NsSort.compareSymbolsThenPlatform(a.data, b.data));
		for (entry in requires) {
			final req = entry.data;
			// the comments of a prefix list go with the first of its requires
			final list = entry.prefixList;
			if (list != null && !list.applied) {
				list.applied = true;
				if (list.above != null)
					req.commentsAbove = list.above;
				if (list.after != null)
					req.commentAfter = list.after;
			}
			sortSymbols(req.refer);
			sortSymbols(req.exclude);
			sortRenames(req.rename);
		}
		result.requires = [for (entry in requires) entry.data];
	}

	function finishImports():Void {
		if (importKeys.length == 0)
			return;
		final imports:Array<Import> = [];
		result.imports = imports;

		for (packageName in importKeys) {
			final obj = importsByPackage.get(packageName);
			final sortedClasses = obj.classes;
			NsSort.sortArray(sortedClasses, NsSort.cmpStr);

			// classes in the default package are printed as bare symbols,
			// so each one becomes its own import entry
			if (packageName == "") {
				final numClasses = sortedClasses.length;
				for (classIdx in 0...numClasses) {
					final imported = new Import("", [sortedClasses[classIdx]]);
					if (classIdx == 0)
						imported.commentsAbove = obj.commentsAbove;
					if (classIdx == numClasses - 1)
						imported.commentAfter = obj.commentAfter;
					imported.platform = obj.platform;
					imports.push(imported);
				}
			} else {
				imports.push(obj);
			}
		}

		NsSort.sortArray(imports, NsSort.compareImports);
	}

	// merges the keys of the ns metadata: the last value of a key wins, at its own position
	function finishNsMetadata():Void {
		final nsMetadata = result.nsMetadata;
		if (nsMetadata == null || nsMetadata.length < 2)
			return;
		final lastValues:Map<String, String> = [];
		for (item in nsMetadata)
			lastValues[item.key] = item.value;
		final merged:Array<NsMetadata> = [];
		var i = nsMetadata.length - 1;
		while (i >= 0) {
			final key = nsMetadata[i].key;
			final value = lastValues[key];
			if (value != null && value != "") {
				lastValues.remove(key);
				merged.push(new NsMetadata(key, value));
			}
			i--;
		}
		merged.reverse();
		result.nsMetadata = merged;
	}
}
