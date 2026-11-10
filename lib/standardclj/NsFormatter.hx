package standardclj;

/**
	Prints the parsed ns data produced by `NsParser.parse`. The data is a
	Dynamic object shaped like upstream's `parseNs` result; absent fields read
	as null, which is treated like JavaScript's `undefined`.
**/
class NsFormatter {
	static final genClassKeys = [
		"name", "extends", "implements", "init", "constructors", "post-init", "methods", "main", "factory", "state", "exposes", "exposes-methods",
		"prefix", "impl-ns", "load-impl-ns"
	];

	// -------------------------------------------------------------------------
	// Dynamic helpers

	static inline function get(o:Dynamic, key:String):Dynamic {
		return o == null ? null : Reflect.field(o, key);
	}

	/** JavaScript truthiness. **/
	static function truthy(x:Dynamic):Bool {
		return x != null && x != false && x != "" && x != 0;
	}

	static function str(x:Dynamic):String {
		return x == null ? "undefined" : Std.string(x);
	}

	static function isStr(x:Dynamic):Bool {
		return Std.isOfType(x, String);
	}

	static function isStringWithChars(x:Dynamic):Bool {
		return isStr(x) && x != "";
	}

	static function isArr(x:Dynamic):Bool {
		return Std.isOfType(x, Array);
	}

	static function size(a:Dynamic):Int {
		return isArr(a) ? (a : Array<Dynamic>).length : 0;
	}

	static function arr(a:Dynamic):Array<Dynamic> {
		return isArr(a) ? a : [];
	}

	static function pluck(a:Array<Dynamic>, key:String):Array<String> {
		return [for (x in a) str(get(x, key))];
	}

	static function join(a:Array<Dynamic>, sep:String):String {
		return [for (x in a) str(x)].join(sep);
	}

	static function spaces(n:Int):String {
		return StringTools.lpad("", " ", n);
	}

	static function printCommentsAbove(out:String, commentsAbove:Dynamic, indentation:String):String {
		for (c in arr(commentsAbove))
			out += indentation + str(c) + "\n";
		return out;
	}

	// -------------------------------------------------------------------------
	// Platforms

	/** A sorted array of the platform strings found on items in `items`, with :default last. **/
	static function getPlatformsFromArray(items:Array<Dynamic>):Array<String> {
		var hasDefault = false;
		final platforms:Array<String> = [];
		for (itm in items) {
			final p:Dynamic = get(itm, "platform");
			if (truthy(p)) {
				if (p == ":default")
					hasDefault = true;
				else if (platforms.indexOf(str(p)) < 0)
					platforms.push(str(p));
			}
		}
		platforms.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		if (hasDefault)
			platforms.push(":default");
		return platforms;
	}

	/** True if there is at most one require per platform. **/
	static function onlyOneRequirePerPlatform(reqs:Array<Dynamic>):Bool {
		final seen:Array<String> = [];
		for (r in reqs) {
			final p:Dynamic = get(r, "platform");
			if (isStr(p) && p != "") {
				if (seen.indexOf(p) >= 0)
					return false;
				seen.push(p);
			}
		}
		return true;
	}

	/** Filters on the platform key. A null platform selects items without a platform. **/
	static function filterOnPlatform(items:Array<Dynamic>, platform:Null<String>):Array<Dynamic> {
		return items.filter(itm -> {
			final p:Dynamic = get(itm, "platform");
			if (platform == null)
				!truthy(p);
			else
				isStr(p) && p == platform;
		});
	}

	// -------------------------------------------------------------------------
	// Require and import lines

	static function formatImportKeyword(ns:Dynamic, indentation:String):String {
		var out = printCommentsAbove("", get(ns, "importCommentsAbove"), indentation);
		out += indentation + "(:import";
		final after:Dynamic = get(ns, "importCommentAfter");
		if (isStringWithChars(after))
			out += " " + after;
		return out;
	}

	static function formatRequireLine(req:Dynamic, initialIndentation:String, metadataInline:Bool):String {
		var out = "";
		var requireIndentation = initialIndentation;

		out = printCommentsAbove(out, get(req, "commentsAbove"), initialIndentation);

		final metadata:Dynamic = get(req, "metadata");
		if (size(metadata) > 0) {
			out += initialIndentation + join(metadata, " ");
			if (metadataInline) {
				out += " ";
				requireIndentation = "";
			} else {
				out += "\n";
			}
		}

		out += requireIndentation + "[" + str(get(req, "symbol"));

		final as:Dynamic = get(req, "as");
		final asAlias:Dynamic = get(req, "asAlias");
		if (isStringWithChars(as))
			out += " :as " + as;
		else if (isStringWithChars(asAlias))
			out += " :as-alias " + asAlias;

		final def:Dynamic = get(req, "default");
		if (isStringWithChars(def))
			out += " :default " + def;

		// NOTE: this will not work if the individual :refer symbols are wrapped in a reader conditional
		final refer:Dynamic = get(req, "refer");
		if (size(refer) > 0)
			out += " :refer [" + pluck(arr(refer), "symbol").join(" ") + "]";
		else if (refer == "all")
			out += " :refer :all";

		// NOTE: this will not work if the individual :exclude symbols are wrapped in a reader conditional
		final exclude:Dynamic = get(req, "exclude");
		if (size(exclude) > 0)
			out += " :exclude [" + pluck(arr(exclude), "symbol").join(" ") + "]";

		final includeMacros:Dynamic = get(req, "includeMacros");
		if (includeMacros == true)
			out += " :include-macros true";
		else if (includeMacros == false)
			out += " :include-macros false";

		final referMacros:Dynamic = get(req, "referMacros");
		if (size(referMacros) > 0)
			out += " :refer-macros [" + join(arr(referMacros), " ") + "]";

		final rename:Dynamic = get(req, "rename");
		if (size(rename) > 0)
			out += " :rename {" + formatRenamesList(arr(rename)) + "}";

		return out + "]";
	}

