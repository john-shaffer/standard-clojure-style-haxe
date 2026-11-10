package standardclj;

import standardclj.NodeUtil.*;

/**
	Helpers for printing: string utilities and the lookahead functions that
	`NodesFormatter` uses over flat node lists (see `Node.flatten`).
**/
class FormatUtil {
	static final commentOnlyMarkers = ~/^;+$/;
	static final commentWithSpace = ~/^;+ /;
	static final commentWithoutSpace = ~/^(;+)([^ ])/;
	static final leadingWhitespace = ~/^[, ]*\n+ */;
	static final nonWhitespace = ~/\S/;

	public static function crlfToLf(txt:String):String {
		return StringTools.replace(txt, "\r\n", "\n");
	}

	public static function repeatString(text:String, n:Int):String {
		final b = new StringBuf();
		for (_ in 0...n)
			b.add(text);
		return b.toString();
	}

	public static function hasNonWhitespaceChars(s:String):Bool {
		return nonWhitespace.match(s);
	}

	/** Does the line need a space inserted before a comment that is about to be printed on it? **/
	public static function commentNeedsSpaceBefore(lineTxt:String, nodeTxt:String):Bool {
		return StringTools.startsWith(nodeTxt, ";") && lineTxt != "" && !StringTools.endsWith(lineTxt, " ") && !StringTools.endsWith(lineTxt, "(")
			&& !StringTools.endsWith(lineTxt, "[") && !StringTools.endsWith(lineTxt, "{");
	}

	public static function commentNeedsSpaceInside(commentTxt:String):Bool {
		return !commentWithSpace.match(commentTxt) && !commentOnlyMarkers.match(commentTxt);
	}

	/** Inserts a space after the leading semicolons of a comment. **/
	public static function addSpaceInsideComment(commentTxt:String):String {
		return commentWithoutSpace.replace(commentTxt, "$1 $2");
	}

	public static function removeLeadingWhitespace(txt:String):String {
		return StringTools.rtrim(leadingWhitespace.replace(txt, ""));
	}

	static inline function isSpaceOrComma(ch:String):Bool {
		return ch == " " || ch == ",";
	}

	/** Does not remove newlines, since it operates on a single line. **/
	public static function removeTrailingWhitespace(txt:String):String {
		var endIdx = txt.length;
		while (endIdx > 0 && isSpaceOrComma(txt.charAt(endIdx - 1)))
			endIdx--;
		return txt.substr(0, endIdx);
	}

	public static function txtHasCommasAfterNewline(s:String):Bool {
		final lastNewlineIdx = s.lastIndexOf("\n");
		if (lastNewlineIdx == -1)
			return false;
		return s.indexOf(",", lastNewlineIdx) != -1;
	}

	public static function hasCommasAfterNewline(node:Null<Node>):Bool {
		return isWhitespace(node) && txtHasCommasAfterNewline(node.text);
	}

	public static function isNewlineNodeWithCommaOnNextLine(n:Null<Node>):Bool {
		return n != null && isNewline(n) && txtHasCommasAfterNewline(n.text);
	}

	public static function numSpacesAfterNewline(newlineNode:Node):Int {
		return newlineNode.text.length - newlineNode.text.lastIndexOf("\n") - 1;
	}

	/** Are all of the nodes on the next line already slurped up, or whitespace? **/
	public static function areForwardNodesAlreadySlurped(nodes:Array<Node>, idx:Int):Bool {
		final nodesSize = nodes.length;
		var result = true;
		var keepSearching = true;
		while (keepSearching) {
			final node = idx < nodesSize ? nodes[idx] : null;
			if (node == null || isNewline(node)) {
				keepSearching = false;
			} else if (node.text == null || node.wasSlurpedUp || isWhitespace(node)) {
				keepSearching = true;
			} else {
				keepSearching = false;
				result = false;
			}
			idx++;
			if (idx >= nodesSize)
				keepSearching = false;
		}
		return result;
	}

	/**
		Searches forward for closing parens that could be slurped up to the current
		line. Includes whitespace and comment nodes as well.
	**/
	public static function findForwardClosingParens(nodes:Array<Node>, idx:Int):Array<Node> {
		final closers:Array<Node> = [];
		final nodesSize = nodes.length;
		var keepSearching = true;
		while (keepSearching) {
			final node = idx < nodesSize ? nodes[idx] : null;
			if (node == null || isNewlineNodeWithCommaOnNextLine(node)) {
				keepSearching = false;
			} else if (isWhitespace(node) || isParenCloser(node) || isComment(node)) {
				closers.push(node);
			} else {
				keepSearching = false;
			}
			idx++;
			if (idx >= nodesSize)
				keepSearching = false;
		}
		return closers;
	}

	/** Sets `origColIdx` on the nodes of this line, stopping at the next newline node. **/
	public static function recordOriginalColIndexes(nodes:Array<Node>, idx:Int):Void {
		var colIdx = 0;
		if (isNewline(nodes[idx])) {
			colIdx = numSpacesAfterNewline(nodes[idx]);
			idx++;
		}
		while (idx < nodes.length) {
			final node = nodes[idx];
			if (isNewline(node))
				break;
			if (node.hasText()) {
				node.origColIdx = colIdx;
				colIdx += node.text.length;
			} else if (isTag(node)) {
				node.origColIdx = colIdx;
				colIdx++;
			}
			idx++;
		}
	}

	/** Is the next line one with only a comment on it? **/
	public static function isNextLineACommentLine(nodes:Array<Node>, idx:Int):Bool {
		final n1 = idx < nodes.length ? nodes[idx] : null;
		final n2 = idx + 1 < nodes.length ? nodes[idx + 1] : null;
		if (n1 != null && n2 != null)
			return isComment(n1) && isNewline(n2);
		return n1 != null && isComment(n1);
	}
}
