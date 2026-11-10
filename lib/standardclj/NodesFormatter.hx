package standardclj;

import standardclj.FormatUtil.*;
import standardclj.NodeSearch.*;
import standardclj.NodeUtil.*;
import standardclj.Standard.FormatResult;

/** What the formatter tracks about an opener node while it is on the paren stack. **/
private class ParenInfo {
	public final opener:Node;
	/** Nodes printed on the opening line of this paren stack, used to determine if Rule 3 indentation applies. **/
	public final openingLineNodes:Array<Node> = [];
	public final nextWithTextSkippingMeta:Null<Node>;
	public final openerLineIdx:Int;
	public var rule3Active = false;
	public var rule3NumSpaces = 0;
	public var rule3SearchComplete = false;

	public function new(opener:Node, nextWithTextSkippingMeta:Null<Node>, openerLineIdx:Int) {
		this.opener = opener;
		this.nextWithTextSkippingMeta = nextWithTextSkippingMeta;
		this.openerLineIdx = openerLineIdx;
	}
}

/** The main formatting pass, over the nodes of a parsed source file and its parsed `ns` form. **/
class NodesFormatter {
	/** The text of a comment node or a discard form (`#_ ...`), null otherwise. **/
	static function commentOrDiscardText(node:Null<Node>):Null<String> {
		if (node == null)
			return null;
		if (isComment(node))
			return node.text;
		if (isReaderComment(node))
			return textOf(node);
		return null;
	}

	static inline function hasChars(s:Null<String>):Bool {
		return s != null && s != "";
	}

	/**
		Is this node part of the comment (or discard forms) that trail the closing
		paren of the ns form? parseNs merges those into `commentOutsideNsForm` and
		formatNs prints them itself, so they must not be printed a second time.
		`txtSkippedSoFar` is the text of the trailing comment nodes already skipped
		on this line.
	**/
	static function isNsTrailingComment(node:Null<Node>, parsedNs:Dynamic, txtSkippedSoFar:String):Bool {
		final nodeTxt = commentOrDiscardText(node);
		final outside:Null<String> = parsedNs.commentOutsideNsForm;
		if (!hasChars(nodeTxt) || !hasChars(outside))
			return false;
		final candidateTxt = txtSkippedSoFar == "" ? nodeTxt : txtSkippedSoFar + " " + nodeTxt;
		return outside == candidateTxt || StringTools.startsWith(outside, candidateTxt + " ");
	}

	static function isOpeningBraceNode(n:Null<Node>):Bool {
		if (n == null || n.name != "braces" || n.children == null || n.children.length != 3)
			return false;
		final last = n.children[2];
		return last.name == ".close" && last.text == "}";
	}