	// -------------------------------------------------------------------------
	// :refer-clojure

	/** The available :refer-clojure keys, in the order :exclude, :only, :rename. **/
	static function getReferClojureKeys(referClojure:Dynamic):Array<String> {
		final keys = [];
		if (truthy(referClojure)) {
			if (truthy(get(referClojure, "exclude")))
				keys.push(":exclude");
			if (truthy(get(referClojure, "only")))
				keys.push(":only");
			if (truthy(get(referClojure, "rename")))
				keys.push(":rename");
		}
		return keys;
	}

	static function formatKeywordFollowedByListOfSymbols(kwd:String, symbols:Array<Dynamic>):String {
		return kwd + " [" + join(symbols, " ") + "]";
	}

	static function formatRenamesList(itms:Array<Dynamic>):String {
		return [for (i in itms) str(get(i, "fromSymbol")) + " " + str(get(i, "toSymbol"))].join(", ");
	}

	/** "(:refer-clojure" followed by the comment from the keyword line, if there is one. **/
	static function formatReferClojureKeyword(ns:Dynamic):String {
		final c:Dynamic = get(ns, "referClojureCommentAfter");
		return isStringWithChars(c) ? "(:refer-clojure " + c : "(:refer-clojure";
	}

	/** A newline plus indentation when the keyword has a comment, otherwise a space. **/
	static function referClojureKeySeparator(ns:Dynamic, keyIndentation:String):String {
		return isStringWithChars(get(ns, "referClojureCommentAfter")) ? "\n" + keyIndentation : " ";
	}

	static function formatReferClojureSingleKeyword(ns:Dynamic, excludeOrOnly:String):String {
		final symbolsArr:Array<Dynamic> = arr(get(get(ns, "referClojure"), excludeOrOnly));
		final kwd = ":" + excludeOrOnly;
		final commentsAbove = get(ns, "referClojureCommentsAbove");

		final platforms = getPlatformsFromArray(symbolsArr);
		final numPlatforms = platforms.length;
		final symbolsForAllPlatforms = pluck(filterOnPlatform(symbolsArr, null), "symbol");
		final numSymbolsForAllPlatforms = symbolsForAllPlatforms.length;

		// there are no reader conditionals: print all of the symbols
		if (numPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  " + formatReferClojureKeyword(ns);
			s += referClojureKeySeparator(ns, "    ");
			s += formatKeywordFollowedByListOfSymbols(kwd, symbolsForAllPlatforms);
			return s + ")";
		}
		// all symbols are for a single platform: wrap the entire (:refer-clojure) in a single reader conditional
		else if (numPlatforms == 1 && numSymbolsForAllPlatforms == 0) {
			var s = "\n  #?(" + platforms[0] + "\n";
			s = printCommentsAbove(s, commentsAbove, "     ");
			s += "     " + formatReferClojureKeyword(ns);
			s += referClojureKeySeparator(ns, "       ");
			s += formatKeywordFollowedByListOfSymbols(kwd, pluck(symbolsArr, "symbol"));
			return s + "))";
		}
		// all symbols are for specific platforms across multiple platforms:
		// wrap a separate (:refer-clojure) per platform inside #?(...)
		else if (numPlatforms > 1 && numSymbolsForAllPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  #?(";
			for (i in 0...numPlatforms) {
				final platform = platforms[i];
				final symbolsForPlatform = pluck(filterOnPlatform(symbolsArr, platform), "symbol");
				if (i == 0) {
					s += platform + " " + formatReferClojureKeyword(ns);
					// the first key sits two columns inside its opening paren: "  #?(<platform> ("
					s += referClojureKeySeparator(ns, spaces(platform.length + 8));
				} else {
					s += "\n     " + platform + " (:refer-clojure ";
				}
				s += formatKeywordFollowedByListOfSymbols(kwd, symbolsForPlatform);
				s += ")";
			}
			return s + ")";
		}
		// a mix of symbols for all platforms and some for specific platforms
		else {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  " + formatReferClojureKeyword(ns);
			s += "\n    " + kwd + " [" + symbolsForAllPlatforms.join(" ");

			if (kwd == ":exclude")
				s += "\n" + spaces(14);
			else if (kwd == ":only")
				s += "\n" + spaces(11);

			s += "#?@(";
			for (i in 0...numPlatforms) {
				final platform = platforms[i];
				final symbolsForPlatform = pluck(filterOnPlatform(symbolsArr, platform), "symbol");
				s += formatKeywordFollowedByListOfSymbols(platform, symbolsForPlatform);
				if (i + 1 != numPlatforms) {
					if (kwd == ":exclude")
						s += "\n" + spaces(18);
					else if (kwd == ":only")
						s += "\n" + spaces(15);
				}
			}
			return s + ")])";
		}
	}

