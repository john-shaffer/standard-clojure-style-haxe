package standardclj;

import standardclj.NodeUtil.*;
import standardclj.NsData;

/** Parsing of the values of `:gen-class` keys in an ns form. **/
class GenClass {
	static final keywords = [
		":constructors", ":exposes", ":exposes-methods", ":extends", ":factory", ":impl-ns", ":implements", ":init",
		":load-impl-ns", ":main", ":methods", ":name", ":post-init", ":prefix", ":state",
	];

	public static function isKeyword(node:Null<Node>):Bool {
		return node != null && node.text != null && keywords.indexOf(node.text) >= 0;
	}

	// keys whose value is a symbol or string
	public static function isNameKey(key:Null<String>):Bool {
		return switch key {
			case "extends" | "factory" | "impl-ns" | "init" | "name" | "post-init" | "state": true;
			default: false;
		}
	}

	public static function isBooleanKey(key:Null<String>):Bool {
		return key == "main" || key == "load-impl-ns";
	}

	static inline function empty(s:Null<String>):Bool {
		return s == null || s == "";
	}

	public static function parseConstructors(mapNode:Node):Array<Constructor> {
		final constructorErrorMessage = ":gen-class :constructors must be a map of parameter and super-parameter vectors.";
		final pairs = mapPairs(mapNode, ":gen-class :constructors must contain parameter and super-parameter vector pairs.");
		final constructors:Array<Constructor> = [];
		for (pair in pairs) {
			final parameterTypesForm = splitMetadataForm(pair[0]);
			final parameterTypesNode = parameterTypesForm.bodyNode;
			final superParameterTypesNode = pair[1];

			if (!isVectorLiteral(parameterTypesNode) || !isVectorLiteral(superParameterTypesNode))
				throw new haxe.Exception(constructorErrorMessage);

			final constructor = new Constructor(parseTypeVector(parameterTypesNode, constructorErrorMessage),
				parseTypeVector(superParameterTypesNode, constructorErrorMessage));
			if (!empty(parameterTypesForm.metadata))
				constructor.metadata = parameterTypesForm.metadata;
			constructors.push(constructor);
		}
		return constructors;
	}

	static function directFormNodes(collectionNode:Node):Array<Node> {
		final formNodes:Array<Node> = [];
		final children = collectionNode.children;
		if (children != null && children.length == 3 && children[1].name == ".body") {
			final bodyChildren = children[1].children;
			if (bodyChildren != null)
				for (child in bodyChildren)
					if (!isWhitespace(child) && !isComment(child))
						formNodes.push(child);
		}
		return formNodes;
	}

	public static function symbolText(node:Null<Node>):Null<String> {
		if (node == null)
			return null;
		if (isToken(node))
			return node.text;
		if (isString(node))
			return '"' + stringText(node) + '"';
		if (node.name == "meta")
			return textOf(node);
		return null;
	}

	/** Splits a possibly-`meta` form into its body node and the metadata text before it. **/
	public static function splitMetadataForm(node:Null<Node>):{bodyNode:Null<Node>, metadata:Null<String>} {
		if (node == null || node.name != "meta" || node.children == null)
			return {bodyNode: node, metadata: null};

		var metadata = "";
		var bodyNode:Null<Node> = null;
		for (child in node.children) {
			if (child.name == ".body") {
				if (child.children != null && child.children.length == 1)
					bodyNode = child.children[0];
				break;
			}
			metadata += textOf(child);
		}
		return {bodyNode: bodyNode, metadata: StringTools.rtrim(metadata)};
	}

	static function parseTypeVector(vectorNode:Node, errorMessage:String):Array<String> {
		final types:Array<String> = [];
		for (typeNode in directFormNodes(vectorNode)) {
			final typeName = symbolText(typeNode);
			if (empty(typeName))
				throw new haxe.Exception(errorMessage);
			types.push(typeName);
		}
		return types;
	}

