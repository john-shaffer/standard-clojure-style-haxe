package standardclj;

import standardclj.NodeUtil.*;

/** Searches over flat node lists (see `Node.flatten`) and over `meta` nodes. **/
class NodeSearch {
	/** The metadata forms attached by a `meta` node, with their markers, in source order. **/
	public static function metadataStrings(meta:Node):Array<String> {
		final out:Array<String> = [];
		var marker:Null<String> = null;
		for (child in meta.children) {
			if (isMetaMarker(child)) {
				marker = child.text;
			} else if (marker != null && child.name == ".meta") {
				out.push(marker + textOf(child));
				marker = null;
			}
		}
		return out;
	}

	/** Comments between a `meta` node's metadata and its body. **/
	public static function metaComments(meta:Node):Array<String> {
		final out:Array<String> = [];
		for (child in meta.children) {
			if (child.name == ".body")
				break;
			if (isComment(child))
				out.push(child.text);

		}
		return out;
	}

	/**
		The next node at or after `startIdx` that is not part of a metadata
		form or reader discard, i.e. skipping `^:foo`, `^{...}` and `#_ form`.
	**/
	public static function nextTextSkippingMeta(nodes:Array<Node>, startIdx:Int):Null<Node> {
		var idx = startIdx;
		var parenDepth = 0;
		var stringDepth = 0;
		var formsToSkip = 0;
		while (idx < nodes.length) {
			final node = nodes[idx];
			idx++;
			// only text-bearing non-whitespace, non-comment nodes count
			if (!hasText(node) || isWhitespace(node) || isComment(node))
				continue;
			if (isParenOpener(node)) {
				if (stringDepth == 0) {
					if (formsToSkip > 0 && parenDepth == 0)
						parenDepth = 1;
					else if (parenDepth > 0)
						parenDepth++;
					else
						return node;
				}
			} else if (isParenCloser(node)) {
				if (stringDepth == 0) {
					if (parenDepth > 0) {
						parenDepth--;
						if (parenDepth == 0)
							formsToSkip--;
					} else {
						return node;
					}
				}
			} else if (isStringOpener(node)) {
				if (formsToSkip > 0 && parenDepth == 0 && stringDepth == 0)
					stringDepth = 1;
				else if (parenDepth > 0 || stringDepth > 0)
					stringDepth++;
				else
					return node;
			} else if (isStringCloser(node)) {
				if (stringDepth > 0) {
					stringDepth--;
					if (stringDepth == 0 && parenDepth == 0)
						formsToSkip--;
				} else {
					return node;
				}
			} else if (parenDepth > 0 || stringDepth > 0) {
				// inside a form we are skipping
			} else if (isMetaMarker(node) || isDiscardMarker(node)) {
				formsToSkip++;
			} else if (formsToSkip > 0) {
				// a single-token form like `long` or `:private`
				formsToSkip--;
			} else {
				return node;
			}
		}
		return null;
	}

	/** The first node with text at or after `idx`. **/
	public static function nextWithText(nodes:Array<Node>, idx:Int):Null<Node> {
		while (idx < nodes.length) {
			if (nodes[idx].hasText())
				return nodes[idx];
			idx++;
		}
		return null;
	}

	/** The first node that is not whitespace at or after `idx`. **/
	public static function nextNonWhitespace(nodes:Array<Node>, idx:Int):Null<Node> {
		while (idx < nodes.length) {
			if (!isWhitespace(nodes[idx]))
				return nodes[idx];
			idx++;
		}
		return null;
	}

	/**
		The nearest node with text before the node with id `startingNodeId`,
		searching backwards from `startIdx`. Never examines index 0.
	**/
	public static function prevWithText(nodes:Array<Node>, startIdx:Int, startingNodeId:Int):Null<Node> {
		var idx = startIdx;
		var beforeStartingNode = false;
		while (true) {
			final node = nodes[idx];
			if (!beforeStartingNode) {
				if (node.id == startingNodeId)
					beforeStartingNode = true;
			} else if (hasText(node)) {
				return node;
			}
			idx--;
			if (idx == 0)
				return null;
		}
	}

	/** The first node after the node with id `specificNodeId` for which `pred` holds. **/
	public static function nextMatchingAfter(nodes:Array<Node>, startIdx:Int, pred:Node->Bool, specificNodeId:Int):Null<Node> {
		var afterSpecificNode = false;
		var idx = startIdx;
		while (idx < nodes.length) {
			final node = nodes[idx];
			if (!afterSpecificNode) {
				if (node.id == specificNodeId)
					afterSpecificNode = true;
			} else if (pred(node)) {
				return node;
			}
			idx++;
		}
		return null;
	}

	/** The nearest node at or before `startIdx` for which `pred` holds. **/
	public static function prevMatching(nodes:Array<Node>, startIdx:Int, pred:Node->Bool):Null<Node> {
		var idx = startIdx;
		while (idx >= 0) {
			if (pred(nodes[idx]))
				return nodes[idx];
			idx--;
		}
		return null;
	}
}