	static function formatReferClojure(ns:Dynamic):String {
		final referClojure = get(ns, "referClojure");
		final keys = getReferClojureKeys(referClojure);
		final commentsAbove = get(ns, "referClojureCommentsAbove");

		if (keys.length == 0)
			return "";
		else if (keys.length == 1 && keys[0] == ":exclude")
			return formatReferClojureSingleKeyword(ns, "exclude");
		else if (keys.length == 1 && keys[0] == ":only")
			return formatReferClojureSingleKeyword(ns, "only");
		else if (keys.length == 1 && keys[0] == ":rename") {
			final renames:Array<Dynamic> = arr(get(referClojure, "rename"));
			final platforms = getPlatformsFromArray(renames);
			final numPlatforms = platforms.length;
			final nonPlatformSpecificRenames = filterOnPlatform(renames, null);
			final allRenamesForSamePlatform = nonPlatformSpecificRenames.length == 0 && platforms.length > 0;

			if (numPlatforms == 0) {
				var s = printCommentsAbove("\n", commentsAbove, "  ");
				s += "  " + formatReferClojureKeyword(ns);
				s += referClojureKeySeparator(ns, "    ") + ":rename {";
				return s + formatRenamesList(renames) + "})";
			} else if (numPlatforms == 1 && allRenamesForSamePlatform) {
				var s = "\n  #?(" + platforms[0] + "\n";
				s = printCommentsAbove(s, commentsAbove, "     ");
				s += "     " + formatReferClojureKeyword(ns);
				s += referClojureKeySeparator(ns, "       ") + ":rename {";
				return s + formatRenamesList(renames) + "}))";
			} else {
				var s = "\n  " + formatReferClojureKeyword(ns) + "\n    :rename {";
				s += formatRenamesList(nonPlatformSpecificRenames);
				s += "\n             #?@(";
				for (i in 0...numPlatforms) {
					final platformStr = platforms[i];
					if (i != 0)
						s += "\n                 ";
					s += platformStr + " [";
					s += formatRenamesList(filterOnPlatform(renames, platformStr));
					s += "]";
				}
				return s + ")})";
			}
		} else {
			return formatReferClojureMultipleKeywords(ns);
		}
	}

	/** Every :exclude, :only, and :rename item. **/
	static function allReferClojureItems(referClojure:Dynamic):Array<Dynamic> {
		var itms = [];
		for (key in ["exclude", "only", "rename"])
			itms = itms.concat(arr(get(referClojure, key)));
		return itms;
	}

	/**
		The :refer-clojure keys and their items for one platform on a single line,
		ie: ":exclude [a b] :rename {x y}". A null platform means items that are not
		platform-specific.
	**/
	static function formatReferClojureKeysOnOneLine(referClojure:Dynamic, platform:Null<String>):String {
		final parts = [];

		final exclude:Dynamic = get(referClojure, "exclude");
		if (isArr(exclude)) {
			final symbols = pluck(filterOnPlatform(exclude, platform), "symbol");
			if (symbols.length > 0)
				parts.push(formatKeywordFollowedByListOfSymbols(":exclude", symbols));
		}

		final only:Dynamic = get(referClojure, "only");
		if (isArr(only)) {
			final symbols = pluck(filterOnPlatform(only, platform), "symbol");
			if (symbols.length > 0)
				parts.push(formatKeywordFollowedByListOfSymbols(":only", symbols));
		}

		final rename:Dynamic = get(referClojure, "rename");
		if (isArr(rename)) {
			final renames = filterOnPlatform(rename, platform);
			if (renames.length > 0)
				parts.push(":rename {" + formatRenamesList(renames) + "}");
		}

		return parts.join(" ");
	}

	/**
		One :refer-clojure key where the items for specific platforms are spliced into
		the collection with #?@( ... ). The key is assumed to start at column 4.
		`platformGroups` is an array of { platform, txt }.
	**/
	static function formatReferClojureKeyWithSplices(kwd:String, openBracket:String, closeBracket:String, allPlatformsTxt:String,
			platformGroups:Array<{platform:String, txt:String}>):String {
		final kwdPrefix = kwd + " " + openBracket;
		var s = kwdPrefix + allPlatformsTxt;

		final numGroups = platformGroups.length;
		if (numGroups > 0) {
			final spliceIndent = 4 + kwdPrefix.length;
			if (allPlatformsTxt != "")
				s += "\n" + spaces(spliceIndent);
			s += "#?@(";
			for (i in 0...numGroups) {
				final group = platformGroups[i];
				s += group.platform + " [" + group.txt + "]";
				if (i + 1 < numGroups)
					s += "\n" + spaces(spliceIndent + 4);
			}
			s += ")";
		}

		return s + closeBracket;
	}

	static function referClojureSymbolPlatformGroups(symbolsArr:Array<Dynamic>):Array<{platform:String, txt:String}> {
		return [
			for (p in getPlatformsFromArray(symbolsArr))
				{platform: p, txt: pluck(filterOnPlatform(symbolsArr, p), "symbol").join(" ")}
		];
	}

