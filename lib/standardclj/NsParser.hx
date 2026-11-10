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
}