	public static function parseMethods(vectorNode:Node):Array<Method> {
		final methods:Array<Method> = [];
		for (node in directFormNodes(vectorNode)) {
			final methodForm = splitMetadataForm(node);
			final methodNode = methodForm.bodyNode;
			if (!isVectorLiteral(methodNode))
				throw new haxe.Exception(":gen-class :methods must be a vector of method vectors.");

			final methodFormNodes = directFormNodes(methodNode);
			if (methodFormNodes.length != 3)
				throw new haxe.Exception(":gen-class :methods entries must contain a name, parameter-types vector, and return type.");

			final name = symbolText(methodFormNodes[0]);
			final parameterTypesNode = methodFormNodes[1];
			final returnType = symbolText(methodFormNodes[2]);
			if (empty(name))
				throw new haxe.Exception(":gen-class :methods method names must be symbols.");
			if (!isVectorLiteral(parameterTypesNode))
				throw new haxe.Exception(":gen-class :methods parameter types must be provided in a vector.");
			if (empty(returnType))
				throw new haxe.Exception(":gen-class :methods return types must be symbols.");

			final method = new Method(name, parseTypeVector(parameterTypesNode, ":gen-class :methods parameter types must be symbols inside a vector."),
				returnType);
			if (!empty(methodForm.metadata))
				method.metadata = methodForm.metadata;
			methods.push(method);
		}
		return methods;
	}

	static function mapPairs(mapNode:Node, errorMessage:String):Array<Array<Node>> {
		final formNodes = directFormNodes(mapNode);
		if (formNodes.length % 2 != 0)
			throw new haxe.Exception(errorMessage);
		return [for (i in 0...Std.int(formNodes.length / 2)) [formNodes[i * 2], formNodes[i * 2 + 1]]];
	}

	public static function parseExposes(mapNode:Node):Array<Expose> {
		final pairs = mapPairs(mapNode, ":gen-class :exposes must contain protected-field and accessor-map pairs.");
		final exposes:Array<Expose> = [];
		for (pair in pairs) {
			final fieldName = symbolText(pair[0]);
			final accessorsNode = pair[1];
			if (empty(fieldName))
				throw new haxe.Exception(":gen-class :exposes protected field names must be symbols.");
			if (!isMapLiteral(accessorsNode))
				throw new haxe.Exception(":gen-class :exposes field values must be maps containing :get and/or :set.");

			final accessorPairs = mapPairs(accessorsNode, ":gen-class :exposes accessor maps must contain keyword and method-name pairs.");
			final expose = new Expose(fieldName);
			final seenAccessors:Map<String, Bool> = [];
			for (accessorPair in accessorPairs) {
				final accessorKey = isToken(accessorPair[0]) ? accessorPair[0].text : null;
				final accessorName = symbolText(accessorPair[1]);

				if (accessorKey != ":get" && accessorKey != ":set")
					throw new haxe.Exception(":gen-class :exposes accessor keys must be :get or :set.");
				if (seenAccessors.exists(accessorKey))
					throw new haxe.Exception(":gen-class :exposes accessor maps cannot repeat :get or :set.");
				if (empty(accessorName))
					throw new haxe.Exception(":gen-class :exposes accessor method names must be symbols.");

				if (accessorKey == ":get")
					expose.getter = accessorName;
				else
					expose.setter = accessorName;
				seenAccessors[accessorKey] = true;
			}
			exposes.push(expose);
		}
		return exposes;
	}

	public static function parseExposesMethods(mapNode:Node):Array<ExposesMethod> {
		final pairs = mapPairs(mapNode, ":gen-class :exposes-methods must contain superclass-method and exposed-name pairs.");
		final exposesMethods:Array<ExposesMethod> = [];
		for (pair in pairs) {
			final superMethodName = symbolText(pair[0]);
			final exposedName = symbolText(pair[1]);
			if (empty(superMethodName) || empty(exposedName))
				throw new haxe.Exception(":gen-class :exposes-methods names must be symbols.");
			exposesMethods.push(new ExposesMethod(superMethodName, exposedName));
		}
		return exposesMethods;
	}
}