	static function referClojureRenamePlatformGroups(renamesArr:Array<Dynamic>):Array<{platform:String, txt:String}> {
		return [
			for (p in getPlatformsFromArray(renamesArr))
				{platform: p, txt: formatRenamesList(filterOnPlatform(renamesArr, p))}
		];
	}

	/** A :refer-clojure form that has more than one of :exclude, :only, :rename. **/
	static function formatReferClojureMultipleKeywords(ns:Dynamic):String {
		final rc = get(ns, "referClojure");
		final exclude:Array<Dynamic> = arr(get(rc, "exclude"));
		final only:Array<Dynamic> = arr(get(rc, "only"));
		final rename:Array<Dynamic> = arr(get(rc, "rename"));
		final commentsAbove = get(ns, "referClojureCommentsAbove");

		final allItms = allReferClojureItems(rc);
		final platforms = getPlatformsFromArray(allItms);
		final numPlatforms = platforms.length;
		final numItmsForAllPlatforms = filterOnPlatform(allItms, null).length;

		// there are no reader conditionals: put each key on its own line
		if (numPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  " + formatReferClojureKeyword(ns);

			if (truthy(get(rc, "exclude")) && exclude.length > 0)
				s += "\n    " + formatKeywordFollowedByListOfSymbols(":exclude", pluck(exclude, "symbol"));
			if (truthy(get(rc, "only")) && only.length > 0)
				s += "\n    " + formatKeywordFollowedByListOfSymbols(":only", pluck(only, "symbol"));
			if (truthy(get(rc, "rename")) && rename.length > 0)
				s += "\n    :rename {" + formatRenamesList(rename) + "}";

			return s + ")";
		}
		// every item is for a single platform: wrap the entire (:refer-clojure) in a single reader conditional
		else if (numPlatforms == 1 && numItmsForAllPlatforms == 0) {
			var s = "\n  #?(" + platforms[0] + "\n";
			s = printCommentsAbove(s, commentsAbove, "     ");
			s += "     " + formatReferClojureKeyword(ns);
			s += referClojureKeySeparator(ns, "       ");
			s += formatReferClojureKeysOnOneLine(rc, platforms[0]);
			return s + "))";
		}
		// every item is for a specific platform, across multiple platforms:
		// wrap a separate (:refer-clojure) per platform inside #?(...)
		else if (numPlatforms > 1 && numItmsForAllPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  #?(";
			for (i in 0...numPlatforms) {
				final platform = platforms[i];
				if (i == 0) {
					s += platform + " " + formatReferClojureKeyword(ns);
					// the first key sits two columns inside its opening paren: "  #?(<platform> ("
					s += referClojureKeySeparator(ns, spaces(platform.length + 8));
				} else {
					s += "\n     " + platform + " (:refer-clojure ";
				}
				s += formatReferClojureKeysOnOneLine(rc, platform);
				s += ")";
			}
			return s + ")";
		}
		// a mix of items for all platforms and some for specific platforms:
		// put each key on its own line and splice the platform-specific items into each key's collection
		else {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  " + formatReferClojureKeyword(ns);

			if (truthy(get(rc, "exclude")) && exclude.length > 0) {
				final symbols = pluck(filterOnPlatform(exclude, null), "symbol");
				s += "\n    " + formatReferClojureKeyWithSplices(":exclude", "[", "]", symbols.join(" "), referClojureSymbolPlatformGroups(exclude));
			}
			if (truthy(get(rc, "only")) && only.length > 0) {
				final symbols = pluck(filterOnPlatform(only, null), "symbol");
				s += "\n    " + formatReferClojureKeyWithSplices(":only", "[", "]", symbols.join(" "), referClojureSymbolPlatformGroups(only));
			}
			if (truthy(get(rc, "rename")) && rename.length > 0) {
				final renames = filterOnPlatform(rename, null);
				s += "\n    " + formatReferClojureKeyWithSplices(":rename", "{", "}", formatRenamesList(renames), referClojureRenamePlatformGroups(rename));
			}

			return s + ")";
		}
	}

	// -------------------------------------------------------------------------
	// ns

