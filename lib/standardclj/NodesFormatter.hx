package standardclj;

import standardclj.FormatUtil.*;
import standardclj.NodeUtil.*;
import standardclj.NsData;
import standardclj.Standard.FormatResult;

/** What the formatter tracks about a collection while it is on the paren stack. **/
private class ParenInfo {
	public final opener:Node;
	/** Is the first form of the collection itself a collection? **/
	public final headIsOpener:Bool;
	/** Nodes printed on the opening line of this paren stack, used to determine if Rule 3 indentation applies. **/
	public final openingLineNodes:Array<Node> = [];
	public final openerLineIdx:Int;
	public var rule3Active = false;
	public var rule3NumSpaces = 0;
	public var rule3SearchComplete = false;

	public function new(opener:Node, headIsOpener:Bool, openerLineIdx:Int) {
		this.opener = opener;
		this.headIsOpener = headIsOpener;
		this.openerLineIdx = openerLineIdx;
	}
}

/** A list of sibling nodes being printed, and the position of the one in progress. **/
private class Frame {
	public final items:Array<Node>;
	public final owner:Node;
	public var pos = 0;

	public function new(owner:Node, items:Array<Node>) {
		this.owner = owner;
		this.items = items;
	}
}

private enum IgnoreKind {
	/** `#_ :standard-clj/ignore` **/
	Keyword;
	/** `#_{:standard-clj/ignore true}` **/
	Map;
}

/**
	The main formatting pass: prints the syntax tree of a source file, with the
	`ns` form printed from its parsed data.
**/
class NodesFormatter {
	final parsedNs:Ns;
	final nsForm:Null<Node>;
	final frames:Array<Frame> = [];
	final parenStack:Array<ParenInfo> = [];
	var nodesWeHavePrintedOnThisLine:Array<Node> = [];
	var nsFailure:Null<String> = null;
	var outTxt = "";
	var outputTxtContainsChars = false;
	var lineTxt = "";
	var lineIdx = 0;

	function new(parsedNs:Ns, nsForm:Null<Node>) {
		this.parsedNs = parsedNs;
		this.nsForm = nsForm;
	}

	/** Formats a parsed source file. `parsedNs` is the result of `NsParser.parse` for it. The nodes are modified in the process. **/
	public static function format(root:Node, parsedNs:Ns):FormatResult {
		var nsForm = null;
		if (parsedNs.nsSymbol != null) {
			for (c in root.children) {
				if (NsParser.isNsForm(c)) {
					nsForm = c;
					break;
				}
			}
		}
		final f = new NodesFormatter(parsedNs, nsForm);
		f.recordOriginalColumnsOfFirstLine(root);
		f.printItems(root, itemsOf(root));
		if (f.nsFailure != null)
			return Failure(f.nsFailure);
		return Success(StringTools.trim(f.outTxt + f.lineTxt), false);
	}

	// -------------------------------------------------------------------------
	// Tree helpers

	/** The nodes inside a form in source order, with `.body` and `.meta` nodes replaced by their children. **/
	static function itemsOf(n:Node):Array<Node> {
		final out:Array<Node> = [];
		for (c in n.children)
			addItem(c, out);
		return out;
	}

	static function addItem(n:Node, out:Array<Node>):Void {
		if (n.children == null) {
			out.push(n);
		} else if (n.name == ".body" || n.name == ".meta") {
			for (c in n.children)
				addItem(c, out);
		} else if (isTag(n)) {
			// the `#` of a tagged literal is printed for this node, then its token
			out.push(n);
			for (c in n.children)
				addItem(c, out);
		} else {
			out.push(n);
		}
	}

	static function isLeaf(n:Node):Bool {
		return n.children == null || isTag(n);
	}

	/** The form inside the `.body` of a node. **/
	static function bodyForm(n:Node):Null<Node> {
		for (c in n.children) {
			if (c.name == ".body")
				return c.children[0];
		}
		return null;
	}

