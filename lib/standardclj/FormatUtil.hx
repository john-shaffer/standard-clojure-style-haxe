package standardclj;

import standardclj.NodeUtil.*;

/**
	Helpers for printing: string utilities and predicates on whitespace nodes.
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
}