	public static function format(ns:Dynamic):String {
		var out = "(ns " + str(get(ns, "nsSymbol"));

		final requireMacros:Array<Dynamic> = arr(get(ns, "requireMacros"));
		final requires:Array<Dynamic> = arr(get(ns, "requires"));
		final imports:Array<Dynamic> = arr(get(ns, "imports"));
		final numRequireMacros = requireMacros.length;
		final numRequires = requires.length;
		final numImports = imports.length;

		var commentOutsideNsForm2:Null<String> = null;
		final hasGenClass = truthy(get(ns, "genClass"));
		final importsIsLastMainForm = numImports > 0 && !hasGenClass;
		final requireIsLastMainForm = numRequires > 0 && !importsIsLastMainForm && !hasGenClass;
		final requireMacrosIsLastMainForm = numRequireMacros > 0 && numRequires == 0 && numImports == 0 && !hasGenClass;
		final referClojureIsLastMainForm = truthy(get(ns, "referClojure")) && numRequireMacros == 0 && numRequires == 0 && numImports == 0 && !hasGenClass;
		var trailingParensArePrinted = false;

		final docstring:Dynamic = get(ns, "docstring");
		if (isStr(docstring))
			out += "\n  \"" + docstring + "\"";

		final nsMetadata:Array<Dynamic> = arr(get(ns, "nsMetadata"));
		if (nsMetadata.length > 0) {
			out += "\n  {";
			for (i in 0...nsMetadata.length) {
				final item = nsMetadata[i];
				out += str(get(item, "key")) + " " + str(get(item, "value"));
				if (i + 1 != nsMetadata.length)
					out += "\n   ";
			}
			out += "}";
		}

		// FIXME - we need reader conditionals for :refer-clojure here
		if (truthy(get(ns, "referClojure"))) {
			out += formatReferClojure(ns);

			final c:Dynamic = get(ns, "referClojureCommentAfterForm");
			if (isStringWithChars(c)) {
				if (referClojureIsLastMainForm)
					commentOutsideNsForm2 = c;
				else
					out += " " + c;
			}
		}

		if (numRequireMacros > 0) {
			final wrap = filterOnPlatform(requireMacros, ":cljs").length == numRequireMacros;
			var rmLastLineCommentAfter:Null<String> = null;
			final rmCommentAfter:Dynamic = get(ns, "requireMacrosCommentAfter");
			final rmCommentsAbove = get(ns, "requireMacrosCommentsAbove");

			var rmIndentation = "   ";
			if (wrap) {
				out += "\n  #?(:cljs\n";
				out = printCommentsAbove(out, rmCommentsAbove, "     ");
				out += "     (:require-macros";
				if (isStringWithChars(rmCommentAfter))
					out += " " + rmCommentAfter;
				out += "\n";
				rmIndentation = "      ";
			} else {
				out += "\n";
				out = printCommentsAbove(out, rmCommentsAbove, "  ");
				out += "  (:require-macros";
				if (isStringWithChars(rmCommentAfter))
					out += " " + rmCommentAfter;
				out += "\n";
			}

			for (i in 0...numRequireMacros) {
				final rm = requireMacros[i];
				final isLast = i + 1 == numRequireMacros;
				out += formatRequireLine(rm, rmIndentation, false);

				final c:Dynamic = get(rm, "commentAfter");
				if (isStringWithChars(c)) {
					if (isLast)
						rmLastLineCommentAfter = c;
					else
						out += " " + c;
				}
				if (!isLast)
					out += "\n";
			}

			if (!requireMacrosIsLastMainForm && !wrap) {
				out += ")";
			} else if (!requireMacrosIsLastMainForm && wrap) {
				out += "))";
			} else if (requireMacrosIsLastMainForm && !wrap) {
				out += "))";
				trailingParensArePrinted = true;
			} else {
				out += ")))";
				trailingParensArePrinted = true;
			}

			if (isStringWithChars(rmLastLineCommentAfter))
				out += " " + rmLastLineCommentAfter;
		}

		if (numRequires > 0) {
			var closeRequireParenTrail = ")";
			var lastRequireHasComment = false;
			var lastRequireComment:Dynamic = null;
			final reqPlatforms = getPlatformsFromArray(requires);
			final numPlatforms = reqPlatforms.length;
			final requireCommentsAbove:Dynamic = get(ns, "requireCommentsAbove");
			final requireCommentAfter:Dynamic = get(ns, "requireCommentAfter");

			var allRequiresUnderOnePlatform = false;
			if (numPlatforms == 1) {
				if (numRequires == filterOnPlatform(requires, reqPlatforms[0]).length)
					allRequiresUnderOnePlatform = true;
			}

			var requireLineIndentation = "   ";
			if (allRequiresUnderOnePlatform) {
				out += "\n  #?(" + reqPlatforms[0];
				if (size(requireCommentsAbove) > 0)
					out += "\n     " + join(arr(requireCommentsAbove), "\n     ");
				out += "\n     (:require";
				if (isStringWithChars(requireCommentAfter))
					out += " " + requireCommentAfter;
				out += "\n";
				requireLineIndentation = "      ";
			} else {
				if (size(requireCommentsAbove) > 0)
					out += "\n  " + join(arr(requireCommentsAbove), "\n  ");
				out += "\n  (:require";
				if (isStringWithChars(requireCommentAfter))
					out += " " + requireCommentAfter;
				out += "\n";
			}

			for (requiresIdx in 0...numRequires) {
				final req = requires[requiresIdx];
				// NOTE: I am not sure this works correctly with reader conditionals
				final isLastRequire1 = requiresIdx + 1 == numRequires;
				final commentAfter:Dynamic = get(req, "commentAfter");
				final hasComment = truthy(commentAfter);

				if (!truthy(get(req, "platform")) || allRequiresUnderOnePlatform) {
					out += formatRequireLine(req, requireLineIndentation, false);

					if (hasComment && !isLastRequire1) {
						out += " " + commentAfter + "\n";
					} else if (isLastRequire1 && hasComment && requireIsLastMainForm && !allRequiresUnderOnePlatform) {
						closeRequireParenTrail = ")) " + str(commentAfter);
						trailingParensArePrinted = true;
					} else if (isLastRequire1 && hasComment) {
						// NOTE: closeRequireParenTrail is decided below from these two flags
						lastRequireComment = commentAfter;
						lastRequireHasComment = true;
					} else if (isLastRequire1 && !hasComment) {
						closeRequireParenTrail = ")";
					} else {
						out += "\n";
					}
				}
			}

			final requireBlockHasReaderConditionals = numPlatforms > 0;
			final useStandardReaderConditional = onlyOneRequirePerPlatform(requires);

			if (!allRequiresUnderOnePlatform) {
				// use standard reader conditional #?(
				if (useStandardReaderConditional) {
					for (platformIdx in 0...numPlatforms) {
						final platform = reqPlatforms[platformIdx];
						final isLastPlatform = platformIdx + 1 == numPlatforms;

						// only look at requires for this platform
						final req = filterOnPlatform(requires, platform)[0];
						final commentAfter:Dynamic = get(req, "commentAfter");

						if (platformIdx == 0) {
							out = StringTools.trim(out);
							out += "\n   #?(" + platform;
						} else {
							out += "\n      " + platform;
						}

						// a comment above the libspec: print the platform keyword alone, then the
						// comment(s) and the libspec on their own lines inside the reader conditional
						if (size(get(req, "commentsAbove")) > 0)
							out += "\n" + formatRequireLine(req, "      ", true);
						else
							out += " " + formatRequireLine(req, "", true);

						// a comment after the last platform's libspec must be printed after the
						// closing parens (see closeRequireParenTrail below), otherwise it would
						// comment them out
						if (truthy(commentAfter) && isLastPlatform) {
							lastRequireHasComment = true;
							lastRequireComment = commentAfter;
						} else if (truthy(commentAfter)) {
							out += " " + str(commentAfter);
						}
					}
				}
				// use splicing reader conditional #?@(
				else {
					for (platformIdx in 0...numPlatforms) {
						final platform = reqPlatforms[platformIdx];
						final isLastPlatform = platformIdx + 1 == numPlatforms;

						if (platformIdx == 0) {
							out = StringTools.trim(out);
							out += "\n   #?@(" + platform + "\n       [";
						} else {
							out += "\n\n       " + platform + "\n       [";
						}

						// only look at requires for this platform
						final platformRequires = filterOnPlatform(requires, platform);
						final numFilteredReqs = platformRequires.length;
						var printedFirstReqLine = false;
						var printPlatformClosingBracket = true;
						for (reqIdx2 in 0...numFilteredReqs) {
							final req = platformRequires[reqIdx2];
							final isLastForPlatform = reqIdx2 + 1 == numFilteredReqs;
							final commentAfter:Dynamic = get(req, "commentAfter");
							final hasComment = truthy(commentAfter);

							if (printedFirstReqLine) {
								out += formatRequireLine(req, "        ", false);
							} else {
								printedFirstReqLine = true;
								out += formatRequireLine(req, "", false);
							}

							if (hasComment && !isLastForPlatform) {
								out += " " + commentAfter + "\n";
							} else if (hasComment && isLastForPlatform && !isLastPlatform) {
								out += "] " + str(commentAfter);
								printPlatformClosingBracket = false;
							} else if (hasComment && isLastForPlatform && (isLastPlatform || requireIsLastMainForm)) {
								lastRequireHasComment = true;
								lastRequireComment = commentAfter;
							} else if (isLastForPlatform && hasComment) {
								closeRequireParenTrail = ") " + str(commentAfter);
							} else if (isLastForPlatform && !hasComment) {
								closeRequireParenTrail = "]";
							} else {
								out += "\n";
							}
						}

						if (printPlatformClosingBracket)
							out += "]";
					}
				}
			}

			// closeRequireParenTrail can be one of six options:
			// - )             <-- no reader conditional, no comment on the last item, not the last main form
			// - ) <comment>   <-- no reader conditional, comment on the last itm, not the last main form
			// - ))            <-- reader conditional, no comment on the last itm, not the last main form
			// - )) <comment>  <-- reader conditional, comment on last itm, not the last main form
			// - )))           <-- reader conditional, no comment on last itm, :require is last main form
			// - ))) <comment> <-- reader conditional, comment on last itm, :require is last main form
			if (!requireBlockHasReaderConditionals && !lastRequireHasComment && !requireIsLastMainForm) {
				closeRequireParenTrail = ")";
			} else if (!requireBlockHasReaderConditionals && lastRequireHasComment && !requireIsLastMainForm) {
				closeRequireParenTrail = ") " + str(lastRequireComment);
			} else if (requireBlockHasReaderConditionals && !lastRequireHasComment && !requireIsLastMainForm) {
				closeRequireParenTrail = "))";
			} else if (requireBlockHasReaderConditionals && lastRequireHasComment && !requireIsLastMainForm) {
				closeRequireParenTrail = ")) " + str(lastRequireComment);
			} else if (requireBlockHasReaderConditionals && !lastRequireHasComment && requireIsLastMainForm) {
				closeRequireParenTrail = ")))";
				trailingParensArePrinted = true;
			} else if (requireBlockHasReaderConditionals && lastRequireHasComment && requireIsLastMainForm) {
				closeRequireParenTrail = ")))" + " " + str(lastRequireComment);
				trailingParensArePrinted = true;
			}

			out = StringTools.trim(out);
			out += closeRequireParenTrail;
		} // end :require printing

		if (numImports > 0) {
			final nonPlatformSpecificImports = filterOnPlatform(imports, null);
			final numNonPlatformSpecificImports = nonPlatformSpecificImports.length;
			final importPlatforms = getPlatformsFromArray(imports);
			final numImportPlatforms = importPlatforms.length;
			final importSectionHasReaderConditionals = numImportPlatforms > 0;
			final placeReaderConditionalOutsideOfImport = numImportPlatforms == 1 && numNonPlatformSpecificImports == 0;

			// a comment after the last line of the :import section must be printed
			// after the closing parens, otherwise it would comment them out
			var lastImportLineCommentAfter:Dynamic = null;
			var isImportKeywordPrinted = false;

			for (importsIdx in 0...numNonPlatformSpecificImports) {
				if (!isImportKeywordPrinted) {
					out += "\n" + formatImportKeyword(ns, "  ") + "\n";
					isImportKeywordPrinted = true;
				}

				final imp = nonPlatformSpecificImports[importsIdx];
				final isLastImport = importsIdx + 1 == numNonPlatformSpecificImports;
				final classes = arr(get(imp, "classes"));

				out = printCommentsAbove(out, get(imp, "commentsAbove"), "   ");
				if (get(imp, "package") == "") {
					// a class in the default package is printed as a bare symbol
					out += "   " + join(classes, " ");
				} else {
					out += "   (" + str(get(imp, "package"));
					for (className in classes)
						out += " " + str(className);
					out += ")";
				}

				final c:Dynamic = get(imp, "commentAfter");
				if (isStringWithChars(c)) {
					if (isLastImport && !importSectionHasReaderConditionals)
						lastImportLineCommentAfter = c;
					else
						out += " " + c;
				}

				if (!isLastImport)
					out += "\n";
			}

			var isFirstPlatform = true;

			for (platformIdx in 0...numImportPlatforms) {
				final platformStr = importPlatforms[platformIdx];
				final isLastPlatform = platformIdx + 1 == numImportPlatforms;
				final importsForThisPlatform = filterOnPlatform(imports, platformStr);
				final numImports2 = importsForThisPlatform.length;

				if (placeReaderConditionalOutsideOfImport) {
					out += "\n  #?(" + platformStr + "\n" + formatImportKeyword(ns, "     ");
					isImportKeywordPrinted = true;
				} else {
					if (isFirstPlatform) {
						if (!isImportKeywordPrinted) {
							out += "\n" + formatImportKeyword(ns, "  ");
							isImportKeywordPrinted = true;
						}
						out += "\n   #?@(" + platformStr;
						isFirstPlatform = false;
					} else {
						out += "\n\n       " + platformStr;
					}
					out += "\n";

					// comments above the first import of this platform are printed above the opening bracket
					if (numImports2 > 0)
						out = printCommentsAbove(out, get(importsForThisPlatform[0], "commentsAbove"), "       ");
					out += "       [";
				}

				for (idx2 in 0...numImports2) {
					final imp = importsForThisPlatform[idx2];
					final isLastImport2 = idx2 + 1 == numImports2;
					final classes = arr(get(imp, "classes"));

					if (placeReaderConditionalOutsideOfImport) {
						out += "\n";
						out = printCommentsAbove(out, get(imp, "commentsAbove"), "      ");
						out += "      ";
					} else if (idx2 > 0) {
						out += "\n";
						out = printCommentsAbove(out, get(imp, "commentsAbove"), "        ");
						out += "        ";
					}

					if (get(imp, "package") == "") {
						// a class in the default package is printed as a bare symbol
						out += join(classes, " ");
					} else {
						out += "(" + str(get(imp, "package")) + " " + join(classes, " ") + ")";
					}

					if (isLastImport2 && !placeReaderConditionalOutsideOfImport)
						out += "]";

					final c:Dynamic = get(imp, "commentAfter");
					if (isStringWithChars(c)) {
						if (isLastImport2 && isLastPlatform)
							lastImportLineCommentAfter = c;
						else
							out += " " + c;
					}
				}
			}

			// closeImportParenTrail can be one of four options:
			// - )    <-- no reader conditional, :gen-class follows
			// - ))   <-- reader conditional, :gen-class follows (closes the #?@( or #?( form and the :import form)
			// - ))   <-- no reader conditional, :import is the last main form
			// - )))  <-- reader conditional, :import is the last main form
			var closeImportParenTrail = ")";
			if (importsIsLastMainForm && importSectionHasReaderConditionals) {
				closeImportParenTrail = ")))";
				trailingParensArePrinted = true;
			} else if (importsIsLastMainForm) {
				closeImportParenTrail = "))";
				trailingParensArePrinted = true;
			} else if (importSectionHasReaderConditionals) {
				closeImportParenTrail = "))";
			}

			out += closeImportParenTrail;

			if (isStringWithChars(lastImportLineCommentAfter))
				out += " " + lastImportLineCommentAfter;
		} // end :import section

		if (hasGenClass) {
			final genClass = get(ns, "genClass");
			out += "\n";
			out = formatGenClass(out, genClass);
			trailingParensArePrinted = true;
		}

		if (!trailingParensArePrinted)
			out += ")";

		if (isStringWithChars(commentOutsideNsForm2))
			out += " " + commentOutsideNsForm2;

		return out;
	}