	/** Is the first form inside the collection, skipping metadata and discards, a collection? **/
	static function headIsCollection(collection:Node):Bool {
		for (c in itemsOf(collection).slice(1)) {
			if (isWhitespace(c) || isComment(c) || isReaderComment(c))
				continue;
			var form = c;
			while (form != null && form.name == "meta")
				form = bodyForm(form);
			return form != null && form.children != null && isParenOpener(form.children[0]);
		}
		return false;
	}

	// -------------------------------------------------------------------------
	// Lookahead over the nodes after the one being printed

	/** Calls `visit` on the nodes with no children after the current one, in source order, until it returns false. **/
	function forward(visit:Node->Bool):Void {
		var i = frames.length;
		while (--i >= 0) {
			final f = frames[i];
			for (j in f.pos + 1...f.items.length) {
				if (!visitLeaves(f.items[j], visit))
					return;
			}
		}
	}

	static function visitLeaves(n:Node, visit:Node->Bool):Bool {
		if (isLeaf(n))
			return visit(n);
		for (c in itemsOf(n)) {
			if (!visitLeaves(c, visit))
				return false;
		}
		return true;
	}

	function nextWithText():Null<Node> {
		var found = null;
		forward(n -> {
			if (n.hasText())
				found = n;
			return found == null;
		});
		return found;
	}

	function hasForward():Bool {
		var found = false;
		forward(_ -> {
			found = true;
			return false;
		});
		return found;
	}

	/**
		Searches forward for closing parens that could be slurped up to the current
		line. Includes whitespace and comment nodes as well.
	**/
	function findForwardClosingParens():Array<Node> {
		final closers:Array<Node> = [];
		forward(n -> {
			if (isNewlineNodeWithCommaOnNextLine(n) || !(isWhitespace(n) || isParenCloser(n) || isComment(n)))
				return false;
			closers.push(n);
			return true;
		});
		return closers;
	}

	/** Are all of the nodes on the next line already slurped up, or whitespace? **/
	function areForwardNodesAlreadySlurped():Bool {
		var result = true;
		forward(n -> {
			if (isNewline(n))
				return false;
			if (n.text == null || n.wasSlurpedUp || isWhitespace(n))
				return true;
			result = false;
			return false;
		});
		return result;
	}

	/** Sets `origColIdx` on the nodes with text on the first line: the column they have in the source. **/
	function recordOriginalColumnsOfFirstLine(root:Node):Void {
		var col = 0;
		var done = false;
		root.walk(n -> {
			if (done || isNewline(n)) {
				done = true;
			} else {
				col = recordOriginalColumn(n, col);
			}
		});
	}

	static function recordOriginalColumn(n:Node, col:Int):Int {
		if (n.hasText()) {
			n.origColIdx = col;
			return col + n.text.length;
		}
		if (isTag(n)) {
			n.origColIdx = col;
			return col + 1;
		}
		return col;
	}

	/** Sets `origColIdx` on the nodes with text on the line after the current newline node. **/
	function recordOriginalColumnsOfNextLine(newline:Node):Void {
		var col = numSpacesAfterNewline(newline);
		forward(n -> {
			if (isNewline(n))
				return false;
			col = recordOriginalColumn(n, col);
			return true;
		});
	}

	/** Is the next line one with only a comment on it? **/
	function isNextLineACommentLine():Bool {
		var n1:Null<Node> = null;
		var n2:Null<Node> = null;
		forward(n -> {
			if (n1 == null) {
				n1 = n;
				return true;
			}
			n2 = n;
			return false;
		});
		if (n1 != null && n2 != null)
			return isComment(n1) && isNewline(n2);
		return n1 != null && isComment(n1);
	}

	// -------------------------------------------------------------------------
	// Printing

