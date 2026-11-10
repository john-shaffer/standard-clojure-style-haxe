package standardclj;

import standardclj.NodeUtil.*;

/**
	Extracts the data of an ns form from a flat list of nodes. The result is a
	Dynamic anonymous object shaped like upstream's `parseNs` result, where
	absent fields are really absent.
**/
class NsParser {
	// -------------------------------------------------------------------------
	// Sorting

	static function cmpStr(a:String, b:String):Int {
		return a > b ? 1 : a < b ? -1 : 0;
	}

	// NOTE: a missing platform compares equal to any platform, as upstream
	static function compareSymbolsThenPlatform(a:Dynamic, b:Dynamic):Int {
		final c = cmpStr(a.symbol, b.symbol);
		if (c != 0)
			return c;
		if (a.platform == null || b.platform == null)
			return 0;
		return cmpStr(a.platform, b.platform);
	}

	static function compareFromSymbol(a:Dynamic, b:Dynamic):Int {
		return cmpStr(a.fromSymbol, b.fromSymbol);
	}

	static function compareImports(a:Dynamic, b:Dynamic):Int {
		return cmpStr(Reflect.field(a, "package"), Reflect.field(b, "package"));
	}

	/**
		Sorts in place like V8's Array.prototype.sort for short arrays (a run
		detection followed by binary insertion), so that results are the same
		even for comparators that are not transitive.
	**/
	static function sortArray<T>(a:Array<T>, cmp:T->T->Int):Void {
		final n = a.length;
		if (n < 2)
			return;
		var runLength = 2;
		if (n > 2) {
			final descending = cmp(a[1], a[0]) < 0;
			var previous = a[1];
			var idx = 2;
			while (idx < n) {
				final order = cmp(a[idx], previous);
				if (descending ? order >= 0 : order < 0)
					break;
				previous = a[idx];
				runLength++;
				idx++;
			}
			if (descending)
				reverseRange(a, 0, runLength);
		} else if (cmp(a[1], a[0]) < 0) {
			reverseRange(a, 0, 2);
		}
		for (start in runLength...n) {
			var left = 0;
			var right = start;
			final pivot = a[start];
			while (left < right) {
				final mid = left + ((right - left) >> 1);
				if (cmp(pivot, a[mid]) < 0)
					right = mid;
				else
					left = mid + 1;
			}
			var p = start;
			while (p > left) {
				a[p] = a[p - 1];
				p--;
			}
			a[left] = pivot;
		}
	}

	static function reverseRange<T>(a:Array<T>, from:Int, to:Int):Void {
		var lo = from;
		var hi = to - 1;
		while (lo < hi) {
			final t = a[lo];
			a[lo] = a[hi];
			a[hi] = t;
			lo++;
			hi--;
		}
	}

	static inline function isArray(x:Dynamic):Bool {
		return Std.isOfType(x, Array);
	}

	static inline function sortField(obj:Dynamic, field:String, cmp:Dynamic->Dynamic->Int):Void {
		final arr:Dynamic = Reflect.field(obj, field);
		if (isArray(arr))
			sortArray(cast(arr, Array<Dynamic>), cmp);
	}

	/** Splits a single-symbol :import like "java.util.Date" into its package and class name. **/
	static function parseJavaPackageWithClass(s:String):{pkg:String, className:String} {
		final lastDotIdx = s.lastIndexOf(".");
		if (lastDotIdx == -1)
			return {pkg: "", className: s};
		return {pkg: s.substr(0, lastDotIdx), className: s.substr(lastDotIdx + 1)};
	}

	static function sortNsResult(result:Dynamic, importsObj:Null<Map<String, Dynamic>>, importKeys:Array<String>, prefixListComments:Map<Int, Dynamic>):Dynamic {
		final referClojure:Dynamic = result.referClojure;
		if (referClojure != null) {
			sortField(referClojure, "exclude", compareSymbolsThenPlatform);
			sortField(referClojure, "only", compareSymbolsThenPlatform);
			sortField(referClojure, "rename", compareFromSymbol);
		}

		final genClass:Dynamic = result.genClass;
		if (genClass != null) {
			final implementsKey:Dynamic = Reflect.field(genClass, "implements");
			if (implementsKey != null)
				sortField(implementsKey, "value", compareSymbolsThenPlatform);
		}

		if (isArray(result.requireMacros)) {
			final requireMacros:Array<Dynamic> = result.requireMacros;
			sortArray(requireMacros, compareSymbolsThenPlatform);
			for (rm in requireMacros)
				sortField(rm, "refer", compareSymbolsThenPlatform);
		}

		if (isArray(result.requires)) {
			final requires:Array<Dynamic> = result.requires;
			sortArray(requires, compareSymbolsThenPlatform);

			for (req in requires) {
				// attach prefix list comments to the first require with the same id (if possible)
				if (Reflect.hasField(req, "prefixListId")) {
					final id:Int = req.prefixListId;
					final comments:Dynamic = prefixListComments.get(id);
					if (comments != null) {
						if (comments.commentsAbove != null)
							req.commentsAbove = comments.commentsAbove;
						if (comments.commentAfter != null)
							req.commentAfter = comments.commentAfter;
						prefixListComments.remove(id);
					}
					Reflect.deleteField(req, "prefixListId");
				}

				sortField(req, "refer", compareSymbolsThenPlatform);
				sortField(req, "exclude", compareSymbolsThenPlatform);
				sortField(req, "rename", compareFromSymbol);
			}
		}

		// convert and sort the imports
		if (importsObj != null) {
			final imports:Array<Dynamic> = [];
			result.imports = imports;

			for (packageName in importKeys) {
				final obj:Dynamic = importsObj.get(packageName);
				final sortedClasses:Array<String> = obj.classes;
				sortArray(sortedClasses, cmpStr);

				// classes in the default package are printed as bare symbols,
				// so each one becomes its own import entry
				if (packageName == "") {
					final numClasses = sortedClasses.length;
					for (classIdx in 0...numClasses) {
						final importObj:Dynamic = {};
						Reflect.setField(importObj, "package", "");
						importObj.classes = [sortedClasses[classIdx]];
						if (obj.commentsAbove != null && classIdx == 0)
							importObj.commentsAbove = obj.commentsAbove;
						if (obj.commentAfter != null && classIdx == numClasses - 1)
							importObj.commentAfter = obj.commentAfter;
						if (obj.platform != null)
							importObj.platform = obj.platform;
						imports.push(importObj);
					}
				} else {
					final importObj:Dynamic = {};
					Reflect.setField(importObj, "package", packageName);
					importObj.classes = sortedClasses;
					if (obj.commentsAbove != null)
						importObj.commentsAbove = obj.commentsAbove;
					if (obj.commentAfter != null)
						importObj.commentAfter = obj.commentAfter;
					if (obj.platform != null)
						importObj.platform = obj.platform;
					imports.push(importObj);
				}
			}

			sortArray(imports, compareImports);
		}

		// merge nsMetadata keys
		if (isArray(result.nsMetadata)) {
			final nsMetadata:Array<Dynamic> = result.nsMetadata;
			if (nsMetadata.length > 1) {
				final metadataObj:Map<String, String> = [];
				final metadataKeys:Array<String> = [];
				for (item in nsMetadata) {
					metadataObj[item.key] = item.value;
					metadataKeys.push(item.key);
				}

				// keep the last occurrence of each key, in source order
				final newNsMetadata:Array<Dynamic> = [];
				var reverseIdx = metadataKeys.length - 1;
				while (reverseIdx >= 0) {
					final key = metadataKeys[reverseIdx];
					final value = metadataObj.get(key);
					if (value != null && value != "") {
						metadataObj.remove(key);
						newNsMetadata.push({key: key, value: value});
					}
					reverseIdx--;
				}
				newNsMetadata.reverse();
				result.nsMetadata = newNsMetadata;
			}
		}

		return result;
	}