	// -------------------------------------------------------------------------
	// :gen-class

	/** Appends the :gen-class form, including the parens that close the ns form. **/
	static function formatGenClass(out:String, genClass:Dynamic):String {
		var genClassIndentationLevel = 2;
		final behindReaderConditional = get(genClass, "platform") == ":clj";

		if (behindReaderConditional) {
			out += "  #?(:clj\n";
			genClassIndentationLevel = 5;
		}

		final indentation = spaces(genClassIndentationLevel);
		out = printCommentsAbove(out, get(genClass, "commentsAbove"), indentation);
		out += indentation + "(:gen-class";

		var commentAfterGenClass:Dynamic = null;
		final commentAfter:Dynamic = get(genClass, "commentAfter");

		if (truthy(get(genClass, "isEmpty"))) {
			if (isStringWithChars(commentAfter))
				commentAfterGenClass = commentAfter;
		} else {
			if (isStringWithChars(commentAfter))
				out += " " + commentAfter;

			final valueIndentationLevel = genClassIndentationLevel + 1;
			final valueIndentation = spaces(valueIndentationLevel);

			// print the :gen-class keys in the order in which they appear in the clojure.core.genclass documentation
			// https://github.com/clojure/clojure/blob/clojure-1.11.1/src/clj/clojure/genclass.clj#L507
			for (key in genClassKeys) {
				final genClassValue:Dynamic = get(genClass, key);
				if (!truthy(genClassValue))
					continue;

				// print the comment from the previous line if necessary
				if (isStringWithChars(commentAfterGenClass)) {
					out += " " + commentAfterGenClass;
					commentAfterGenClass = null;
				}

				out += "\n";
				out = printCommentsAbove(out, get(genClassValue, "commentsAbove"), valueIndentation);
				out += valueIndentation + ":" + key;

				final value:Dynamic = get(genClassValue, "value");
				final nestedIndentation = spaces(valueIndentationLevel + key.length + 3);

				switch key {
					case "implements":
						final interfaces = arr(value);
						if (interfaces.length > 0)
							out += " [" + pluck(interfaces, "symbol").join(" ") + "]";
					case "constructors":
						final constructors = arr(value);
						if (constructors.length == 0) {
							out += " {}";
						} else {
							for (i in 0...constructors.length) {
								final c = constructors[i];
								out += i == 0 ? " {" : "\n" + nestedIndentation;
								if (truthy(get(c, "metadata")))
									out += str(get(c, "metadata")) + " ";
								out += "[" + join(arr(get(c, "parameterTypes")), " ");
								out += "] [" + join(arr(get(c, "superParameterTypes")), " ") + "]";
							}
							out += "}";
						}
					case "methods":
						final methods = arr(value);
						if (methods.length == 0) {
							out += " []";
						} else {
							for (i in 0...methods.length) {
								final m = methods[i];
								out += i == 0 ? " [" : "\n" + nestedIndentation;
								if (truthy(get(m, "metadata")))
									out += str(get(m, "metadata")) + " ";
								out += "[" + str(get(m, "name"));
								out += " [" + join(arr(get(m, "parameterTypes")), " ");
								out += "] " + str(get(m, "returnType")) + "]";
							}
							out += "]";
						}
					case "exposes":
						final exposes = arr(value);
						if (exposes.length == 0) {
							out += " {}";
						} else {
							for (i in 0...exposes.length) {
								final e = exposes[i];
								out += i == 0 ? " {" : "\n" + nestedIndentation;
								out += str(get(e, "fieldName")) + " {";
								if (truthy(get(e, "getter")))
									out += ":get " + str(get(e, "getter"));
								if (truthy(get(e, "setter"))) {
									if (truthy(get(e, "getter")))
										out += " ";
									out += ":set " + str(get(e, "setter"));
								}
								out += "}";
							}
							out += "}";
						}
					case "exposes-methods":
						final items = arr(value);
						if (items.length == 0) {
							out += " {}";
						} else {
							for (i in 0...items.length) {
								final m = items[i];
								out += i == 0 ? " {" : "\n" + nestedIndentation;
								out += str(get(m, "superMethodName")) + " " + str(get(m, "exposedName"));
							}
							out += "}";
						}
					default:
						// every remaining key holds a single scalar value, so an unset value here means
						// the parser did not recognize the form that followed the key. Never print it:
						// the output would contain the text "undefined" or "null" that was not in the input
						// https://github.com/oakmac/standard-clojure-style-js/issues/225
						if (!isStr(value) && value != true && value != false)
							throw ':gen-class :$key is missing a value.';

						if (truthy(get(genClassValue, "metadata")))
							out += " " + str(get(genClassValue, "metadata"));
						out += " " + str(value);
				}

				final c:Dynamic = get(genClassValue, "commentAfter");
				if (isStringWithChars(c))
					commentAfterGenClass = c;
			}

			// then the forms we do not know, as they were written
			for (other in arr(get(genClass, "other"))) {
				if (isStringWithChars(commentAfterGenClass)) {
					out += " " + commentAfterGenClass;
					commentAfterGenClass = null;
				}
				out += "\n";
				out = printCommentsAbove(out, get(other, "commentsAbove"), valueIndentation);
				out += valueIndentation + str(get(other, "text"));
				final c:Dynamic = get(other, "commentAfter");
				if (isStringWithChars(c))
					commentAfterGenClass = c;
			}
		}

		final hasComment = isStringWithChars(commentAfterGenClass);
		final closer = behindReaderConditional ? ")))" : "))";
		return out + closer + (hasComment ? " " + str(commentAfterGenClass) : "");
	}
}
