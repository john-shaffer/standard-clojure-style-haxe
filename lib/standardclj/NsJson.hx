package standardclj;

import standardclj.NsData;

/**
	Converts ns data to the JSON-shaped structure of upstream's `parseNs`
	result: anonymous objects and arrays, where absent fields are absent.
**/
class NsJson {
	static function put(o:Dynamic, key:String, value:Dynamic):Void {
		if (value != null)
			Reflect.setField(o, key, value);
	}

	static function strings(a:Null<Array<String>>):Null<Array<String>> {
		return a == null ? null : a.copy();
	}

	static function each<T>(a:Null<Array<T>>, f:T->Dynamic):Null<Array<Dynamic>> {
		return a == null ? null : a.map(f);
	}

	static function symbol(s:Symbol):Dynamic {
		final o:Dynamic = {symbol: s.symbol};
		put(o, "platform", s.platform);
		return o;
	}

	static function rename(r:Rename):Dynamic {
		final o:Dynamic = {fromSymbol: r.fromSymbol, toSymbol: r.toSymbol};
		put(o, "platform", r.platform);
		return o;
	}

	static function require(r:Require):Dynamic {
		final o:Dynamic = {symbol: r.symbol};
		put(o, "as", r.alias);
		put(o, "asAlias", r.asAlias);
		put(o, "commentAfter", r.commentAfter);
		put(o, "commentsAbove", strings(r.commentsAbove));
		put(o, "default", r.defaultName);
		put(o, "exclude", each(r.exclude, symbol));
		put(o, "includeMacros", r.includeMacros);
		put(o, "metadata", strings(r.metadata));
		put(o, "platform", r.platform);
		put(o, "refer", r.referAll ? "all" : each(r.refer, symbol));
		put(o, "referMacros", strings(r.referMacros));
		put(o, "rename", each(r.rename, rename));
		if (r.symbolIsString)
			o.symbolIsString = true;
		return o;
	}

	static function imported(i:Import):Dynamic {
		final o:Dynamic = {classes: i.classes.copy()};
		Reflect.setField(o, "package", i.packageName);
		put(o, "commentAfter", i.commentAfter);
		put(o, "commentsAbove", strings(i.commentsAbove));
		put(o, "platform", i.platform);
		return o;
	}

	static function key<T>(k:Null<GenClassKey<T>>, value:T->Dynamic):Dynamic {
		if (k == null)
			return null;
		final o:Dynamic = {};
		put(o, "commentAfter", k.commentAfter);
		put(o, "commentsAbove", strings(k.commentsAbove));
		put(o, "metadata", k.metadata);
		if (k.value != null)
			o.value = value(k.value);
		return o;
	}

	static function scalar<T>(v:T):Dynamic {
		return v;
	}

	static function constructor(c:Constructor):Dynamic {
		final o:Dynamic = {parameterTypes: c.parameterTypes.copy(), superParameterTypes: c.superParameterTypes.copy()};
		put(o, "metadata", c.metadata);
		return o;
	}

	static function method(m:Method):Dynamic {
		final o:Dynamic = {name: m.name, parameterTypes: m.parameterTypes.copy(), returnType: m.returnType};
		put(o, "metadata", m.metadata);
		return o;
	}

	static function expose(e:Expose):Dynamic {
		final o:Dynamic = {fieldName: e.fieldName};
		put(o, "getter", e.getter);
		put(o, "setter", e.setter);
		return o;
	}

	static function genClass(g:NsGenClass):Dynamic {
		final o:Dynamic = {isEmpty: g.isEmpty};
		put(o, "commentAfter", g.commentAfter);
		put(o, "commentsAbove", strings(g.commentsAbove));
		put(o, "constructors", key(g.constructors, v -> v.map(constructor)));
		put(o, "exposes", key(g.exposes, v -> v.map(expose)));
		put(o, "exposes-methods", key(g.exposesMethods, v -> v.map(m -> ({superMethodName: m.superMethodName, exposedName: m.exposedName} : Dynamic))));
		put(o, "extends", key(g.extendsClass, scalar));
		put(o, "factory", key(g.factory, scalar));
		put(o, "impl-ns", key(g.implNs, scalar));
		put(o, "implements", key(g.implementsInterfaces, v -> v.map(symbol)));
		put(o, "init", key(g.init, scalar));
		put(o, "load-impl-ns", key(g.loadImplNs, scalar));
		put(o, "main", key(g.main, scalar));
		put(o, "methods", key(g.methods, v -> v.map(method)));
		put(o, "name", key(g.name, scalar));
		put(o, "other", each(g.other, x -> {
			final item:Dynamic = {text: x.text};
			put(item, "commentAfter", x.commentAfter);
			put(item, "commentsAbove", strings(x.commentsAbove));
			return item;
		}));
		put(o, "platform", g.platform);
		put(o, "post-init", key(g.postInit, scalar));
		put(o, "prefix", key(g.prefix, scalar));
		put(o, "state", key(g.state, scalar));
		return o;
	}

	public static function toJson(ns:Ns):Dynamic {
		final o:Dynamic = {nsSymbol: ns.nsSymbol};
		put(o, "commentOutsideNsForm", ns.commentOutsideNsForm);
		put(o, "docstring", ns.docstring);
		put(o, "genClass", ns.genClass == null ? null : genClass(ns.genClass));
		put(o, "importCommentAfter", ns.importCommentAfter);
		put(o, "importCommentsAbove", strings(ns.importCommentsAbove));
		put(o, "imports", each(ns.imports, imported));
		put(o, "nsMetadata", each(ns.nsMetadata, m -> ({key: m.key, value: m.value} : Dynamic)));
		if (ns.referClojure != null) {
			final r:Dynamic = {};
			put(r, "exclude", each(ns.referClojure.exclude, symbol));
			put(r, "only", each(ns.referClojure.only, symbol));
			put(r, "rename", each(ns.referClojure.rename, rename));
			o.referClojure = r;
		}
		put(o, "referClojureCommentAfter", ns.referClojureCommentAfter);
		put(o, "referClojureCommentAfterForm", ns.referClojureCommentAfterForm);
		put(o, "referClojureCommentsAbove", strings(ns.referClojureCommentsAbove));
		put(o, "requireCommentAfter", ns.requireCommentAfter);
		put(o, "requireCommentsAbove", strings(ns.requireCommentsAbove));
		put(o, "requireMacros", each(ns.requireMacros, require));
		put(o, "requireMacrosCommentAfter", ns.requireMacrosCommentAfter);
		put(o, "requireMacrosCommentsAbove", strings(ns.requireMacrosCommentsAbove));
		put(o, "requires", each(ns.requires, require));
		return o;
	}
}
