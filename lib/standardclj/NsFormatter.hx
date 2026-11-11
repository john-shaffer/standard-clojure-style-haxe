package standardclj;

import standardclj.NsData;

private typedef HasPlatform = {
	var platform:Null<String>;
};

/** Prints the parsed ns data produced by `NsParser.parse`. **/
class NsFormatter {
	// -------------------------------------------------------------------------
	// Helpers

	/** A string that is not null or empty. **/
	static inline function has(s:Null<String>):Bool {
		return s != null && s != "";
	}

	static function spaces(n:Int):String {
		return StringTools.lpad("", " ", n);
	}

	static function printCommentsAbove(out:String, commentsAbove:Null<Array<String>>, indentation:String):String {
		if (commentsAbove != null)
			for (c in commentsAbove)
				out += indentation + c + "\n";
		return out;
	}

	static function symbolNames(symbols:Null<Array<Symbol>>):Array<String> {
		return symbols == null ? [] : [for (s in symbols) s.symbol];
	}

	static inline function size<T>(a:Null<Array<T>>):Int {
		return a == null ? 0 : a.length;
	}

	// -------------------------------------------------------------------------
	// Platforms

	/** A sorted array of the platform strings found on items in `items`, with :default last. **/
	static function getPlatformsFromArray<T:HasPlatform>(items:Array<T>):Array<String> {
		var hasDefault = false;
		final platforms:Array<String> = [];
		for (itm in items) {
			final p = itm.platform;
			if (has(p)) {
				if (p == ":default")
					hasDefault = true;
				else if (platforms.indexOf(p) < 0)
					platforms.push(p);
			}
		}
		platforms.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		if (hasDefault)
			platforms.push(":default");
		return platforms;
	}

	/** True if there is at most one require per platform. **/
	static function onlyOneRequirePerPlatform(reqs:Array<Require>):Bool {
		final seen:Array<String> = [];
		for (r in reqs) {
			final p = r.platform;
			if (has(p)) {
				if (seen.indexOf(p) >= 0)
					return false;
				seen.push(p);
			}
		}
		return true;
	}

	/** Filters on the platform key. A null platform selects items without a platform. **/
	static function filterOnPlatform<T:HasPlatform>(items:Array<T>, platform:Null<String>):Array<T> {
		return items.filter(itm -> platform == null ? !has(itm.platform) : itm.platform == platform);
	}

	// -------------------------------------------------------------------------
	// Require and import lines

	static function formatImportKeyword(ns:Ns, indentation:String):String {
		var out = printCommentsAbove("", ns.importCommentsAbove, indentation);
		out += indentation + "(:import";
		if (has(ns.importCommentAfter))
			out += " " + ns.importCommentAfter;
		return out;
	}

	static function formatRequireLine(req:Require, initialIndentation:String, metadataInline:Bool, commentsPrinted = false):String {
		var out = "";
		var requireIndentation = initialIndentation;

		if (!commentsPrinted)
			out = printCommentsAbove(out, req.commentsAbove, initialIndentation);

		final metadata = req.metadata;
		if (size(metadata) > 0) {
			out += initialIndentation + metadata.join(" ");
			if (metadataInline) {
				out += " ";
				requireIndentation = "";
			} else {
				out += "\n";
			}
		}

		out += requireIndentation + "[" + req.symbol;

		if (has(req.alias))
			out += " :as " + req.alias;
		else if (has(req.asAlias))
			out += " :as-alias " + req.asAlias;

		if (has(req.defaultName))
			out += " :default " + req.defaultName;

		// NOTE: this will not work if the individual :refer symbols are wrapped in a reader conditional
		if (size(req.refer) > 0)
			out += " :refer [" + symbolNames(req.refer).join(" ") + "]";
		else if (req.referAll)
			out += " :refer :all";

		// NOTE: this will not work if the individual :exclude symbols are wrapped in a reader conditional
		if (size(req.exclude) > 0)
			out += " :exclude [" + symbolNames(req.exclude).join(" ") + "]";

		if (req.includeMacros == true)
			out += " :include-macros true";
		else if (req.includeMacros == false)
			out += " :include-macros false";

		if (size(req.referMacros) > 0)
			out += " :refer-macros [" + req.referMacros.join(" ") + "]";

		if (size(req.rename) > 0)
			out += " :rename {" + formatRenamesList(req.rename) + "}";

		return out + "]";
	}