	/** The number of spaces to use for indentation at the beginning of a line. **/
	static function numSpacesForIndentation(wrapping:Null<ParenInfo>):Int {
		if (wrapping == null)
			return 0;
		final opener = wrapping.opener;
				final openerColIdx = opener.printedColIdx;
		if (isReaderConditionalOpener(opener))
			return openerColIdx + opener.text.length;
		if (wrapping.headIsOpener) {
			if (isMapLiteralOpener(opener) || isVectorLiteralOpener(opener) || isSingleParenOpener(opener))
				return openerColIdx + 1;
			if (isSetLiteralOpener(opener) || isAnonFnOpener(opener))
				return openerColIdx + 2;
			throw new haxe.Exception("Error inside numSpacesForIndentation function. This condition should be unreachable.");
		}
		if (isMapLiteralOpener(opener) || isVectorLiteralOpener(opener))
			return openerColIdx + 1;
		if (isAnonFnOpener(opener))
			return openerColIdx + 3;
		if (isNamespacedMapOpener(opener))
			return openerColIdx + opener.text.length;
		// else indent two spaces from the wrapping opener
		return openerColIdx + 2;
	}


	/** What `#_` discards, if it asks for the next form to be left alone. **/
	static function ignoreKind(discard:Node):Null<IgnoreKind> {
		final form = bodyForm(discard);
		final gaps = discard.children.length - 2;
		if (isStandardCljIgnoreKeyword(form) && (gaps == 0 || (gaps == 1 && isWhitespace(discard.children[1]))))
			return Keyword;
		if (form != null && form.name == "braces" && gaps == 0 && isOpen(form.children[0], "{") && isStandardCljIgnoreKeyword(itemsOf(form)[1]))
			return Map;
		return null;
	}

	/** Appends text to the output as it is, without formatting it. **/
	function printRaw(text:String):Void {
		outTxt += lineTxt + text;
		lineTxt = "";
	}

	function printItems(owner:Node, items:Array<Node>):Void {
		final frame = new Frame(owner, items);
		frames.push(frame);
		while (frame.pos < items.length) {
			final node = items[frame.pos];
			if (node == nsForm) {
				printNs(frame);
			} else if (isLeaf(node)) {
				printLeaf(node);
			} else {
				printItems(node, itemsOf(node));
				final kind = node.name == "discard" ? ignoreKind(node) : null;
				if (kind != null)
					leaveNextFormAlone(frame, kind);
			}
			frame.pos++;
		}
		frames.pop();
	}

	/** Prints the `ns` form from its parsed data. **/
	function printNs(frame:Frame):Void {
		try {
			lineTxt += NsFormatter.format(parsedNs);
		} catch (e:haxe.Exception) {
			nsFailure = e.message;
		}
		outputTxtContainsChars = true;
		nodesWeHavePrintedOnThisLine = [];
		// NsFormatter prints the comments (and discards) after the closing paren that it was given,
		// and the whitespace before them
		final outside:Null<String> = parsedNs.commentOutsideNsForm;
		if (outside == null || outside == "")
			return;
		var skipped = "";
		var last = frame.pos;
		var i = frame.pos + 1;
		while (i < frame.items.length) {
			final next = frame.items[i];
			if (isNewline(next) || !(isWhitespace(next) || isComment(next) || isReaderComment(next)))
				break;
			if (!isWhitespace(next)) {
				final text = isComment(next) ? next.text : textOf(next);
				final candidate = skipped == "" ? text : skipped + " " + text;
				if (outside != candidate && !StringTools.startsWith(outside, candidate + " "))
					break;
				skipped = candidate;
				last = i;
			}
			i++;
		}
		frame.pos = last;
	}

