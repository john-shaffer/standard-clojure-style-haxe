package standardclj;

import standardclj.NodeUtil.*;

/** Searches inside `meta` nodes. **/
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

	/** Comments and discards between a `meta` node's metadata and its body. **/
	public static function metaComments(meta:Node):Array<String> {
		final out:Array<String> = [];
		for (child in meta.children) {
			if (child.name == ".body")
				break;
			if (isComment(child))
				out.push(child.text);
			else if (isReaderComment(child))
				out.push(textOf(child));

		}
		return out;
	}
}
