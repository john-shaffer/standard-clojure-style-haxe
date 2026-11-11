package standardclj;

import standardclj.NsData;

/** Comparators and a sort that matches JavaScript's Array.prototype.sort, for the ns data. **/
class NsSort {
	public static function cmpStr(a:String, b:String):Int {
		return a > b ? 1 : a < b ? -1 : 0;
	}

	// NOTE: a missing platform compares equal to any platform, as upstream
	public static function compareSymbolsThenPlatform(a:{symbol:String, platform:Null<String>}, b:{symbol:String, platform:Null<String>}):Int {
		final c = cmpStr(a.symbol, b.symbol);
		if (c != 0)
			return c;
		if (a.platform == null || b.platform == null)
			return 0;
		return cmpStr(a.platform, b.platform);
	}

	public static function compareFromSymbol(a:Rename, b:Rename):Int {
		return cmpStr(a.fromSymbol, b.fromSymbol);
	}

	public static function compareImports(a:Import, b:Import):Int {
		return cmpStr(a.packageName, b.packageName);
	}

	/**
		Sorts in place like V8's Array.prototype.sort for short arrays (a run
		detection followed by binary insertion), so that results are the same
		even for comparators that are not transitive.
	**/
	public static function sortArray<T>(a:Array<T>, cmp:T->T->Int):Void {
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
}