	// -------------------------------------------------------------------------
	// :refer-clojure

	/** The available :refer-clojure keys, in the order :exclude, :only, :rename. **/
	static function getReferClojureKeys(referClojure:Null<ReferClojure>):Array<String> {
		final keys = [];
		if (referClojure != null) {
			if (referClojure.exclude != null)
				keys.push(":exclude");
			if (referClojure.only != null)
				keys.push(":only");
			if (referClojure.rename != null)
				keys.push(":rename");
		}
		return keys;
	}

	static function formatKeywordFollowedByListOfSymbols(kwd:String, symbols:Array<String>):String {
		return kwd + " [" + symbols.join(" ") + "]";
	}

	static function formatRenamesList(itms:Array<Rename>):String {
		return [for (i in itms) i.fromSymbol + " " + i.toSymbol].join(", ");
	}

	/** "(:refer-clojure" followed by the comment from the keyword line, if there is one. **/
	static function formatReferClojureKeyword(ns:Ns):String {
		final c = ns.referClojureCommentAfter;
		return has(c) ? "(:refer-clojure " + c : "(:refer-clojure";
	}

	/** A newline plus indentation when the keyword has a comment, otherwise a space. **/
	static function referClojureKeySeparator(ns:Ns, keyIndentation:String):String {
		return has(ns.referClojureCommentAfter) ? "\n" + keyIndentation : " ";
	}

