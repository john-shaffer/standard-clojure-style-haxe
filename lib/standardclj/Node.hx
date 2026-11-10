package standardclj;

/**
	A node of the syntax tree.

	- `children`: child nodes (null for terminals)
	- `endIdx`: end position in the source (exclusive)
	- `name`: node kind, e.g. `parens`, `token`, `.open`
	- `startIdx`: start position in the source (inclusive)
	- `text`: raw text (null for non-terminals)
**/
class Node {
	static var idCounter = 0;

	public var children:Null<Array<Node>>;
	public var endIdx:Int;
	public final id:Int;
	public var name:Null<String>;
	public var startIdx:Int;
	public var text:Null<String>;

	// scratch fields used by the formatter
	public var origColIdx = -1;
	public var printedColIdx = -1;
	public var printedLineIdx = -1;
	public var wasSlurpedUp = false;

	public function new(name:Null<String>, startIdx:Int, endIdx:Int, ?text:String, ?children:Array<Node>) {
		this.id = ++idCounter;
		this.name = name;
		this.startIdx = startIdx;
		this.endIdx = endIdx;
		this.text = text;
		this.children = children;
	}

	public function hasText():Bool {
		return text != null && text != "";
	}

	/** Calls `f` on this node and every descendant, in source order. **/
	public function walk(f:Node->Void):Void {
		f(this);
		if (children != null) {
			for (c in children)
				c.walk(f);
		}
	}

	/** The tree flattened to a list, in source order. **/
	public function flatten():Array<Node> {
		final out:Array<Node> = [];
		walk(n -> out.push(n));
		return out;
	}
}