	// -------------------------------------------------------------------------
	// Parsing

	/**
		Searches for a `#_ :standard-clj/ignore-file`, stopping when we reach
		the first (ns) form.
	**/
	public static function lookForIgnoreFile(nodes:Array<Node>):Bool {
		final numNodes = nodes.length;
		var idx = 0;
		while (true) {
			final node = nodes[idx];
			if (isDiscardMarker(node)) {
				final next1 = NodeSearch.nextMatchingAfter(nodes, idx, hasTextAndNotWhitespace, node.id);
				if (isStandardCljIgnoreFileKeyword(next1)) {
					return true;
				} else if (next1.text == "{") {
					final next2 = NodeSearch.nextMatchingAfter(nodes, idx, hasTextAndNotWhitespace, next1.id);
					if (isStandardCljIgnoreFileKeyword(next2)) {
						final next3 = NodeSearch.nextMatchingAfter(nodes, idx, hasTextAndNotWhitespace, next2.id);
						if (next3.name == "token" && next3.text == "true")
							return true;
					}
				}
			} else if (isNs(node)) {
				return false;
			}
			idx++;
			if (idx >= numNodes)
				return false;
		}
	}

	// the next token inside a :require list / vector, or null if we reach a closing paren
	// FIXME: this will not work with metadata, comments, or reader conditionals
	static function findNextTokenInsideRequireForm(nodes:Array<Node>, startIdx:Int):Null<Node> {
		var idx = startIdx;
		var result:Null<Node> = null;
		final numNodes = nodes.length;
		var keepSearching = true;
		while (keepSearching) {
			final node = nodes[idx];
			if (isParenCloser(node)) {
				keepSearching = false;
				result = null;
			} else if (isToken(node) && node.text != "") {
				keepSearching = false;
				result = node;
			}
			idx++;
			if (idx >= numNodes)
				keepSearching = false;
		}
		return result;
	}

	static inline function nonEmpty(s:Null<String>):Bool {
		return s != null && s != "";
	}