	static function formatReferClojureSingleKeyword(ns:Ns, excludeOrOnly:String):String {
		final rc = ns.referClojure;
		final symbolsArr:Array<Symbol> = (excludeOrOnly == "exclude" ? rc.exclude : rc.only) ?? [];
		final kwd = ":" + excludeOrOnly;
		final commentsAbove = ns.referClojureCommentsAbove;

		final platforms = getPlatformsFromArray(symbolsArr);
		final numPlatforms = platforms.length;
		final symbolsForAllPlatforms = symbolNames(filterOnPlatform(symbolsArr, null));
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
			s += formatKeywordFollowedByListOfSymbols(kwd, symbolNames(symbolsArr));
			return s + "))";
		}
			// all symbols are for specific platforms across multiple platforms:
		// wrap a separate (:refer-clojure) per platform inside #?(...)
		else if (numPlatforms > 1 && numSymbolsForAllPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  #?(";
			for (i in 0...numPlatforms) {
				final platform = platforms[i];
				final symbolsForPlatform = symbolNames(filterOnPlatform(symbolsArr, platform));
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
				final symbolsForPlatform = symbolNames(filterOnPlatform(symbolsArr, platform));
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

	static function formatReferClojure(ns:Ns):String {
		final referClojure = ns.referClojure;
		final keys = getReferClojureKeys(referClojure);
		final commentsAbove = ns.referClojureCommentsAbove;

		if (keys.length == 0)
			return "";
		else if (keys.length == 1 && keys[0] == ":exclude")
			return formatReferClojureSingleKeyword(ns, "exclude");
		else if (keys.length == 1 && keys[0] == ":only")
			return formatReferClojureSingleKeyword(ns, "only");
		else if (keys.length == 1 && keys[0] == ":rename") {
			final renames = referClojure.rename ?? [];
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
	static function allReferClojureItems(referClojure:ReferClojure):Array<HasPlatform> {
		final itms:Array<HasPlatform> = [];
		for (items in [referClojure.exclude, referClojure.only])
			for (item in items ?? [])
				itms.push(item);
		for (item in referClojure.rename ?? [])
			itms.push(item);
		return itms;
	}

	/**
		The :refer-clojure keys and their items for one platform on a single line,
		ie: ":exclude [a b] :rename {x y}". A null platform means items that are not
		platform-specific.
	**/
	static function formatReferClojureKeysOnOneLine(referClojure:ReferClojure, platform:Null<String>):String {
		final parts = [];

		if (referClojure.exclude != null) {
			final symbols = symbolNames(filterOnPlatform(referClojure.exclude, platform));
			if (symbols.length > 0)
				parts.push(formatKeywordFollowedByListOfSymbols(":exclude", symbols));
		}

		if (referClojure.only != null) {
			final symbols = symbolNames(filterOnPlatform(referClojure.only, platform));
			if (symbols.length > 0)
				parts.push(formatKeywordFollowedByListOfSymbols(":only", symbols));
		}

		if (referClojure.rename != null) {
			final renames = filterOnPlatform(referClojure.rename, platform);
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

	static function referClojureSymbolPlatformGroups(symbolsArr:Array<Symbol>):Array<{platform:String, txt:String}> {
		return [
			for (p in getPlatformsFromArray(symbolsArr))
				{platform: p, txt: symbolNames(filterOnPlatform(symbolsArr, p)).join(" ")}
		];
	}

	static function referClojureRenamePlatformGroups(renamesArr:Array<Rename>):Array<{platform:String, txt:String}> {
		return [
			for (p in getPlatformsFromArray(renamesArr))
				{platform: p, txt: formatRenamesList(filterOnPlatform(renamesArr, p))}
		];
	}

	/** A :refer-clojure form that has more than one of :exclude, :only, :rename. **/
	static function formatReferClojureMultipleKeywords(ns:Ns):String {
		final rc = ns.referClojure;
		final exclude = rc.exclude ?? [];
		final only = rc.only ?? [];
		final rename = rc.rename ?? [];
		final commentsAbove = ns.referClojureCommentsAbove;

		final allItms = allReferClojureItems(rc);
		final platforms = getPlatformsFromArray(allItms);
		final numPlatforms = platforms.length;
		final numItmsForAllPlatforms = filterOnPlatform(allItms, null).length;

		// there are no reader conditionals: put each key on its own line
		if (numPlatforms == 0) {
			var s = printCommentsAbove("\n", commentsAbove, "  ");
			s += "  " + formatReferClojureKeyword(ns);

			if (rc.exclude != null && exclude.length > 0)
				s += "\n    " + formatKeywordFollowedByListOfSymbols(":exclude", symbolNames(exclude));
			if (rc.only != null && only.length > 0)
				s += "\n    " + formatKeywordFollowedByListOfSymbols(":only", symbolNames(only));
			if (rc.rename != null && rename.length > 0)
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

			if (rc.exclude != null && exclude.length > 0) {
				final symbols = symbolNames(filterOnPlatform(exclude, null));
				s += "\n    " + formatReferClojureKeyWithSplices(":exclude", "[", "]", symbols.join(" "), referClojureSymbolPlatformGroups(exclude));
			}
			if (rc.only != null && only.length > 0) {
				final symbols = symbolNames(filterOnPlatform(only, null));
				s += "\n    " + formatReferClojureKeyWithSplices(":only", "[", "]", symbols.join(" "), referClojureSymbolPlatformGroups(only));
			}
			if (rc.rename != null && rename.length > 0) {
				final renames = filterOnPlatform(rename, null);
				s += "\n    " + formatReferClojureKeyWithSplices(":rename", "{", "}", formatRenamesList(renames), referClojureRenamePlatformGroups(rename));
			}

			return s + ")";
		}
	}

	// -------------------------------------------------------------------------
	// ns

	/** Appends the :refer-clojure form. **/
	static function formatReferClojureSection(ns:Ns, o:NsOutput, isLastMainForm:Bool):Void {
		var out = o.text;
		// FIXME - we need reader conditionals for :refer-clojure here
		if (ns.referClojure != null) {
			out += formatReferClojure(ns);

			final c = ns.referClojureCommentAfterForm;
			if (has(c)) {
				if (isLastMainForm)
					o.commentOutside = c;
				else
					out += " " + c;
			}
		}
		o.text = out;
	}

	/** Appends the :require-macros form. **/
	static function formatRequireMacrosSection(ns:Ns, o:NsOutput, isLastMainForm:Bool):Void {
		var out = o.text;
		final requireMacros = ns.requireMacros ?? [];
		final numRequireMacros = requireMacros.length;
		final wrap = filterOnPlatform(requireMacros, ":cljs").length == numRequireMacros;
		var rmLastLineCommentAfter:Null<String> = null;
		final rmCommentAfter = ns.requireMacrosCommentAfter;
		final rmCommentsAbove = ns.requireMacrosCommentsAbove;

		var rmIndentation = "   ";
		if (wrap) {
			out += "\n  #?(:cljs\n";
			out = printCommentsAbove(out, rmCommentsAbove, "     ");
			out += "     (:require-macros";
			if (has(rmCommentAfter))
				out += " " + rmCommentAfter;
			out += "\n";
			rmIndentation = "      ";
		} else {
			out += "\n";
			out = printCommentsAbove(out, rmCommentsAbove, "  ");
			out += "  (:require-macros";
			if (has(rmCommentAfter))
				out += " " + rmCommentAfter;
			out += "\n";
		}

		for (i in 0...numRequireMacros) {
			final rm = requireMacros[i];
			final isLast = i + 1 == numRequireMacros;
			out += formatRequireLine(rm, rmIndentation, false);

			final c = rm.commentAfter;
			if (has(c)) {
				if (isLast)
					rmLastLineCommentAfter = c;
				else
					out += " " + c;
			}
			if (!isLast)
				out += "\n";
		}

		if (!isLastMainForm && !wrap) {
			out += ")";
		} else if (!isLastMainForm && wrap) {
			out += "))";
		} else if (isLastMainForm && !wrap) {
			out += "))";
			o.closesNs = true;
		} else {
			out += ")))";
			o.closesNs = true;
		}

		if (has(rmLastLineCommentAfter))
			out += " " + rmLastLineCommentAfter;
		o.text = out;
	}

	/** Appends the :require form. **/
	static function formatRequireSection(ns:Ns, o:NsOutput, isLastMainForm:Bool):Void {
		var out = o.text;
		final requires = ns.requires ?? [];
		final numRequires = requires.length;
		var closeRequireParenTrail = ")";
		var lastRequireHasComment = false;
		var lastRequireComment:Null<String> = null;
		final reqPlatforms = getPlatformsFromArray(requires);
		final numPlatforms = reqPlatforms.length;
		final requireCommentsAbove = ns.requireCommentsAbove;
		final requireCommentAfter = ns.requireCommentAfter;

		var allRequiresUnderOnePlatform = false;
		if (numPlatforms == 1) {
			if (numRequires == filterOnPlatform(requires, reqPlatforms[0]).length)
				allRequiresUnderOnePlatform = true;
		}

		var requireLineIndentation = "   ";
		if (allRequiresUnderOnePlatform) {
			out += "\n  #?(" + reqPlatforms[0];
			if (size(requireCommentsAbove) > 0)
				out += "\n     " + requireCommentsAbove.join("\n     ");
			out += "\n     (:require";
			if (has(requireCommentAfter))
				out += " " + requireCommentAfter;
			out += "\n";
			requireLineIndentation = "      ";
		} else {
			if (size(requireCommentsAbove) > 0)
				out += "\n  " + requireCommentsAbove.join("\n  ");
			out += "\n  (:require";
			if (has(requireCommentAfter))
				out += " " + requireCommentAfter;
			out += "\n";
		}

		for (requiresIdx in 0...numRequires) {
			final req = requires[requiresIdx];
			// NOTE: I am not sure this works correctly with reader conditionals
			final isLastRequire1 = requiresIdx + 1 == numRequires;
			final commentAfter = req.commentAfter;
			final hasComment = has(commentAfter);

			if (!has(req.platform) || allRequiresUnderOnePlatform) {
				out += formatRequireLine(req, requireLineIndentation, false);

				if (hasComment && !isLastRequire1) {
					out += " " + commentAfter + "\n";
				} else if (isLastRequire1 && hasComment && isLastMainForm && !allRequiresUnderOnePlatform) {
					closeRequireParenTrail = ")) " + commentAfter;
					o.closesNs = true;
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
					final commentAfter = req.commentAfter;

					if (platformIdx == 0) {
						out = StringTools.trim(out);
						out += "\n   #?(" + platform;
					} else {
						out += "\n      " + platform;
					}

					// a comment above the libspec: print the platform keyword alone, then the
					// comment(s) and the libspec on their own lines inside the reader conditional
					if (size(req.commentsAbove) > 0)
						out += "\n" + formatRequireLine(req, "      ", true);
					else
						out += " " + formatRequireLine(req, "", true);

					// a comment after the last platform's libspec must be printed after the
					// closing parens (see closeRequireParenTrail below), otherwise it would
					// comment them out
					if (has(commentAfter) && isLastPlatform) {
						lastRequireHasComment = true;
						lastRequireComment = commentAfter;
					} else if (has(commentAfter)) {
						out += " " + commentAfter;
					}
				}
			}
			// use splicing reader conditional #?@(
			else {
				for (platformIdx in 0...numPlatforms) {
					final platform = reqPlatforms[platformIdx];
					final isLastPlatform = platformIdx + 1 == numPlatforms;

					// only look at requires for this platform
					final platformRequires = filterOnPlatform(requires, platform);

					if (platformIdx == 0) {
						out = StringTools.trim(out);
						out += "\n   #?@(" + platform + "\n";
					} else {
						out += "\n\n       " + platform + "\n";
					}
					// comments above the first libspec of this platform are printed above the opening bracket
					out = printCommentsAbove(out, platformRequires[0].commentsAbove, "       ");
					out += "       [";
					final numFilteredReqs = platformRequires.length;
					var printedFirstReqLine = false;
					var printPlatformClosingBracket = true;
					for (reqIdx2 in 0...numFilteredReqs) {
						final req = platformRequires[reqIdx2];
						final isLastForPlatform = reqIdx2 + 1 == numFilteredReqs;
						final commentAfter = req.commentAfter;
						final hasComment = has(commentAfter);

						if (printedFirstReqLine) {
							out += formatRequireLine(req, "        ", false);
						} else {
							printedFirstReqLine = true;
							out += formatRequireLine(req, "", false, true);
						}

						if (hasComment && !isLastForPlatform) {
							out += " " + commentAfter + "\n";
						} else if (hasComment && isLastForPlatform && !isLastPlatform) {
							out += "] " + commentAfter;
							printPlatformClosingBracket = false;
						} else if (hasComment && isLastForPlatform && (isLastPlatform || isLastMainForm)) {
							lastRequireHasComment = true;
							lastRequireComment = commentAfter;
						} else if (isLastForPlatform && hasComment) {
							closeRequireParenTrail = ") " + commentAfter;
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
		if (!requireBlockHasReaderConditionals && !lastRequireHasComment && !isLastMainForm) {
			closeRequireParenTrail = ")";
		} else if (!requireBlockHasReaderConditionals && lastRequireHasComment && !isLastMainForm) {
			closeRequireParenTrail = ") " + lastRequireComment;
		} else if (requireBlockHasReaderConditionals && !lastRequireHasComment && !isLastMainForm) {
			closeRequireParenTrail = "))";
		} else if (requireBlockHasReaderConditionals && lastRequireHasComment && !isLastMainForm) {
			closeRequireParenTrail = ")) " + lastRequireComment;
		} else if (requireBlockHasReaderConditionals && !lastRequireHasComment && isLastMainForm) {
			closeRequireParenTrail = ")))";
			o.closesNs = true;
		} else if (requireBlockHasReaderConditionals && lastRequireHasComment && isLastMainForm) {
			closeRequireParenTrail = ")))" + " " + lastRequireComment;
			o.closesNs = true;
		}

		out = StringTools.trim(out);
		out += closeRequireParenTrail;
		o.text = out;
	}

	/** Appends the :import form. **/
	static function formatImportSection(ns:Ns, o:NsOutput, isLastMainForm:Bool):Void {
		var out = o.text;
		final imports = ns.imports ?? [];
		final numImports = imports.length;
		final nonPlatformSpecificImports = filterOnPlatform(imports, null);
		final numNonPlatformSpecificImports = nonPlatformSpecificImports.length;
		final importPlatforms = getPlatformsFromArray(imports);
		final numImportPlatforms = importPlatforms.length;
		final importSectionHasReaderConditionals = numImportPlatforms > 0;
		final placeReaderConditionalOutsideOfImport = numImportPlatforms == 1 && numNonPlatformSpecificImports == 0;

		// a comment after the last line of the :import section must be printed
		// after the closing parens, otherwise it would comment them out
		var lastImportLineCommentAfter:Null<String> = null;
		var isImportKeywordPrinted = false;

		for (importsIdx in 0...numNonPlatformSpecificImports) {
			if (!isImportKeywordPrinted) {
				out += "\n" + formatImportKeyword(ns, "  ") + "\n";
				isImportKeywordPrinted = true;
			}

			final imp = nonPlatformSpecificImports[importsIdx];
			final isLastImport = importsIdx + 1 == numNonPlatformSpecificImports;
			final classes = imp.classes;

			out = printCommentsAbove(out, imp.commentsAbove, "   ");
			if (imp.packageName == "") {
				// a class in the default package is printed as a bare symbol
				out += "   " + classes.join(" ");
			} else {
				out += "   (" + imp.packageName;
				for (className in classes)
					out += " " + className;
				out += ")";
			}

			final c = imp.commentAfter;
			if (has(c)) {
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
					out = printCommentsAbove(out, importsForThisPlatform[0].commentsAbove, "       ");
				out += "       [";
			}

			for (idx2 in 0...numImports2) {
				final imp = importsForThisPlatform[idx2];
				final isLastImport2 = idx2 + 1 == numImports2;
				final classes = imp.classes;

				if (placeReaderConditionalOutsideOfImport) {
					out += "\n";
					out = printCommentsAbove(out, imp.commentsAbove, "      ");
					out += "      ";
				} else if (idx2 > 0) {
					out += "\n";
					out = printCommentsAbove(out, imp.commentsAbove, "        ");
					out += "        ";
				}

				if (imp.packageName == "") {
					// a class in the default package is printed as a bare symbol
					out += classes.join(" ");
				} else {
					out += "(" + imp.packageName + " " + classes.join(" ") + ")";
				}

				if (isLastImport2 && !placeReaderConditionalOutsideOfImport)
					out += "]";

				final c = imp.commentAfter;
				if (has(c)) {
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
		if (isLastMainForm && importSectionHasReaderConditionals) {
			closeImportParenTrail = ")))";
			o.closesNs = true;
		} else if (isLastMainForm) {
			closeImportParenTrail = "))";
			o.closesNs = true;
		} else if (importSectionHasReaderConditionals) {
			closeImportParenTrail = "))";
		}

		out += closeImportParenTrail;

		if (has(lastImportLineCommentAfter))
			out += " " + lastImportLineCommentAfter;
		o.text = out;
	}

	public static function format(ns:Ns):String {
		final o = new NsOutput("(ns " + (ns.nsSymbol ?? "undefined"));

		final numRequireMacros = (ns.requireMacros ?? []).length;
		final numRequires = (ns.requires ?? []).length;
		final numImports = (ns.imports ?? []).length;

		final hasGenClass = ns.genClass != null;
		final importsIsLastMainForm = numImports > 0 && !hasGenClass;
		final requireIsLastMainForm = numRequires > 0 && !importsIsLastMainForm && !hasGenClass;
		final requireMacrosIsLastMainForm = numRequireMacros > 0 && numRequires == 0 && numImports == 0 && !hasGenClass;
		final referClojureIsLastMainForm = ns.referClojure != null && numRequireMacros == 0 && numRequires == 0 && numImports == 0 && !hasGenClass;

		if (ns.docstring != null)
			o.text += "\n  \"" + ns.docstring + "\"";

		final nsMetadata = ns.nsMetadata ?? [];
		if (nsMetadata.length > 0) {
			o.text += "\n  {";
			for (i in 0...nsMetadata.length) {
				final item = nsMetadata[i];
				o.text += item.key + " " + item.value;
				if (i + 1 != nsMetadata.length)
					o.text += "\n   ";
			}
			o.text += "}";
		}

		if (ns.referClojure != null)
			formatReferClojureSection(ns, o, referClojureIsLastMainForm);
		if (numRequireMacros > 0)
			formatRequireMacrosSection(ns, o, requireMacrosIsLastMainForm);
		if (numRequires > 0)
			formatRequireSection(ns, o, requireIsLastMainForm);
		if (numImports > 0)
			formatImportSection(ns, o, importsIsLastMainForm);

		if (hasGenClass) {
			o.text = formatGenClass(o.text + "\n", ns.genClass);
			o.closesNs = true;
		}

		if (!o.closesNs)
			o.text += ")";

		if (has(o.commentOutside))
			o.text += " " + o.commentOutside;

		return o.text;
	}

	// -------------------------------------------------------------------------
	// :gen-class

	/** Appends the :gen-class form, including the parens that close the ns form. **/
	static function formatGenClass(out:String, genClass:NsGenClass):String {
		var genClassIndentationLevel = 2;
		final behindReaderConditional = genClass.platform == ":clj";

		if (behindReaderConditional) {
			out += "  #?(:clj\n";
			genClassIndentationLevel = 5;
		}

		final indentation = spaces(genClassIndentationLevel);
		out = printCommentsAbove(out, genClass.commentsAbove, indentation);
		out += indentation + "(:gen-class";

		var commentAfterGenClass:Null<String> = null;
		final commentAfter = genClass.commentAfter;

		if (genClass.isEmpty) {
			if (has(commentAfter))
				commentAfterGenClass = commentAfter;
		} else {
			if (has(commentAfter))
				out += " " + commentAfter;

			final valueIndentationLevel = genClassIndentationLevel + 1;
			final valueIndentation = spaces(valueIndentationLevel);

			// prints a key, its comments, and the value as printed by `printValue`
			function printKey<T>(name:String, key:Null<GenClassKey<T>>, printValue:(GenClassKey<T>, String) -> String):Void {
				if (key == null)
					return;

				// print the comment from the previous line if necessary
				if (has(commentAfterGenClass)) {
					out += " " + commentAfterGenClass;
					commentAfterGenClass = null;
				}

				out += "\n";
				out = printCommentsAbove(out, key.commentsAbove, valueIndentation);
				out += valueIndentation + ":" + name;
				out += printValue(key, spaces(valueIndentationLevel + name.length + 3));

				if (has(key.commentAfter))
					commentAfterGenClass = key.commentAfter;
			}

			function scalar<T>(name:String):(GenClassKey<T>, String) -> String {
				return (key, _) -> {
					// every remaining key holds a single scalar value, so an unset value here means
					// the parser did not recognize the form that followed the key. Never print it:
					// the output would contain the text "undefined" or "null" that was not in the input
					// https://github.com/oakmac/standard-clojure-style-js/issues/225
					if (key.value == null)
						throw ':gen-class :$name is missing a value.';
					return (has(key.metadata) ? " " + key.metadata : "") + " " + Std.string(key.value);
				};
			}

			// print the :gen-class keys in the order in which they appear in the clojure.core.genclass documentation
			// https://github.com/clojure/clojure/blob/clojure-1.11.1/src/clj/clojure/genclass.clj#L507
			printKey("name", genClass.name, scalar("name"));
			printKey("extends", genClass.extendsClass, scalar("extends"));
			printKey("implements", genClass.implementsInterfaces, (key, _) -> {
				final interfaces = key.value ?? [];
				return interfaces.length > 0 ? " [" + symbolNames(interfaces).join(" ") + "]" : "";
			});
			printKey("init", genClass.init, scalar("init"));
			printKey("constructors", genClass.constructors, (key, nestedIndentation) -> {
				final constructors = key.value ?? [];
				if (constructors.length == 0)
					return " {}";
				var s = "";
				for (i in 0...constructors.length) {
					final c = constructors[i];
					s += i == 0 ? " {" : "\n" + nestedIndentation;
					if (has(c.metadata))
						s += c.metadata + " ";
					s += "[" + c.parameterTypes.join(" ");
					s += "] [" + c.superParameterTypes.join(" ") + "]";
				}
				return s + "}";
			});
			printKey("post-init", genClass.postInit, scalar("post-init"));
			printKey("methods", genClass.methods, (key, nestedIndentation) -> {
				final methods = key.value ?? [];
				if (methods.length == 0)
					return " []";
				var s = "";
				for (i in 0...methods.length) {
					final m = methods[i];
					s += i == 0 ? " [" : "\n" + nestedIndentation;
					if (has(m.metadata))
						s += m.metadata + " ";
					s += "[" + m.name;
					s += " [" + m.parameterTypes.join(" ");
					s += "] " + m.returnType + "]";
				}
				return s + "]";
			});
			printKey("main", genClass.main, scalar("main"));
			printKey("factory", genClass.factory, scalar("factory"));
			printKey("state", genClass.state, scalar("state"));
			printKey("exposes", genClass.exposes, (key, nestedIndentation) -> {
				final exposes = key.value ?? [];
				if (exposes.length == 0)
					return " {}";
				var s = "";
				for (i in 0...exposes.length) {
					final e = exposes[i];
					s += i == 0 ? " {" : "\n" + nestedIndentation;
					s += e.fieldName + " {";
					if (has(e.getter))
						s += ":get " + e.getter;
					if (has(e.setter)) {
						if (has(e.getter))
							s += " ";
						s += ":set " + e.setter;
					}
					s += "}";
				}
				return s + "}";
			});
			printKey("exposes-methods", genClass.exposesMethods, (key, nestedIndentation) -> {
				final items = key.value ?? [];
				if (items.length == 0)
					return " {}";
				var s = "";
				for (i in 0...items.length) {
					s += i == 0 ? " {" : "\n" + nestedIndentation;
					s += items[i].superMethodName + " " + items[i].exposedName;
				}
				return s + "}";
			});
			printKey("prefix", genClass.prefix, scalar("prefix"));
			printKey("impl-ns", genClass.implNs, scalar("impl-ns"));
			printKey("load-impl-ns", genClass.loadImplNs, scalar("load-impl-ns"));

			// then the forms we do not know, as they were written
			for (other in genClass.other ?? []) {
				if (has(commentAfterGenClass)) {
					out += " " + commentAfterGenClass;
					commentAfterGenClass = null;
				}
				out += "\n";
				out = printCommentsAbove(out, other.commentsAbove, valueIndentation);
				out += valueIndentation + other.text.split("\n").join("\n" + valueIndentation);
				if (has(other.commentAfter))
					commentAfterGenClass = other.commentAfter;
			}
		}

		final hasComment = has(commentAfterGenClass);
		final closer = behindReaderConditional ? ")))" : "))";
		return out + closer + (hasComment ? " " + commentAfterGenClass : "");
	}
}

/** The text of an ns form as it is built, and what the sections that print it found out. **/
private class NsOutput {
	/** A section printed the parens that close the ns form. **/
	public var closesNs = false;

	/** A comment after the last form, printed after the ns form closes. **/
	public var commentOutside:Null<String>;

	public var text:String;

	public function new(text:String) {
		this.text = text;
	}
}