	/** After `#_ :standard-clj/ignore`, prints the form that follows it as it is. **/
	function leaveNextFormAlone(frame:Frame, kind:IgnoreKind):Void {
		var end = frame.pos + 1;
		while (end < frame.items.length && isWhitespace(frame.items[end]))
			end++;
		if (end >= frame.items.length || isParenCloser(frame.items[end]))
			return;
		final target = frame.items[end];
		var start = frame.pos + 1;
		if (!isLeaf(target) && kind == Keyword) {
			// only a form is left alone, the whitespace before it is formatted
			while (frame.pos + 1 < end) {
				frame.pos++;
				printLeaf(frame.items[frame.pos]);
			}
			start = end;
		}
		final raw = new StringBuf();
		for (i in start...end + 1)
			raw.add(textOf(frame.items[i]));
		printRaw(raw.toString());
		frame.pos = end;
	}

	function printLeaf(node:Node):Void {
		// edge case: add '#' text to .tag nodes
		if (isTag(node))
			node.text = "#";

		final nextTextNode = nextWithText();
		final isLastNode = !hasForward();

		final currentNodeIsWhitespace = isWhitespace(node);
		final currentNodeIsNewline = isNewline(node);

		var skipPrintingThisNode = false;

		if (isParenOpener(node)) {
			// we potentially need to add this opener node to the current openingLineNodes
			// before we push into the next parenStack
			if (parenStack.length > 0) {
				final top = parenStack[parenStack.length - 1];
				if (lineIdx == top.openerLineIdx)
					top.openingLineNodes.push(node);
			}

			final frame = frames[frames.length - 1];
			parenStack.push(new ParenInfo(node, headIsCollection(frame.owner), lineIdx));

			// remove whitespace after an opener (remove-surrounding-whitespace?)
			if (isWhitespace(nextTextNode))
				frame.pos++;
		} else if (isParenCloser(node)) {
			parenStack.pop();
		}

		// add nodes to the top of the parenStack if we are on the opening line
		if (parenStack.length > 0 && node.hasText()) {
			final top = parenStack[parenStack.length - 1];
			if (lineIdx == top.openerLineIdx)
				top.openingLineNodes.push(node);
		}

		// remove whitespace before a closer (remove-surrounding-whitespace?)
		if (currentNodeIsWhitespace && !currentNodeIsNewline && isParenCloser(nextTextNode))
			skipPrintingThisNode = true;

		// do not print a comma at the end of a line
		if (currentNodeIsWhitespace && !currentNodeIsNewline && nextTextNode != null && isComment(nextTextNode))
			node.text = StringTools.replace(node.text, ",", "");

		// If we are inside of a parenStack and hit a newline,
		// look forward to see if we can close the current parenTrail.
		// ie: slurp closing parens onto the current line
		if (parenStack.length > 0) {
			final isCommentFollowedByNewline = isComment(node) && nextTextNode != null && isNewline(nextTextNode);
			final hasCommasAfterNewline2 = hasCommasAfterNewline(node) || hasCommasAfterNewline(nextTextNode);

			var lookForwardToSlurpNodes = false;
			if (hasCommasAfterNewline2)
				lookForwardToSlurpNodes = false;
			else if (isCommentFollowedByNewline)
				lookForwardToSlurpNodes = true;
			else if (currentNodeIsNewline)
				lookForwardToSlurpNodes = true;

			if (lookForwardToSlurpNodes) {
				// look forward and grab any closers nodes that may be slurped up
				final parenTrailClosers = findForwardClosingParens();

				// If we have printed a whitespace node just before this, we may need to remove it and then re-print
				final lastNodeWePrinted = nodesWeHavePrintedOnThisLine.length > 0 ? nodesWeHavePrintedOnThisLine[nodesWeHavePrintedOnThisLine.length - 1] : null;
				var lineTxtHasBeenRightTrimmed = false;
				if (lastNodeWePrinted != null && isWhitespace(lastNodeWePrinted)) {
					lineTxt = removeTrailingWhitespace(lineTxt);
					lineTxtHasBeenRightTrimmed = true;
				}

				for (closer in parenTrailClosers) {
					if (isParenCloser(closer)) {
						// NOTE: we are adjusting the current line here, but we do not update the nodesWeHavePrintedOnThisLine
						// because we cannot have a Rule 3 alignment to a closer node
						lineTxt += closer.text;
						closer.text = "";
						closer.wasSlurpedUp = true;
						parenStack.pop();
					}
				}

				// re-print the whitespace node if necessary
				if (lineTxtHasBeenRightTrimmed)
					lineTxt += lastNodeWePrinted.text;
			}
		}

		if (currentNodeIsNewline && !skipPrintingThisNode) {
			// record the original column indexes for the next line
			recordOriginalColumnsOfNextLine(node);

			final numSpacesOnNextLine = numSpacesAfterNewline(node);

			// Have we already slurped up everything on the next line?
			final allNextLineNodesWereSlurpedUp = areForwardNodesAlreadySlurped();

			final nextLineContainsOnlyOneComment = isNextLineACommentLine();
			var nextLineCommentColIdx = -1;
			if (nextLineContainsOnlyOneComment)
				nextLineCommentColIdx = numSpacesOnNextLine;

			final isDoubleNewline = node.text.indexOf("\n\n") >= 0;
			var newlineStr = "\n";
			if (isDoubleNewline)
				newlineStr = "\n\n";

			// print the current line and calculate the next line's indentation level
			if (outputTxtContainsChars) {
				final topOfTheParenStack = parenStack.length > 0 ? parenStack[parenStack.length - 1] : null;

				// Check for Rule 3:
				// Are we inside of a parenStack that crosses into the next line?
				// And have not already done a "Rule 3" check for this parenStack?
				if (topOfTheParenStack != null && !topOfTheParenStack.rule3SearchComplete) {
					var searchForAlignmentNode = true;
					// NOTE: we can start this index at 1 because we will always want to skip at least the first node
					var openingLineNodeIdx = 1;

					// we must be past the first whitespace node in order to look for Rule 3 alignment nodes
					var pastFirstWhitespaceNode = false;

					final numOpeningLineNodes = topOfTheParenStack.openingLineNodes.length;
					if (numOpeningLineNodes > 2) {
						while (searchForAlignmentNode) {
							final openingLineNode = topOfTheParenStack.openingLineNodes[openingLineNodeIdx];
							if (openingLineNode != null) {
								// Is the first node on this new line vertically aligned with any of the nodes
								// on the line above that are in the same paren stack?
								if (pastFirstWhitespaceNode && hasNonBlankText(openingLineNode) && openingLineNode.origColIdx == numSpacesOnNextLine) {
									// Rule 3 is activated
									topOfTheParenStack.rule3Active = true;

									// NOTE: we use the original colIdx of this node in order to determine Rule 3 alignment,
									// but we use the printedColIdx of this node to determine the number of leading spaces
									topOfTheParenStack.rule3NumSpaces = openingLineNode.printedColIdx;

									// we are done searching at this point
									searchForAlignmentNode = false;
								} else if (!pastFirstWhitespaceNode && isWhitespace(openingLineNode)) {
									pastFirstWhitespaceNode = true;
								}
							}

							openingLineNodeIdx++;
							if (openingLineNodeIdx >= numOpeningLineNodes)
								searchForAlignmentNode = false;
						}
					}

					// only check for Rule 3 alignment once per parenStack
					topOfTheParenStack.rule3SearchComplete = true;
				}

				// Do we have a comment line that looks vertically aligned with nodes on the previous line?
				// NOTE: this is basically "Rule 3" for single line comments
				var colIdxOfSingleLineCommentAlignmentNode = -1;
				var commentLooksAlignedWithPreviousForm = false;
				if (nextLineContainsOnlyOneComment && !isDoubleNewline) {
					for (idx2 in 0...nodesWeHavePrintedOnThisLine.length) {
						final prevLineNode = nodesWeHavePrintedOnThisLine[idx2];
						final prevNode2 = idx2 > 0 ? nodesWeHavePrintedOnThisLine[idx2 - 1] : null;

						var isPossibleAlignmentNode = false;
						if (hasNonBlankText(prevLineNode)) {
							if (prevNode2 == null || !isParenOpener(prevNode2))
								isPossibleAlignmentNode = true;
						}

						if (isPossibleAlignmentNode && nextLineCommentColIdx == prevLineNode.origColIdx) {
							colIdxOfSingleLineCommentAlignmentNode = prevLineNode.printedColIdx;
							commentLooksAlignedWithPreviousForm = true;
							break;
						}
					}
				}

				var numSpaces = 0;
				if (topOfTheParenStack != null && topOfTheParenStack.rule3Active) {
					// If we are inside a parenStack and Rule 3 has been activated, use that first.
					numSpaces = topOfTheParenStack.rule3NumSpaces;
				} else if (nextLineContainsOnlyOneComment && commentLooksAlignedWithPreviousForm) {
					// Comment lines that are vertically aligned with a node from the line above --> align to that node
					numSpaces = colIdxOfSingleLineCommentAlignmentNode;
				} else if (nextLineContainsOnlyOneComment && topOfTheParenStack == null) {
					// Comment lines that are outside of a parenStack, and have no obvious relation to lines above them:
					// keep their current indentation
					numSpaces = numSpacesOnNextLine;
				} else {
					// Else apply regular fixed indentation rules based on the parenStack depth (ie: Tonsky rules)
					numSpaces = numSpacesForIndentation(topOfTheParenStack);
				}

				var indentationStr = repeatString(" ", numSpaces);

				// If we have slurped up all of the nodes on this line, we can remove it.
				if (allNextLineNodesWereSlurpedUp) {
					newlineStr = "";
					indentationStr = "";
				}

				if (isComma(node)) {
					final nextLineCommaTrail = removeLeadingWhitespace(node.text);
					indentationStr += StringTools.rtrim(nextLineCommaTrail);
				}

				// add this line to the outTxt and reset lineTxt
				if (hasNonWhitespaceChars(lineTxt))
					outTxt += lineTxt;
				outTxt += newlineStr;

				lineTxt = indentationStr;
				nodesWeHavePrintedOnThisLine = [];

				// increment the lineIdx
				lineIdx++;
				if (isDoubleNewline)
					lineIdx++;
			}

			// we have taken care of printing this node, skip the "normal" printing step
			skipPrintingThisNode = true;
		}

		if (node.hasText() && !skipPrintingThisNode) {
			final isTokenFollowedByOpener = isToken(node) && nextTextNode != null && isParenOpener(nextTextNode);
			final isParenCloserFollowedByText = isParenCloser(node) && nextTextNode != null && (isToken(nextTextNode) || isParenOpener(nextTextNode));
			final addSpaceAfterThisNode = isTokenFollowedByOpener || isParenCloserFollowedByText;

			var nodeTxt = node.text;
			if (isComment(node)) {
				if (commentNeedsSpaceInside(nodeTxt))
					nodeTxt = addSpaceInsideComment(nodeTxt);
				if (commentNeedsSpaceBefore(lineTxt, nodeTxt))
					nodeTxt = " " + nodeTxt;
			}

			// if there is a whitespace node as the first or last node, do not print it
			if (currentNodeIsWhitespace && (isLastNode || !outputTxtContainsChars))
				skipPrintingThisNode = true;

			// add the text of this node to the current line
			if (!skipPrintingThisNode) {
				final lineLengthBeforePrintingNode = lineTxt.length;
				lineTxt += nodeTxt;

				if (lineTxt != "")
					outputTxtContainsChars = true;

				// add the printed colIdx to this node
				node.printedColIdx = lineLengthBeforePrintingNode;
				node.printedLineIdx = lineIdx;

				nodesWeHavePrintedOnThisLine.push(node);
			}

			if (addSpaceAfterThisNode)
				lineTxt += " ";
		}
	}
}
