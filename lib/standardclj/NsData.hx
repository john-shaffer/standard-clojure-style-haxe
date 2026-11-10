package standardclj;

// The data of an ns form, as produced by `NsParser.parse` and printed by
// `NsFormatter.format`. A value that is null is absent, and an absent array
// is not the same as an empty one: `:exclude []` gives an empty array.

/** A symbol, with the platform of the reader conditional it came from. **/
class Symbol {
	public var symbol:String;
	public var platform:Null<String>;

	public function new(symbol:String, platform:Null<String>) {
		this.symbol = symbol;
		this.platform = platform;
	}
}

/** `from to` in a `:rename` map. **/
class Rename {
	public final fromSymbol:String;
	public final toSymbol:String;
	public var platform:Null<String>;

	public function new(fromSymbol:String, toSymbol:String, platform:Null<String>) {
		this.fromSymbol = fromSymbol;
		this.toSymbol = toSymbol;
		this.platform = platform;
	}
}

class NsMetadata {
	public final key:String;
	public final value:String;

	public function new(key:String, value:String) {
		this.key = key;
		this.value = value;
	}
}

/** A libspec of `:require` or `:require-macros`. **/
class Require {
	public var symbol:String;
	public var platform:Null<String>;
	/** The `:as` symbol. **/
	public var alias:Null<String>;
	public var asAlias:Null<String>;
	public var commentAfter:Null<String>;
	public var commentsAbove:Null<Array<String>>;
	/** The `:default` symbol. **/
	public var defaultName:Null<String>;
	public var exclude:Null<Array<Symbol>>;
	public var includeMacros:Null<Bool>;
	public var metadata:Null<Array<String>>;
	/** The symbols of `:refer`, unless `referAll`. **/
	public var refer:Null<Array<Symbol>>;
	/** `:refer :all` **/
	public var referAll = false;
	public var referMacros:Null<Array<String>>;
	public var rename:Null<Array<Rename>>;
	/** The symbol is a string, as in `["react" :as react]`. **/
	public var symbolIsString = false;

	public function new(symbol:String) {
		this.symbol = symbol;
	}
}

class Import {
	/** The package; empty for classes in the default package. **/
	public final packageName:String;
	public final classes:Array<String>;
	public var commentAfter:Null<String>;
	public var commentsAbove:Null<Array<String>>;
	public var platform:Null<String>;

	public function new(packageName:String, classes:Array<String>) {
		this.packageName = packageName;
		this.classes = classes;
	}
}

class ReferClojure {
	public var exclude:Null<Array<Symbol>>;
	public var only:Null<Array<Symbol>>;
	public var rename:Null<Array<Rename>>;

	public function new() {}
}

/** The comments, metadata and value that belong to one key of `:gen-class`. **/
class GenClassKey<T> {
	public var commentAfter:Null<String>;
	public var commentsAbove:Null<Array<String>>;
	public var metadata:Null<String>;
	/** Null when the key is missing its value. **/
	public var value:Null<T>;

	public function new() {}
}

class Constructor {
	public final parameterTypes:Array<String>;
	public final superParameterTypes:Array<String>;
	public var metadata:Null<String>;

	public function new(parameterTypes:Array<String>, superParameterTypes:Array<String>) {
		this.parameterTypes = parameterTypes;
		this.superParameterTypes = superParameterTypes;
	}
}

class Method {
	public final name:String;
	public final parameterTypes:Array<String>;
	public final returnType:String;
	public var metadata:Null<String>;

	public function new(name:String, parameterTypes:Array<String>, returnType:String) {
		this.name = name;
		this.parameterTypes = parameterTypes;
		this.returnType = returnType;
	}
}

class Expose {
	public final fieldName:String;
	public var getter:Null<String>;
	public var setter:Null<String>;

	public function new(fieldName:String) {
		this.fieldName = fieldName;
	}
}

class ExposesMethod {
	public final superMethodName:String;
	public final exposedName:String;

	public function new(superMethodName:String, exposedName:String) {
		this.superMethodName = superMethodName;
		this.exposedName = exposedName;
	}
}

/** A form of `:gen-class` that we do not know, kept as it is written. **/
class GenClassOther {
	public final text:String;
	public var commentAfter:Null<String>;
	public var commentsAbove:Null<Array<String>>;

	public function new(text:String) {
		this.text = text;
	}
}

class NsGenClass {
	public var commentAfter:Null<String>;
	public var commentsAbove:Null<Array<String>>;
	public var constructors:Null<GenClassKey<Array<Constructor>>>;
	public var exposes:Null<GenClassKey<Array<Expose>>>;
	public var exposesMethods:Null<GenClassKey<Array<ExposesMethod>>>;
	public var extendsClass:Null<GenClassKey<String>>;
	public var factory:Null<GenClassKey<String>>;
	public var implNs:Null<GenClassKey<String>>;
	public var implementsInterfaces:Null<GenClassKey<Array<Symbol>>>;
	public var init:Null<GenClassKey<String>>;
	/** `:gen-class` has no keys. **/
	public var isEmpty = true;
	public var loadImplNs:Null<GenClassKey<Bool>>;
	public var main:Null<GenClassKey<Bool>>;
	public var methods:Null<GenClassKey<Array<Method>>>;
	public var name:Null<GenClassKey<String>>;
	/** Unknown forms, in source order. **/
	public var other:Null<Array<GenClassOther>>;
	public var platform:Null<String>;
	public var postInit:Null<GenClassKey<String>>;
	public var prefix:Null<GenClassKey<String>>;
	public var state:Null<GenClassKey<String>>;

	public function new() {}
}

class Ns {
	public var commentOutsideNsForm:Null<String>;
	public var docstring:Null<String>;
	public var genClass:Null<NsGenClass>;
	public var importCommentAfter:Null<String>;
	public var importCommentsAbove:Null<Array<String>>;
	public var imports:Null<Array<Import>>;
	public var nsMetadata:Null<Array<NsMetadata>>;
	public var nsSymbol:Null<String>;
	public var referClojure:Null<ReferClojure>;
	public var referClojureCommentAfter:Null<String>;
	public var referClojureCommentAfterForm:Null<String>;
	public var referClojureCommentsAbove:Null<Array<String>>;
	public var requireCommentAfter:Null<String>;
	public var requireCommentsAbove:Null<Array<String>>;
	public var requireMacros:Null<Array<Require>>;
	public var requireMacrosCommentAfter:Null<String>;
	public var requireMacrosCommentsAbove:Null<Array<String>>;
	public var requires:Null<Array<Require>>;

	public function new() {}
}