	/** The number of spaces to use for indentation at the beginning of a line. **/
	static function numSpacesForIndentation(wrapping:Null<ParenInfo>):Int {
		if (wrapping == null)
			return 0;
		final opener = wrapping.opener;
		final nextNodeAfterOpener = wrapping.nextWithTextSkippingMeta;
		final openerColIdx = opener.printedColIdx;
		if (isReaderConditionalOpener(opener))
			return openerColIdx + opener.text.length;
		if (nextNodeAfterOpener != null && isParenOpener(nextNodeAfterOpener)) {
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

	/**
		Formats the flattened tree. `parsedNs` is the result of `NsParser.parse`,
		which is printed in place of the ns form by `NsFormatter.format`.
		The nodes are modified in the process.
	**/
	public static function format(nodes:Array<Node>, parsedNs:Dynamic):FormatResult {
		final numNodes = nodes.length;
		final hasParsedNsForm = parsedNs.nsSymbol != null;

		var parenNestingDepth = 0;
		var idx = 0;
		var outTxt = "";
		var outputTxtContainsChars = false;
		var lineTxt = "";
		var lineIdx = 0;
		var insideNsForm = false;
		var lineIdxOfClosingNsForm = -1;
		// id of the last node of a discard form that trails the ns form (printed by formatNs)
		var nsTrailingDiscardEndId = -1;
		// text of the comment / discard nodes trailing the ns form that we have skipped so far
		var nsTrailingCommentTxtSkipped = "";
		var nsStartStringIdx = -1;
		var nsEndStringIdx = -1;
		var ignoreNodesStartId = -1;
		var ignoreNodesEndId = -1;
		var insideTheIgnoreZone = false;

		final parenStack:Array<ParenInfo> = [];
		var nodesWeHavePrintedOnThisLine:Array<Node> = [];

		while (idx < numNodes) {
			final node = nodes[idx];

			if (ignoreNodesStartId > 0 && node.id == ignoreNodesStartId) {
				insideTheIgnoreZone = true;
				// dump the current lineTxt when we start the ignore zone
				outTxt += lineTxt;
				lineTxt = "";
			}

			if (insideTheIgnoreZone) {
				if (node.hasText())
					outTxt += node.text;
				if (node.id == ignoreNodesEndId) {
					ignoreNodesStartId = -1;
					ignoreNodesEndId = -1;
					insideTheIgnoreZone = false;
				}
				idx++;
				continue;
			}

			// edge case: add '#' text to .tag nodes
			if (isTag(node))
				node.text = "#";

			// record original column indexes for the first line
			if (idx == 0)
				recordOriginalColIndexes(nodes, idx);

			if (nsStartStringIdx == -1 && parenNestingDepth == 1 && hasParsedNsForm && isNs(node)) {
				insideNsForm = true;
				nsStartStringIdx = (outTxt + lineTxt).length;
			}

			final nextTextNode = nextWithText(nodes, idx + 1);
			final isLastNode = idx + 1 >= numNodes;

			final currentNodeIsWhitespace = isWhitespace(node);
			final currentNodeIsNewline = isNewline(node);

			var skipPrintingThisNode = false;

			// do not print the comment (or discard form) on the last line of the ns form:
			// formatNs prints it after the closing parens
			if (nsTrailingDiscardEndId > 0) {
				skipPrintingThisNode = true;
				if (node.id == nsTrailingDiscardEndId)
					nsTrailingDiscardEndId = -1;
			} else if (lineIdx == lineIdxOfClosingNsForm && isNsTrailingComment(node, parsedNs, nsTrailingCommentTxtSkipped)) {
				skipPrintingThisNode = true;
				if (nsTrailingCommentTxtSkipped == "")
					nsTrailingCommentTxtSkipped = commentOrDiscardText(node);
				else
					nsTrailingCommentTxtSkipped += " " + commentOrDiscardText(node);
				if (isReaderComment(node))
					nsTrailingDiscardEndId = lastNodeWithText(node).id;
			}

			if (isStandardCljIgnoreKeyword(node) && idx > 1) {
				final prevNode1 = prevWithText(nodes, idx, node.id);
				var prevNode2 = null;
				if (prevNode1 != null)
					prevNode2 = prevWithText(nodes, idx, prevNode1.id);

				final isDiscardMap = prevNode1 != null && prevNode1.name == ".open" && prevNode1.text == "{" && prevNode2 != null
					&& isDiscardMarker(prevNode2);

				if (isDiscardMarker(prevNode1) || (isWhitespace(prevNode1) && isDiscardMarker(prevNode2))) {
					// look forward to find the next node with text
					final nextIgnoreNode = nextNonWhitespace(nodes, idx + 1);

					// if parens or brackets or something with children, then find the closing node id
					if (nextIgnoreNode.children != null && nextIgnoreNode.children.length > 0) {
						ignoreNodesStartId = nextIgnoreNode.id;
						ignoreNodesEndId = nextIgnoreNode.children[nextIgnoreNode.children.length - 1].id;
					} else {
						// if a node without children, then just don't format it
						ignoreNodesStartId = nodes[idx + 1].id;
						ignoreNodesEndId = nextIgnoreNode.id;
					}
				} else if (isDiscardMap) {
					// find the opening { and closing } for this form
					final openingBraceNode = prevMatching(nodes, idx, isOpeningBraceNode);
					final closingBraceNodeId = openingBraceNode.children[2].id;

					final startIgnoreNode = nextMatchingAfter(nodes, idx, _ -> true, closingBraceNodeId);
					final firstNodeInsideIgnoreZone = nextMatchingAfter(nodes, idx, _ -> true, startIgnoreNode.id);

					// if parens or brackets or something with children, then find the closing node id
					if (firstNodeInsideIgnoreZone.children != null && firstNodeInsideIgnoreZone.children.length > 0) {
						ignoreNodesStartId = startIgnoreNode.id;
						ignoreNodesEndId = firstNodeInsideIgnoreZone.children[firstNodeInsideIgnoreZone.children.length - 1].id;
					} else {
						// if a node without children, then just don't format it
						ignoreNodesStartId = startIgnoreNode.id;
						ignoreNodesEndId = firstNodeInsideIgnoreZone.id;
					}
				}
			}

			if (isParenOpener(node)) {
				// we potentially need to add this opener node to the current openingLineNodes
				// before we push into the next parenStack
				if (parenStack.length > 0) {
					final top = parenStack[parenStack.length - 1];
					if (lineIdx == top.openerLineIdx)
						top.openingLineNodes.push(node);
				}

				parenNestingDepth++;

				parenStack.push(new ParenInfo(node, nextTextSkippingMeta(nodes, idx + 1), lineIdx));

				// remove whitespace after an opener (remove-surrounding-whitespace?)
				if (isWhitespace(nextTextNode)) {
					// FIXME: skip this via index instead of modifying the tree like this
					nextTextNode.text = "";
				}
			} else if (isParenCloser(node)) {
				// NOTE: this code is duplicated when we look forward to close parenTrails
				parenNestingDepth--;
				parenStack.pop();

				// flag the end of the ns form
				if (insideNsForm && parenNestingDepth == 0) {
					insideNsForm = false;
					nsEndStringIdx = (outTxt + lineTxt).length;
					lineIdxOfClosingNsForm = lineIdx;
				}
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
			if (parenStack.length > 0 && !insideNsForm) {
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
					final parenTrailClosers = findForwardClosingParens(nodes, idx + 1);

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
							parenNestingDepth--;
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
				recordOriginalColIndexes(nodes, idx);

				final numSpacesOnNextLine = numSpacesAfterNewline(node);

				// Have we already slurped up everything on the next line?
				final allNextLineNodesWereSlurpedUp = areForwardNodesAlreadySlurped(nodes, idx + 1);

				final nextLineContainsOnlyOneComment = isNextLineACommentLine(nodes, idx + 1);
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

				if (currentNodeIsWhitespace && (isLastNode || !outputTxtContainsChars)) {
					// if there is a whitespace node as the first or last node, do not print it
					skipPrintingThisNode = true;
				} else if (currentNodeIsWhitespace && lineIdx == lineIdxOfClosingNsForm && isComment(nextTextNode)) {
					// do not print the whitespace before a comment on the last line of the ns form
					// (commentNeedsSpaceBefore adds a single space)
					skipPrintingThisNode = true;
				} else if (currentNodeIsWhitespace && lineIdx == lineIdxOfClosingNsForm
					&& isNsTrailingComment(nodes[idx + 1], parsedNs, nsTrailingCommentTxtSkipped)) {
					// do not print the whitespace before the comment (or discard form) that trails the ns form
					// (formatNs prints that comment itself, with a single space before it)
					skipPrintingThisNode = true;
				}

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

			idx++;
		}

		// add the last line to outTxt if necesary
		if (lineTxt != "")
			outTxt += lineTxt;

		// replace the ns form with our formatted version
		if (nsStartStringIdx > 0) {
			final headStr = outTxt.substr(0, nsStartStringIdx - 1);

			var nsStr = null;
			try {
				nsStr = NsFormatter.format(parsedNs);
			} catch (e:haxe.Exception) {
				return Failure(e.message);
			}

			var tailStr = "";
			if (nsEndStringIdx > 0)
				tailStr = outTxt.substr(nsEndStringIdx + 1);

			outTxt = headStr + nsStr + tailStr;
		}

		// remove any leading or trailing whitespace
		return Success(StringTools.trim(outTxt), false);
	}
}