	/**
		Extracts namespace information from a flat array of nodes (see
		`Node.flatten`). Returns a data structure of the ns form that can be
		used to "print from scratch".
	**/
	public static function parse(nodesArr:Array<Node>):Dynamic {
		var idx = 0;
		final numNodes = nodesArr.length;
		final result:Dynamic = {nsSymbol: null};
		var importsObj:Null<Map<String, Dynamic>> = null;
		final importKeys:Array<String> = [];
		var idCounter = 0;
		function reqAt(i:Int):Dynamic {
			return (result.requires : Array<Dynamic>)[i];
		}
		function importAt(name:String):Dynamic {
			return importsObj.get(name);
		}
		function genClassField(key:String):Dynamic {
			return Reflect.field(result.genClass, key);
		}

		var continueParsingNsForm = true;
		var nsFormEndsLineIdx = -1;
		var parenNestingDepth = 0;
		var lineNo = 0;
		var insideNsForm = false;
		var insideReferClojureForm = false;
		var referClojureParenNestingDepth = -1;
		var insideRequireForm = false;
		var requireFormParenNestingDepth = -1;
		var requireFormLineNo = -1;
		var insideImportForm = false;
		var importFormLineNo = -1;
		var nextTextNodeIsNsSymbol = false;
		var insideImportPackageList = false;
		var collectReferClojureExcludeSymbols = false;
		var collectReferClojureOnlySymbols = false;
		var collectReferClojureRenameSymbols = false;
		var collectRequireExcludeSymbols = false;
		var requireExcludeSymbolParenDepth = -1;
		var renamesTmp:Array<String> = [];
		var importPackageListFirstToken:Null<String> = null;
		var nsNodeIdx = -1;
		var nsSymbolIdx = -1;
		var beyondNsMetadata = false;
		var insideNsMetadataHashMap = false;
		var insideNsMetadataShorthand = false;
		var nextTokenNodeIsMetadataTrueKey = false;
		var nextTextNodeIsMetadataKey = false;
		var metadataValueNodeId = -1;
		var tmpMetadataKey = "";
		var referClojureNodeIdx = -1;
		var requireNodeIdx = -1;
		var referIdx = -1;
		var referParenNestingDepth = -1;
		var importNodeIdx = -1;
		var importNodeParenNestingDepth = -1;
		var activeRequireIdx = -1;
		var requireSymbolIdx = -1;
		var nextTokenIsAsSymbol = false;
		var singleLineComments:Array<String> = [];
		var activeImportPackageName:Null<String> = null;
		var prevNodeIsNewline = false;
		var lineOfLastCommentRecording = -1;
		var lastCommentRecorded:Null<String> = null;
		var insidePrefixList = false;
		var prefixListParenNestingDepth = -1;
		var prefixListPrefix:Null<String> = null;
		var prefixListLineNo = -1;
		final prefixListComments:Map<Int, Dynamic> = [];
		var currentPrefixListId:Null<Int> = null;
		var insideReaderConditional = false;
		var readerConditionalIsSplicing = false;
		var currentReaderConditionalPlatform:Null<String> = null;
		var readerConditionalParenNestingDepth = -1;
		var insideRequireList = false;
		var requireListParenNestingDepth = -1;
		var referMacrosIdx = -1;
		var referMacrosParenNestingDepth = -1;
		var insideIncludeMacros = false;
		var activeRequireMacrosIdx = -1;
		var insideRequireMacrosForm = false;
		var requireMacrosNodeIdx = -1;
		var requireMacrosLineNo = -1;
		var requireMacrosParenNestingDepth = -1;
		var requireMacrosReferNodeIdx = -1;
		var requireMacrosAsNodeIdx = -1;
		var requireMacrosRenameIdx = -1;
		var genClassNodeIdx = -1;
		var insideGenClass = false;
		var genClassLineNo = -1;
		var genClassToggle = 0;
		var genClassKeyStr:Null<String> = null;
		var genClassValueLineNo = -1;
		var insideReaderComment = false;
		var idOfLastNodeInsideReaderComment = -1;
		var renameIdx = -1;
		var renameParenNestingDepth = -1;
		var skipNodesUntilWeReachThisId = -1;
		var sectionToAttachEolCommentsTo:Null<String> = null;
		var nextTokenIsRequireDefaultSymbol = false;
		var numSymbolsInsideList = 0;
		var insideGenClassImplements = false;
		var genClassImplementsParenDepth = -1;
		var genClassValueLastNodeId = -1;
		var pendingRequireMetadata:Array<String> = [];
		var pendingRequireMacrosMetadata:Array<String> = [];
		var pendingReaderCommentLineNo = -1;

		// the platform of the enclosing reader conditional, if any
		inline function platformOrNull():Null<String> {
			return insideReaderConditional && nonEmpty(currentReaderConditionalPlatform) ? currentReaderConditionalPlatform : null;
		}

		// moves the pending metadata strings and comments of a meta node into place
		function collectMetaNode(node:Node, pending:Array<String>):Void {
			for (m in NodeSearch.metadataStrings(node))
				pending.push(m);
			// comments between the metadata and the libspec are skipped along with the
			// metadata children, so collect them here as comments above the libspec
			for (c in NodeSearch.metaComments(node))
				singleLineComments.push(c);
			final bodyNode = NodeSearch.metaBody(node);
			if (bodyNode != null)
				skipNodesUntilWeReachThisId = bodyNode.id;
		}

		// skips the nodes of a just-collected value, recording where it ends
		function skipToLastNodeWithText(node:Node):Node {
			final lastNode = lastNodeWithText(node);
			skipNodesUntilWeReachThisId = lastNode.id;
			return lastNode;
		}

		while (continueParsingNsForm) {
			final node = nodesArr[idx];
			final currentNodeIsNewline = isNewline(node);
			final isTokenNode2 = isToken(node);
			final isTextNode = hasText(node);
			final nodeHasNonBlankText = hasNonBlankText(node);

			if (parenNestingDepth >= 1 && isTokenNode2 && nodeHasNonBlankText)
				numSymbolsInsideList++;

			if (parenNestingDepth == 1 && isNs(node) && numSymbolsInsideList == 1) {
				insideNsForm = true;
				nextTextNodeIsNsSymbol = true;
				nsNodeIdx = idx;
			} else if (insideNsForm && isReferClojure(node)) {
				insideReferClojureForm = true;
				referClojureParenNestingDepth = parenNestingDepth;
				sectionToAttachEolCommentsTo = "refer-clojure";
				referClojureNodeIdx = idx;
				beyondNsMetadata = true;
			} else if (insideNsForm && isRequire(node)) {
				insideRequireForm = true;
				requireFormParenNestingDepth = parenNestingDepth;
				requireFormLineNo = lineNo;
				requireNodeIdx = idx;
				beyondNsMetadata = true;
				sectionToAttachEolCommentsTo = "require";
			} else if (insideNsForm && isImport(node)) {
				insideImportForm = true;
				importFormLineNo = lineNo;
				importNodeIdx = idx;
				importNodeParenNestingDepth = parenNestingDepth;
				beyondNsMetadata = true;
				sectionToAttachEolCommentsTo = "import";
			} else if (insideNsForm && isRequireMacrosKeyword(node)) {
				insideRequireMacrosForm = true;
				requireMacrosNodeIdx = idx;
				requireMacrosLineNo = lineNo;
				requireMacrosParenNestingDepth = parenNestingDepth;
				beyondNsMetadata = true;
				sectionToAttachEolCommentsTo = "require-macros";
			} else if (insideNsForm && GenClass.isNode(node)) {
				insideGenClass = true;
				genClassNodeIdx = idx;
				beyondNsMetadata = true;
				sectionToAttachEolCommentsTo = "gen-class";
			}

			if (isParenOpener(node)) {
				parenNestingDepth++;
				numSymbolsInsideList = 0;

				// the vector directly inside a splicing reader conditional (#?@(:clj [...]))
				// holds import specs; it is not itself a package list
				final isReaderConditionalSpliceVector = insideReaderConditional
					&& readerConditionalIsSplicing
					&& parenNestingDepth == readerConditionalParenNestingDepth + 1
					&& node.text == "[";

				if (insideNsForm && isReaderConditionalOpener(node)) {
					insideReaderConditional = true;
					readerConditionalIsSplicing = node.text == "#?@(";
					currentReaderConditionalPlatform = null;
					readerConditionalParenNestingDepth = parenNestingDepth;
				} else if (insideRequireForm && requireListParenNestingDepth == -1) {
					insideRequireList = true;
					requireListParenNestingDepth = parenNestingDepth;
				} else if (insideImportForm && parenNestingDepth > importNodeParenNestingDepth && !isReaderConditionalSpliceVector) {
					insideImportPackageList = true;
				} else if (insideGenClass && genClassToggle == 1 && genClassKeyStr == "implements") {
					insideGenClassImplements = true;
					genClassImplementsParenDepth = parenNestingDepth;
					final implementsObj:Dynamic = genClassField("implements");
					if (!isArray(implementsObj.value))
						implementsObj.value = [];
				}
			} else if (isParenCloser(node)) {
				parenNestingDepth--;

				// We can assume there is only one ns form per file and exit the main
				// loop once we have finished parsing it.
				if (insideNsForm && parenNestingDepth == 0) {
					insideNsForm = false;
					nsFormEndsLineIdx = lineNo;
				}

				if (insideImportPackageList) {
					insideImportPackageList = false;
					importPackageListFirstToken = null;
				}
				if (insideRequireForm && parenNestingDepth < requireFormParenNestingDepth) {
					insideRequireForm = false;
					requireFormParenNestingDepth = -1;
				}
				if (insideReferClojureForm && parenNestingDepth < referClojureParenNestingDepth) {
					insideReferClojureForm = false;
					referClojureNodeIdx = -1;
				}

				if (insideReferClojureForm && parenNestingDepth <= referClojureParenNestingDepth) {
					collectReferClojureExcludeSymbols = false;
					collectReferClojureOnlySymbols = false;
					collectReferClojureRenameSymbols = false;
				}

				// we are finished collecting :refer symbols
				if (referIdx > 0 && parenNestingDepth <= referParenNestingDepth) {
					referIdx = -1;
					referParenNestingDepth = -1;
				}

				// we are finished collecting :rename symbols
				if (renameIdx > 0 && parenNestingDepth <= renameParenNestingDepth) {
					renameIdx = -1;
					renameParenNestingDepth = -1;
				}

				// we are finished collecting require prefix list symbols
				if (insideRequireList && parenNestingDepth < requireListParenNestingDepth) {
					insideRequireList = false;
					requireListParenNestingDepth = -1;
					nextTokenIsRequireDefaultSymbol = false;
				}

				if (insideRequireForm && requireSymbolIdx > 0)
					requireSymbolIdx = -1;

				if (insideRequireForm && insidePrefixList && prefixListParenNestingDepth != -1 && parenNestingDepth == prefixListParenNestingDepth - 1) {
					insidePrefixList = false;
					prefixListPrefix = null;
					prefixListParenNestingDepth = -1;
				}

				if (insideReaderConditional && parenNestingDepth == readerConditionalParenNestingDepth - 1) {
					insideReaderConditional = false;
					readerConditionalIsSplicing = false;
					currentReaderConditionalPlatform = null;
					readerConditionalParenNestingDepth = -1;
				}
				if (idx > referMacrosIdx && parenNestingDepth <= referMacrosParenNestingDepth) {
					referMacrosIdx = -1;
					referMacrosParenNestingDepth = -1;
				}
				if (insideImportForm && parenNestingDepth < importNodeParenNestingDepth) {
					insideImportForm = false;
					importNodeIdx = -1;
					importNodeParenNestingDepth = -1;
				}
				if (insideRequireMacrosForm && parenNestingDepth < requireMacrosParenNestingDepth) {
					insideRequireMacrosForm = false;
					requireMacrosParenNestingDepth = -1;
					requireMacrosNodeIdx = -1;
					requireMacrosAsNodeIdx = -1;
				}
				if (collectRequireExcludeSymbols && parenNestingDepth < requireExcludeSymbolParenDepth) {
					collectRequireExcludeSymbols = false;
					requireExcludeSymbolParenDepth = -1;
				}
				if (insideGenClassImplements && parenNestingDepth < genClassImplementsParenDepth) {
					insideGenClassImplements = false;
					genClassImplementsParenDepth = -1;
					genClassToggle = 0; // back to looking for a :gen-class key
					genClassValueLineNo = lineNo;
				}

				requireMacrosReferNodeIdx = -1;
				requireMacrosRenameIdx = -1;
			}

			final isCommentNode2 = isComment(node);
			final isReaderCommentNode2 = isReaderComment(node);

			// an end-of-line comment may merge onto a reader comment collected earlier on this
			// same line, but only if no libspec has been parsed in between: parsing a libspec
			// flushes singleLineComments onto that require, which closes the merge window
			// (a comment after the libspec belongs to the libspec as commentAfter, not to the
			// reader comment as commentsAbove)
			final readerCommentMergeWindowIsOpen = insideRequireForm && pendingReaderCommentLineNo == lineNo && singleLineComments.length > 0;

			if (isReaderCommentNode2) {
				insideReaderComment = true;
				idOfLastNodeInsideReaderComment = lastNodeWithText(node).id;
			}

			if (skipNodesUntilWeReachThisId > 0) {
				if (node.id == skipNodesUntilWeReachThisId) {
					skipNodesUntilWeReachThisId = -1;
					if (node.id == genClassValueLastNodeId) {
						genClassValueLineNo = lineNo;
						genClassValueLastNodeId = -1;
					}
				}

				// collect metadata attached to the next :require libspec. The meta node
				// already groups stacked metadata and its wrapped body, so skip only the
				// metadata children and let the normal require parser consume the body.
			} else if (insideRequireForm && requireSymbolIdx == -1 && node.name == "meta") {
				collectMetaNode(node, pendingRequireMetadata);

				// collect metadata attached to the next :require-macros libspec
				// (same approach as :require above)
			} else if (insideRequireMacrosForm && requireMacrosReferNodeIdx == -1 && requireMacrosRenameIdx == -1 && node.name == "meta") {
				collectMetaNode(node, pendingRequireMacrosMetadata);

				// collect ns metadata shorthand
			} else if (insideNsMetadataShorthand) {
				if (node.name == ".marker" && node.text == "^") {
					nextTokenNodeIsMetadataTrueKey = true;
				} else if (nextTokenNodeIsMetadataTrueKey && isTokenNode2) {
					if (result.nsMetadata == null)
						result.nsMetadata = [];

					final metadataObj:Dynamic = {};
					metadataObj.key = node.text;
					metadataObj.value = "true";

					result.nsMetadata.push(metadataObj);

					nextTokenNodeIsMetadataTrueKey = false;
					insideNsMetadataShorthand = false;
				}

				// collect ns metadata inside a hash map literal
			} else if (insideNsMetadataHashMap) {
				if (nextTextNodeIsMetadataKey && node.name == ".close" && node.text == "}") {
					insideNsMetadataHashMap = false;
				} else if (!nextTextNodeIsMetadataKey && node.name == ".open" && node.text == "{") {
					nextTextNodeIsMetadataKey = true;
				} else if (nextTextNodeIsMetadataKey && isTokenNode2) {
					if (result.nsMetadata == null)
						result.nsMetadata = [];

					tmpMetadataKey = node.text;
					nextTextNodeIsMetadataKey = false;

					// the next node should be a whitespace node, then collect the value for this key
					metadataValueNodeId = NodeSearch.nextNonWhitespace(nodesArr, idx + 1).id;
				} else if (node.id == metadataValueNodeId) {
					final metadataObj:Dynamic = {};
					metadataObj.key = tmpMetadataKey;
					metadataObj.value = textOf(node);

					result.nsMetadata.push(metadataObj);

					tmpMetadataKey = "";
					nextTextNodeIsMetadataKey = true;
					metadataValueNodeId = -1;

					// skip any forward nodes that we have just collected as text
					var skipCandidate:Null<Node> = node;
					while (skipCandidate != null) {
						if (skipCandidate.children != null) {
							final c = skipCandidate.children;
							skipCandidate = c.length == 0 ? null : c[c.length - 1];
							skipNodesUntilWeReachThisId = skipCandidate.id;
						} else {
							skipCandidate = null;
						}
					}
				}

				// collect ns metadata before we hit the nsSymbol
			} else if (!insideNsMetadataHashMap && !insideNsMetadataShorthand && insideNsForm && nsSymbolIdx < 0 && node.name == "meta") {
				final markerNode = NodeSearch.nextWithText(nodesArr, idx + 1);

				// NOTE: this should always be true
				if (markerNode.text == "^") {
					final nodeAfterMarker = NodeSearch.nextWithText(nodesArr, idx + 2);

					if (nodeAfterMarker != null && nodeAfterMarker.text == "{")
						insideNsMetadataHashMap = true;
					else if (nodeAfterMarker != null && isToken(nodeAfterMarker))
						insideNsMetadataShorthand = true;
				}

				// collect metadata hash map after the ns symbol
			} else if (insideNsForm
				&& idx > nsNodeIdx
				&& parenNestingDepth >= 1
				&& !beyondNsMetadata
				&& !insideReaderComment
				&& !insideNsMetadataShorthand
				&& !insideNsMetadataHashMap
				&& node.name == ".open"
				&& node.text == "{") {
				insideNsMetadataHashMap = true;
				nextTextNodeIsMetadataKey = true;

				// collect the ns symbol
			} else if (idx > nsNodeIdx && nextTextNodeIsNsSymbol && isTokenNode2 && isTextNode) {
				result.nsSymbol = node.text;
				nsSymbolIdx = idx;
				nextTextNodeIsNsSymbol = false;

				// collect reader conditional platform keyword
			} else if (insideReaderConditional && parenNestingDepth == readerConditionalParenNestingDepth && isKeyword(node)) {
				currentReaderConditionalPlatform = node.text;

				// collect single-line comments
			} else if (insideNsForm && idx > nsNodeIdx && prevNodeIsNewline && isCommentNode2) {
				singleLineComments.push(node.text);

				// merge this comment onto the pending reader comment (one that starts its own line)
				// so they travel together during sorting
			} else if (readerCommentMergeWindowIsOpen && isCommentNode2) {
				final lastCommentIdx = singleLineComments.length - 1;
				singleLineComments[lastCommentIdx] = singleLineComments[lastCommentIdx] + " " + node.text;
				// reset so a comment on a later line cannot merge onto this reader comment
				pendingReaderCommentLineNo = -1;

				// collect a reader comment that starts its own line
			} else if (insideNsForm && idx > nsNodeIdx && prevNodeIsNewline && isReaderCommentNode2) {
				singleLineComments.push(textOf(node));
				// NOTE: record the line number so that an end-of-line comment following this
				// reader comment can be merged onto it by the branch above
				pendingReaderCommentLineNo = lineNo;

				// collect comments at the end of a line
				//
				// The rule for comments and discard forms inside the ns form:
				// a comment or discard attaches to the nearest item to its left on the same line
				// (closing parens are not items, so a comment after `[a.b]))` belongs to a.b and
				// travels with it when it is sorted). If nothing is to its left on that line, it
				// is a comment above the next item (see the singleLineComments branches above).
			} else if (idx > nsNodeIdx && !prevNodeIsNewline && (isCommentNode2 || isReaderCommentNode2)) {
				var commentAtEndOfLine:String = isCommentNode2 ? node.text : textOf(node);

				// more than one discard (or a discard followed by a comment) on the same line:
				// merge them so they travel together and keep their original order
				if (lineOfLastCommentRecording == lineNo && nonEmpty(lastCommentRecorded))
					commentAtEndOfLine = lastCommentRecorded + " " + commentAtEndOfLine;
				lastCommentRecorded = commentAtEndOfLine;

				if (prefixListLineNo == lineNo) {
					if (prefixListComments.get(currentPrefixListId) == null)
						prefixListComments.set(currentPrefixListId, {});
					prefixListComments.get(currentPrefixListId).commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (requireFormLineNo == lineNo && activeRequireIdx < 0) {
					result.requireCommentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (requireFormLineNo == lineNo && activeRequireIdx >= 0) {
					reqAt(activeRequireIdx).commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (sectionToAttachEolCommentsTo == "refer-clojure" && insideReferClojureForm && result.referClojure == null) {
					result.referClojureCommentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (sectionToAttachEolCommentsTo == "refer-clojure" && result.referClojure != null) {
					result.referClojureCommentAfterForm = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (importFormLineNo == lineNo && importsObj == null) {
					result.importCommentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (importFormLineNo == lineNo) {
					importAt(activeImportPackageName).commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (requireMacrosLineNo == lineNo && activeRequireMacrosIdx < 0) {
					result.requireMacrosCommentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (requireMacrosLineNo == lineNo) {
					result.requireMacros[activeRequireMacrosIdx].commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
					// a key/value on this line wins over the :gen-class keyword on this line:
					// the comment belongs to the nearest item to its left
				} else if (genClassValueLineNo == lineNo && genClassKeyStr != null && genClassField(genClassKeyStr) != null) {
					genClassField(genClassKeyStr).commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				} else if (genClassLineNo == lineNo) {
					result.genClass.commentAfter = commentAtEndOfLine;
					lineOfLastCommentRecording = lineNo;
				}

				if (!insideNsForm && lineNo == lineOfLastCommentRecording)
					result.commentOutsideNsForm = commentAtEndOfLine;

				// discard nodes that are inside a reader comment
			} else if (insideReaderComment) {
				if (node.id == idOfLastNodeInsideReaderComment) {
					insideReaderComment = false;
					idOfLastNodeInsideReaderComment = -1;
				}

				// attach comments to the :require form
			} else if (insideRequireForm && idx == requireNodeIdx && singleLineComments.length > 0) {
				result.requireCommentsAbove = singleLineComments;
				singleLineComments = [];

				// attach comments to the :import form
			} else if (insideImportForm && idx == importNodeIdx && singleLineComments.length > 0) {
				result.importCommentsAbove = singleLineComments;
				singleLineComments = [];

				// attach comments to the :refer-clojure form
			} else if (insideReferClojureForm && idx == referClojureNodeIdx && singleLineComments.length > 0) {
				result.referClojureCommentsAbove = singleLineComments;
				singleLineComments = [];

				// collect the docstring
			} else if (insideNsForm
				&& idx > nsNodeIdx
				&& parenNestingDepth == 1
				&& !beyondNsMetadata
				&& !insideNsMetadataShorthand
				&& !insideNsMetadataHashMap
				&& isString(node)) {
				result.docstring = stringText(node);

				// collect :refer-clojure :exclude
			} else if (insideReferClojureForm && idx > referClojureNodeIdx && isExcludeKeyword(node)) {
				if (result.referClojure == null)
					result.referClojure = {};
				if (!isArray(result.referClojure.exclude))
					result.referClojure.exclude = [];
				collectReferClojureExcludeSymbols = true;

				// collect :refer-clojure :exclude symbols
			} else if (idx > referClojureNodeIdx + 1
				&& collectReferClojureExcludeSymbols
				&& parenNestingDepth >= 3
				&& isTokenNode2
				&& isTextNode
				&& result.referClojure != null
				&& isArray(result.referClojure.exclude)) {
				final symbolObj:Dynamic = {};
				symbolObj.symbol = node.text;
				final platform = platformOrNull();
				if (platform != null)
					symbolObj.platform = platform;
				result.referClojure.exclude.push(symbolObj);

				// collect :refer-clojure :only
			} else if (insideReferClojureForm && idx > referClojureNodeIdx && isOnlyKeyword(node)) {
				if (result.referClojure == null)
					result.referClojure = {};
				// NOTE: :only can appear more than once when each platform of a reader conditional
				// has its own (:refer-clojure :only [...]) form, so do not reset an existing array
				if (!isArray(result.referClojure.only))
					result.referClojure.only = [];
				collectReferClojureOnlySymbols = true;

				// collect :refer-clojure :only symbols
			} else if (idx > referClojureNodeIdx + 1
				&& collectReferClojureOnlySymbols
				&& parenNestingDepth >= 3
				&& isTokenNode2
				&& isTextNode
				&& result.referClojure != null
				&& isArray(result.referClojure.only)) {
				final symbolObj:Dynamic = {symbol: node.text};
				final platform = platformOrNull();
				if (platform != null)
					symbolObj.platform = platform;
				result.referClojure.only.push(symbolObj);

				// collect :refer-clojure :rename
			} else if (insideReferClojureForm && idx > referClojureNodeIdx && isRenameKeyword(node)) {
				if (result.referClojure == null)
					result.referClojure = {};
				if (!isArray(result.referClojure.rename))
					result.referClojure.rename = [];
				collectReferClojureRenameSymbols = true;

				// collect :refer-clojure :rename symbols
			} else if (idx > referClojureNodeIdx + 1
				&& collectReferClojureRenameSymbols
				&& parenNestingDepth >= 3
				&& isTokenNode2
				&& isTextNode
				&& result.referClojure != null
				&& isArray(result.referClojure.rename)) {
				renamesTmp.push(node.text);

				if (renamesTmp.length == 2) {
					final itm:Dynamic = {};
					itm.fromSymbol = renamesTmp[0];
					itm.toSymbol = renamesTmp[1];
					final platform = platformOrNull();
					if (platform != null)
						itm.platform = platform;
					result.referClojure.rename.push(itm);
					renamesTmp = [];
				}

				// is this :require :as ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isAsKeyword(node)) {
				nextTokenIsAsSymbol = true;

				// collect the require :as symbol
			} else if (idx > requireNodeIdx && insideRequireForm && nextTokenIsAsSymbol && isTokenNode2 && isTextNode) {
				nextTokenIsAsSymbol = false;
				reqAt(activeRequireIdx).as = node.text;

				// collect :require-macros :refer symbols
			} else if (insideRequireMacrosForm && requireMacrosReferNodeIdx != -1 && idx > requireMacrosReferNodeIdx && isTokenNode2 && isTextNode) {
				final rm:Dynamic = result.requireMacros[activeRequireMacrosIdx];
				if (!isArray(rm.refer))
					rm.refer = [];

				final referObj:Dynamic = {};
				referObj.symbol = node.text;
				final platform = platformOrNull();
				if (platform != null)
					referObj.platform = platform;
				rm.refer.push(referObj);

				// collect :require-macros :as symbol
			} else if (insideRequireMacrosForm && requireMacrosAsNodeIdx != -1 && idx > requireMacrosAsNodeIdx && isTokenNode2 && isTextNode) {
				result.requireMacros[activeRequireMacrosIdx].as = node.text;
				requireMacrosAsNodeIdx = -1;

				// collect :require-macros :rename
			} else if (insideRequireMacrosForm && requireMacrosRenameIdx != -1 && idx > requireMacrosRenameIdx && isTokenNode2 && isTextNode) {
				final rm:Dynamic = result.requireMacros[activeRequireMacrosIdx];
				if (!isArray(rm.rename))
					rm.rename = [];

				renamesTmp.push(node.text);

				if (renamesTmp.length == 2) {
					final itm:Dynamic = {};
					itm.fromSymbol = renamesTmp[0];
					itm.toSymbol = renamesTmp[1];
					final platform = platformOrNull();
					if (platform != null)
						itm.platform = platform;
					rm.rename.push(itm);
					renamesTmp = [];
				}

				// :require-macros :refer
			} else if (insideRequireMacrosForm && idx > requireMacrosNodeIdx && isReferKeyword(node)) {
				requireMacrosReferNodeIdx = idx;

				// :require-macros :as
			} else if (insideRequireMacrosForm && idx > requireMacrosNodeIdx && isAsKeyword(node)) {
				requireMacrosAsNodeIdx = idx;

				// :require-macros :rename
			} else if (insideRequireMacrosForm && idx > requireMacrosNodeIdx && isRenameKeyword(node)) {
				requireMacrosRenameIdx = idx;
				renamesTmp = [];

				// collect :require-macros symbol
			} else if (insideRequireMacrosForm && idx > requireMacrosNodeIdx && isTokenNode2 && isTextNode) {
				if (result.requireMacros == null) {
					result.requireMacros = [];

					// add commentsAbove to the :require-macros form if possible
					if (singleLineComments.length > 0) {
						result.requireMacrosCommentsAbove = singleLineComments;
						singleLineComments = [];
					}
				}

				final reqObj:Dynamic = {};
				if (pendingRequireMacrosMetadata.length > 0) {
					reqObj.metadata = pendingRequireMacrosMetadata;
					pendingRequireMacrosMetadata = [];
				}
				reqObj.symbol = node.text;

				// store the comments above this line
				if (singleLineComments.length > 0) {
					reqObj.commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				// add reader conditional platform
				final platform = platformOrNull();
				if (platform != null)
					reqObj.platform = platform;

				result.requireMacros.push(reqObj);
				activeRequireMacrosIdx++;
				requireMacrosLineNo = lineNo;

				// is this :include-macros ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isIncludeMacros(node)) {
				insideIncludeMacros = true;

				// collect :include-macros boolean
			} else if (insideIncludeMacros && isTokenNode2 && isBoolean(node)) {
				reqAt(activeRequireIdx).includeMacros = node.text == "true";
				insideIncludeMacros = false;

				// is this :refer-macros ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isReferMacrosKeyword(node)) {
				referMacrosIdx = idx;
				referMacrosParenNestingDepth = parenNestingDepth;

				// collect :refer-macros symbols
			} else if (idx > referMacrosIdx
				&& insideRequireForm
				&& parenNestingDepth == referMacrosParenNestingDepth + 1
				&& isTokenNode2
				&& isTextNode) {
				final req = reqAt(activeRequireIdx);
				if (!isArray(req.referMacros))
					req.referMacros = [];
				req.referMacros.push(node.text);

				// is this :require :refer ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isReferKeyword(node)) {
				referIdx = idx;
				referParenNestingDepth = parenNestingDepth;

				// is this :require :default ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isDefaultKeyword(node)) {
				nextTokenIsRequireDefaultSymbol = true;

				// collect :require :exclude symbols
			} else if (idx > requireNodeIdx
				&& insideRequireForm
				&& isTokenNode2
				&& collectRequireExcludeSymbols
				&& parenNestingDepth > requireExcludeSymbolParenDepth) {
				final symbolObj:Dynamic = {symbol: node.text};
				reqAt(activeRequireIdx).exclude.push(symbolObj);

				// is this :require :exclude ?
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isExcludeKeyword(node)) {
				reqAt(activeRequireIdx).exclude = [];
				collectRequireExcludeSymbols = true;
				requireExcludeSymbolParenDepth = parenNestingDepth;

				// :require :as-alias
			} else if (idx > requireNodeIdx && insideRequireForm && isTokenNode2 && isAsAliasKeyword(node)) {
				final nextSymbol = findNextTokenInsideRequireForm(nodesArr, idx + 1);
				reqAt(activeRequireIdx).asAlias = nextSymbol.text;

				// collect :refer :all
			} else if (idx > referIdx && insideRequireForm && isTokenNode2 && isAll(node)) {
				reqAt(activeRequireIdx).refer = "all";

				// collect :refer :default symbol
			} else if (idx > referIdx && insideRequireForm && isTokenNode2 && nextTokenIsRequireDefaultSymbol) {
				Reflect.setField(reqAt(activeRequireIdx), "default", node.text);
				nextTokenIsRequireDefaultSymbol = false;

				// :rename keyword inside a :require list
			} else if (insideRequireForm && insideRequireList && renameIdx == -1 && isRenameKeyword(node)) {
				renameIdx = idx;
				renameParenNestingDepth = parenNestingDepth;
				renamesTmp = [];

				// collect :require renames
			} else if (insideRequireForm
				&& insideRequireList
				&& renameIdx > 0
				&& idx > renameIdx
				&& parenNestingDepth > renameParenNestingDepth
				&& isTokenNode2
				&& isTextNode) {
				renamesTmp.push(node.text);

				if (renamesTmp.length == 2) {
					final itm:Dynamic = {};
					itm.fromSymbol = renamesTmp[0];
					itm.toSymbol = renamesTmp[1];
					final platform = platformOrNull();
					if (platform != null)
						itm.platform = platform;

					final req = reqAt(activeRequireIdx);
					if (!isArray(req.rename))
						req.rename = [];
					req.rename.push(itm);

					renamesTmp = [];
				}

				// collect :require :refer symbols
			} else if (idx > referIdx
				&& insideRequireForm
				&& referParenNestingDepth != -1
				&& parenNestingDepth > referParenNestingDepth
				&& isTokenNode2
				&& isTextNode) {
				final req = reqAt(activeRequireIdx);
				if (!isArray(req.refer))
					req.refer = [];
				final referObj:Dynamic = {symbol: node.text};
				req.refer.push(referObj);

				// collect :require symbol not inside of a list / vector
			} else if (insideRequireForm && !insideRequireList && idx > requireNodeIdx && isTokenNode2 && isTextNode && requireSymbolIdx == -1
				&& !isKeyword(node)) {
				if (!isArray(result.requires))
					result.requires = [];

				final requireObj:Dynamic = {};
				if (pendingRequireMetadata.length > 0) {
					requireObj.metadata = pendingRequireMetadata;
					pendingRequireMetadata = [];
				}
				requireObj.symbol = node.text;
				result.requires.push(requireObj);
				activeRequireIdx++;
				requireFormLineNo = lineNo;

				// attach comments from the lines above this require
				if (singleLineComments.length > 0) {
					reqAt(activeRequireIdx).commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				// add platform if we are inside a Reader Conditional
				final platform = platformOrNull();
				if (platform != null)
					reqAt(activeRequireIdx).platform = platform;

				// collect symbols inside of a prefix list
			} else if (insidePrefixList && isTokenNode2 && isTextNode) {
				if (!isArray(result.requires))
					result.requires = [];

				final namespace = prefixListPrefix + "." + node.text;

				final requireObj:Dynamic = {};
				if (pendingRequireMetadata.length > 0) {
					requireObj.metadata = pendingRequireMetadata;
					pendingRequireMetadata = [];
				}
				requireObj.prefixListId = currentPrefixListId;
				requireObj.symbol = namespace;
				result.requires.push(requireObj);
				activeRequireIdx++;
				requireSymbolIdx = idx;
				requireFormLineNo = lineNo;

				// collect :require symbol inside of a list / vector
			} else if (insideRequireForm
				&& insideRequireList
				&& idx > requireNodeIdx
				&& referIdx == -1
				&& renameIdx == -1
				&& isTokenNode2
				&& isTextNode
				&& requireSymbolIdx == -1
				&& !isKeyword(node)) {
				if (!isArray(result.requires))
					result.requires = [];

				// five possibilities for a :require import:
				// - require symbol not inside of list / vector
				// - require symbol inside a list / vector, followed by nothing
				// - require symbol for a prefix list (need to examine the following symbols in order to know this)
				// - require symbol followed by :as
				// - require symbol followed by :refer

				final nextTokenInsideRequireForm = findNextTokenInsideRequireForm(nodesArr, idx + 1);
				final isPrefixList = nextTokenInsideRequireForm != null && !isKeyword(nextTokenInsideRequireForm);

				if (isPrefixList) {
					final prefixListId = ++idCounter;
					insidePrefixList = true;
					prefixListParenNestingDepth = parenNestingDepth;
					prefixListLineNo = lineNo;
					prefixListPrefix = node.text;
					currentPrefixListId = prefixListId;

					// store the comments above this line
					// we will attach them to the first ns imported by this prefix list later
					if (singleLineComments.length > 0) {
						final itm:Dynamic = {commentsAbove: singleLineComments};
						prefixListComments.set(prefixListId, itm);
						singleLineComments = [];
					}
				} else {
					final requireObj:Dynamic = {};
					if (pendingRequireMetadata.length > 0) {
						requireObj.metadata = pendingRequireMetadata;
						pendingRequireMetadata = [];
					}
					requireObj.symbol = node.text;
					result.requires.push(requireObj);
					activeRequireIdx++;
					requireSymbolIdx = idx;
					requireFormLineNo = lineNo;
					insidePrefixList = false;
					prefixListLineNo = -1;

					// attach comments from the lines above this require
					if (singleLineComments.length > 0) {
						reqAt(activeRequireIdx).commentsAbove = singleLineComments;
						singleLineComments = [];
					}

					// add platform if we are inside a Reader Conditional
					final platform = platformOrNull();
					if (platform != null)
						reqAt(activeRequireIdx).platform = platform;
				}

				// collect require Strings in ClojureScript
			} else if (insideRequireForm && insideRequireList && idx > requireNodeIdx && isString(node)) {
				if (!isArray(result.requires))
					result.requires = [];

				final requireObj:Dynamic = {};
				if (pendingRequireMetadata.length > 0) {
					requireObj.metadata = pendingRequireMetadata;
					pendingRequireMetadata = [];
				}
				result.requires.push(requireObj);
				activeRequireIdx++;
				requireFormLineNo = lineNo;

				// attach comments from the lines above this require
				if (singleLineComments.length > 0) {
					reqAt(activeRequireIdx).commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				// add platform if we are inside a Reader Conditional
				final platform = platformOrNull();
				if (platform != null)
					reqAt(activeRequireIdx).platform = platform;

				reqAt(activeRequireIdx).symbol = '"' + stringText(node) + '"';
				reqAt(activeRequireIdx).symbolIsString = true;

				// collect :import packages not inside of a list or vector
			} else if (insideImportForm && idx > importNodeIdx && !insideImportPackageList && isTokenNode2 && isTextNode) {
				if (importsObj == null)
					importsObj = [];

				if (StringTools.startsWith(node.text, ":"))
					throw new haxe.Exception(":import " + node.text + " must be a class symbol.");

				final packageParsed = parseJavaPackageWithClass(node.text);
				final packageName = packageParsed.pkg;
				final className = packageParsed.className;

				if (!importsObj.exists(packageName)) {
					importsObj.set(packageName, {classes: []});
					importKeys.push(packageName);
				}

				importAt(packageName).classes.push(className);
				activeImportPackageName = packageName;
				importFormLineNo = lineNo;

				if (singleLineComments.length > 0) {
					importAt(packageName).commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				// add platform if we are inside a Reader Conditional
				final platform = platformOrNull();
				if (platform != null)
					importAt(packageName).platform = platform;

				// collect :import classes inside of a list or vector
			} else if (insideImportPackageList && isTokenNode2 && isTextNode) {
				if (importPackageListFirstToken == null) {
					final packageName = node.text;
					importPackageListFirstToken = packageName;
					activeImportPackageName = packageName;
					importFormLineNo = lineNo;

					if (importsObj == null)
						importsObj = [];

					if (!importsObj.exists(packageName)) {
						importsObj.set(packageName, {classes: []});
						importKeys.push(packageName);
					}

					if (singleLineComments.length > 0) {
						importAt(packageName).commentsAbove = singleLineComments;
						singleLineComments = [];
					}

					// add platform if we are inside a Reader Conditional
					final platform = platformOrNull();
					if (platform != null)
						importAt(packageName).platform = platform;
				} else {
					importAt(importPackageListFirstToken).classes.push(node.text);
				}

				// collect gen-class :implements symbols
			} else if (insideGenClass
				&& insideGenClassImplements
				&& idx > genClassNodeIdx
				&& genClassToggle == 1
				&& genClassKeyStr == "implements"
				&& (isTokenNode2 || isString(node) || node.name == "meta")) {
				final symbol = GenClass.symbolText(node);
				if (!nonEmpty(symbol))
					throw new haxe.Exception(":gen-class :implements values must be symbols or strings.");

				final symbolObj:Dynamic = {symbol: symbol};
				final platform = platformOrNull();
				if (platform != null)
					symbolObj.platform = platform;
				genClassField("implements").value.push(symbolObj);

				if (!isTokenNode2)
					skipToLastNodeWithText(node);

				// we are on the :gen-class node
			} else if (insideGenClass && idx == genClassNodeIdx) {
				result.genClass = {};
				result.genClass.isEmpty = true;

				// add platform if we are inside a Reader Conditional
				final platform = platformOrNull();
				if (platform != null)
					result.genClass.platform = platform;

				// add commentsAbove
				if (singleLineComments.length > 0) {
					result.genClass.commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				genClassLineNo = lineNo;
				// :gen-class key like :main, :name, :state, :init, etc
			} else if (insideGenClass && idx > genClassNodeIdx && isTextNode && genClassToggle == 0 && GenClass.isKeyword(node)) {
				result.genClass.isEmpty = false;

				genClassKeyStr = node.text.substr(1);
				Reflect.setField(result.genClass, genClassKeyStr, {});

				// add commentsAbove if possible
				if (singleLineComments.length > 0) {
					genClassField(genClassKeyStr).commentsAbove = singleLineComments;
					singleLineComments = [];
				}

				// genClassToggle = 0 means we are looking for a key
				// genClassToggle = 1 means we are looking for a value
				genClassToggle = 1;

				// :gen-class :prefix value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "prefix" && isString(node)) {
				genClassField("prefix").value = GenClass.symbolText(node);
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// :gen-class name-like value with metadata
				// NOTE: :name is the only key where metadata is meaningful to gen-class (class
				// annotations), but metadata is legal reader syntax on any of these values and
				// must be preserved, not dropped
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && GenClass.isNameKey(genClassKeyStr) && node.name == "meta") {
				final valueForm = GenClass.splitMetadataForm(node);
				final value = GenClass.symbolText(valueForm.bodyNode);
				if (!nonEmpty(value))
					throw new haxe.Exception(":gen-class :" + genClassKeyStr + " must be a symbol or string.");

				if (nonEmpty(valueForm.metadata))
					genClassField(genClassKeyStr).metadata = valueForm.metadata;
				genClassField(genClassKeyStr).value = value;
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// other :gen-class name-like values
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && GenClass.isNameKey(genClassKeyStr)
				&& (isTokenNode2 || isString(node))) {
				genClassField(genClassKeyStr).value = GenClass.symbolText(node);
				genClassToggle = 0;

				if (isString(node))
					genClassValueLastNodeId = skipToLastNodeWithText(node).id;
				else
					genClassValueLineNo = lineNo;

				// :gen-class :constructors value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "constructors" && isMapLiteral(node)) {
				genClassField("constructors").value = GenClass.parseConstructors(node);
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// :gen-class :methods value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "methods" && isVectorLiteral(node)) {
				genClassField("methods").value = GenClass.parseMethods(node);
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// invalid :gen-class :methods value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "methods"
				&& hasTextAndNotWhitespace(node)) {
				throw new haxe.Exception(":gen-class :methods must be a vector of method vectors.");

				// :gen-class :exposes value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "exposes" && isMapLiteral(node)) {
				genClassField("exposes").value = GenClass.parseExposes(node);
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// invalid :gen-class :exposes value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "exposes"
				&& hasTextAndNotWhitespace(node)) {
				throw new haxe.Exception(":gen-class :exposes must be a map of protected-field names to accessor maps.");

				// :gen-class :exposes-methods value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "exposes-methods"
				&& isMapLiteral(node)) {
				genClassField("exposes-methods").value = GenClass.parseExposesMethods(node);
				genClassToggle = 0;

				genClassValueLastNodeId = skipToLastNodeWithText(node).id;

				// invalid :gen-class :exposes-methods value
			} else if (insideGenClass && idx > genClassNodeIdx && genClassToggle == 1 && genClassKeyStr == "exposes-methods"
				&& hasTextAndNotWhitespace(node)) {
				throw new haxe.Exception(":gen-class :exposes-methods must be a map of superclass-method names to exposed names.");

				// :main, :load-impl-ns
			} else if (insideGenClass
				&& idx > genClassNodeIdx
				&& isTextNode
				&& isTokenNode2
				&& genClassToggle == 1
				&& GenClass.isBooleanKey(genClassKeyStr)) {
				if (node.text == "true") {
					genClassField(genClassKeyStr).value = true;
					genClassToggle = 0;
					genClassValueLineNo = lineNo;
				} else if (node.text == "false") {
					genClassField(genClassKeyStr).value = false;
					genClassToggle = 0;
					genClassValueLineNo = lineNo;
				} else {
					// FIXME: throw here? this is almost certainly an error in the source
				}

				// throw an error if we encounter :use
			} else if (insideNsForm && isTokenNode2 && parenNestingDepth >= 1 && isUse(node)) {
				throw new haxe.Exception("Standard Clojure Style does not support :use inside of the ns form. Please refactor with :require as appropriate.");
			}

			// increment the lineNo for the next node if we are on a newline node
			// NOTE: this lineNo variable does not account for newlines inside of multi-line strings
			// but we can ignore that for the purposes of ns parsing here
			if (currentNodeIsNewline)
				lineNo++;
			prevNodeIsNewline = currentNodeIsNewline;

			// increment to look at the next node
			idx++;

			// exit if we are at the end of the nodes
			if (idx >= numNodes) {
				continueParsingNsForm = false;
				// exit if we have finished parsing the ns form
			} else if (nsNodeIdx > 0 && !insideNsForm && lineNo >= nsFormEndsLineIdx + 2) {
				continueParsingNsForm = false;
			}
		} // end main ns parsing node loop

		return sortNsResult(result, importsObj, importKeys, prefixListComments);
	}
}
