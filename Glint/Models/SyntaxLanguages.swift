import Foundation

/// The languages Glint colours, and which files are which.
extension SyntaxLanguage {
  /// The language of the file at `path`, by its name or extension.
  static func forPath(_ path: String) -> SyntaxLanguage? {
    let name = (path as NSString).lastPathComponent
    if let language = byName[name] { return language }
    if name.hasPrefix("Dockerfile") || name.hasSuffix(".dockerfile") { return dockerfile }
    if name.hasPrefix(".env") { return ini }
    let ext = (name as NSString).pathExtension.lowercased()
    return byExtension[ext]
  }

  private static let byName: [String: SyntaxLanguage] = [
    "Makefile": make, "makefile": make, "GNUmakefile": make, "Gemfile": ruby, "Rakefile": ruby,
    "Podfile": ruby, "Fastfile": ruby, "Brewfile": ruby, "Vagrantfile": ruby, ".bashrc": shell, ".zshrc": shell,
    ".profile": shell, ".bash_profile": shell, ".zprofile": shell, ".gitconfig": ini, ".editorconfig": ini,
    ".gitignore": ignore, ".dockerignore": ignore, ".npmrc": ini, "Cargo.lock": toml, "go.mod": goMod,
    "CMakeLists.txt": cmake, "Package.resolved": json, ".prettierrc": json, ".eslintrc": json,
  ]

  private static let byExtension: [String: SyntaxLanguage] = {
    var map: [String: SyntaxLanguage] = [:]
    func add(_ language: SyntaxLanguage, _ extensions: String) {
      for ext in extensions.split(separator: " ") { map[String(ext)] = language }
    }
    add(swift, "swift swiftinterface")
    add(c, "c h")
    add(cpp, "cc cpp cxx c++ hpp hh hxx h++ ino ipp tpp cu")
    add(objc, "m mm")
    add(typescript, "ts mts cts tsx")
    add(javascript, "js mjs cjs jsx")
    add(python, "py pyi pyw gyp")
    add(go, "go")
    add(rust, "rs")
    add(java, "java groovy gradle")
    add(kotlin, "kt kts")
    add(csharp, "cs csx")
    add(ruby, "rb rake gemspec ru erb podspec")
    add(php, "php phtml")
    add(dart, "dart")
    add(lua, "lua")
    add(zig, "zig zon")
    add(elixir, "ex exs heex")
    add(scala, "scala sc sbt")
    add(sql, "sql psql")
    add(shell, "sh bash zsh fish ksh command")
    add(json, "json jsonc json5 geojson webmanifest code-workspace")
    add(yaml, "yaml yml")
    add(toml, "toml")
    add(ini, "ini cfg conf properties env editorconfig")
    add(markup, "html htm xhtml xml plist svg vue svelte astro xib storyboard csproj xaml entitlements xcscheme")
    add(css, "css scss sass less")
    add(markdown, "md markdown mdx mdown")
    add(proto, "proto")
    add(graphql, "graphql gql")
    add(hcl, "tf tfvars hcl nomad")
    add(make, "mk make")
    add(cmake, "cmake")
    add(haskell, "hs lhs")
    add(r, "r")
    add(perl, "pl pm")
    add(nix, "nix")
    add(clojure, "clj cljs cljc edn")
    return map
  }()

  // MARK: C family

  static let cKeywords =
    "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while _Bool _Atomic _Generic _Noreturn _Static_assert"
  static let cTypes =
    "char double float int long short signed unsigned void bool size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t ptrdiff_t"
  static let cppKeywords =
    cKeywords
    + " alignas alignof and asm catch class consteval constexpr constinit const_cast co_await co_return co_yield concept decltype delete dynamic_cast explicit export final friend mutable namespace new noexcept not operator or override private protected public reinterpret_cast requires static_assert static_cast template thread_local throw try typeid typename using virtual"

  static let c = SyntaxLanguage(
    "C", lineComments: ["//"], blockComment: ("/*", "*/"), keywords: cKeywords, types: cTypes,
    constants: "NULL", hashPreprocessor: true)
  static let cpp = SyntaxLanguage(
    "C++", lineComments: ["//"], blockComment: ("/*", "*/"), keywords: cppKeywords, types: cTypes + " wchar_t char8_t char16_t char32_t",
    constants: "NULL nullptr", specials: "this", hashPreprocessor: true)
  static let objc = SyntaxLanguage(
    "Objective-C", lineComments: ["//"], blockComment: ("/*", "*/"),
    keywords: cppKeywords + " in out inout bycopy byref oneway nonatomic atomic strong weak copy assign retain readonly readwrite nullable nonnull instancetype",
    types: cTypes + " id BOOL SEL IMP Class NSInteger NSUInteger CGFloat", booleans: "true false YES NO",
    constants: "NULL nil Nil nullptr", specials: "self super", atPrefix: .keyword, hashPreprocessor: true)

  static let swift = SyntaxLanguage(
    "Swift", lineComments: ["//"], blockComment: ("/*", "*/"), quotes: "\"", multilineQuotes: ["\"\"\""],
    keywords:
      "actor any as associatedtype async await borrowing break case catch class consume consuming continue convenience default defer deinit didSet do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect infix init inout internal is isolated lazy let macro mutating nonisolated nonmutating open operator optional override package postfix precedencegroup prefix private protocol public repeat required rethrows return sending set some static struct subscript super switch throw throws try typealias unowned var weak where while willSet",
    types: "Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float Bool String Character Void Never Any AnyObject",
    constants: "nil", specials: "self Self", atPrefix: .attribute, hashPreprocessor: true)

  // MARK: Web

  static let jsKeywords =
    "as async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch throw try typeof var void while with yield"
  static let javascript = SyntaxLanguage(
    "JavaScript", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["`"], keywords: jsKeywords,
    constants: "null undefined NaN Infinity", specials: "this", atPrefix: .attribute, colonKeys: true)
  static let typescript = SyntaxLanguage(
    "TypeScript", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["`"],
    keywords: jsKeywords
      + " abstract accessor asserts declare enum implements infer interface is keyof module namespace override private protected public readonly satisfies type unique",
    types: "string number boolean any unknown never object symbol bigint",
    constants: "null undefined NaN Infinity", specials: "this", atPrefix: .attribute, colonKeys: true)
  static let json = SyntaxLanguage(
    "JSON", lineComments: ["//"], blockComment: ("/*", "*/"), quotes: "\"", constants: "null", namingConventions: false,
    stringKeys: true)
  static let markup = SyntaxLanguage("HTML", family: .markup, blockComment: ("<!--", "-->"))
  static let css = SyntaxLanguage(
    "CSS", lineComments: ["//"], blockComment: ("/*", "*/"), keywords: "important from to and not only", booleans: "",
    namingConventions: false, atPrefix: .keyword, dollarVariables: true, dashInNames: true, cssProperties: true)
  static let graphql = SyntaxLanguage(
    "GraphQL", lineComments: ["#"], multilineQuotes: ["\"\"\""],
    keywords: "query mutation subscription fragment on type interface union enum input scalar schema extend directive implements repeatable",
    constants: "null", atPrefix: .attribute, dollarVariables: true)
  static let php = SyntaxLanguage(
    "PHP", lineComments: ["//", "#"], blockComment: ("/*", "*/"),
    keywords:
      "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield",
    types: "int float string bool void mixed never object iterable", constants: "null NULL",
    specials: "this self parent", caseInsensitive: false, dollarVariables: true)

  // MARK: Scripting

  static let python = SyntaxLanguage(
    "Python", lineComments: ["#"], multilineQuotes: ["\"\"\"", "'''"],
    keywords:
      "and as assert async await break case class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return try type while with yield",
    types: "int float str bool bytes list dict set tuple object", booleans: "True False", constants: "None",
    specials: "self cls", atPrefix: .attribute)
  static let ruby = SyntaxLanguage(
    "Ruby", lineComments: ["#"],
    keywords:
      "BEGIN END alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo require require_relative rescue retry return then undef unless until when while yield attr_accessor attr_reader attr_writer private protected public include extend raise",
    constants: "nil", specials: "self super", atPrefix: .variable)
  static let lua = SyntaxLanguage(
    "Lua", lineComments: ["--"], blockComment: ("--[[", "]]"),
    keywords: "and break do else elseif end for function goto if in local not or repeat return then until while",
    constants: "nil", specials: "self")
  static let perl = SyntaxLanguage(
    "Perl", lineComments: ["#"],
    keywords: "my our local sub if elsif else unless while until for foreach last next redo return use package require no and or not eq ne lt gt le ge",
    booleans: "", dollarVariables: true)
  static let elixir = SyntaxLanguage(
    "Elixir", lineComments: ["#"], multilineQuotes: ["\"\"\""],
    keywords:
      "after alias and case catch cond def defimpl defmacro defmodule defp defprotocol defstruct do else end fn for if import in not or quote raise receive require rescue try unless unquote use when with",
    constants: "nil", atPrefix: .attribute)
  static let shell = SyntaxLanguage(
    "Shell", lineComments: ["#"],
    keywords:
      "if then else elif fi case esac for select while until do done in function time return exit export local readonly declare typeset unset shift source alias set break continue eval exec trap cd echo printf test",
    booleans: "true false", namingConventions: false, dollarVariables: true)
  static let make = SyntaxLanguage(
    "Makefile", lineComments: ["#"], keywords: "include ifeq ifneq ifdef ifndef else endif define endef export override",
    booleans: "", namingConventions: false, dollarVariables: true)
  static let cmake = SyntaxLanguage(
    "CMake", lineComments: ["#"],
    keywords: "if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro set project add_executable add_library target_link_libraries include find_package",
    booleans: "ON OFF TRUE FALSE", caseInsensitive: true, namingConventions: false, dollarVariables: true)
  static let dockerfile = SyntaxLanguage(
    "Dockerfile", lineComments: ["#"],
    keywords: "from run cmd label expose env add copy entrypoint volume user workdir arg onbuild stopsignal healthcheck shell as maintainer",
    booleans: "", caseInsensitive: true, namingConventions: false, dollarVariables: true)

  // MARK: Systems and JVM

  static let go = SyntaxLanguage(
    "Go", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["`"],
    keywords:
      "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var",
    types:
      "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable",
    constants: "nil iota")
  static let goMod = SyntaxLanguage(
    "Go Module", lineComments: ["//"], keywords: "module go require replace exclude retract toolchain", booleans: "",
    namingConventions: false)
  static let rust = SyntaxLanguage(
    "Rust", lineComments: ["//"], blockComment: ("/*", "*/"), quotes: "\"",
    keywords:
      "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type union unsafe use where while yield macro_rules",
    types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
    specials: "self Self", hashAttributes: true)
  static let zig = SyntaxLanguage(
    "Zig", lineComments: ["//"],
    keywords:
      "addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while",
    types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f16 f32 f64 f128 bool void type anyerror noreturn",
    constants: "null undefined", atPrefix: .function)
  static let java = SyntaxLanguage(
    "Java", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["\"\"\""],
    keywords:
      "abstract assert break case catch class const continue default def do else enum extends final finally for goto if implements import instanceof interface native new non-sealed package permits private protected public record return sealed static strictfp super switch synchronized throw throws transient try var volatile while yield",
    types: "boolean byte char double float int long short void", constants: "null", specials: "this",
    atPrefix: .attribute)
  static let kotlin = SyntaxLanguage(
    "Kotlin", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["\"\"\""],
    keywords:
      "abstract actual annotation as break by catch class companion const constructor continue crossinline data do else enum expect external final finally for fun get if import in infix init inline inner interface internal is lateinit noinline object open operator out override package private protected public reified return sealed set super suspend tailrec throw try typealias val value var vararg when where while",
    constants: "null", specials: "this it", atPrefix: .attribute)
  static let scala = SyntaxLanguage(
    "Scala", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["\"\"\""],
    keywords:
      "abstract case catch class def do else enum export extends final finally for given if implicit import lazy match new object override package private protected return sealed then throw trait try type using val var while with yield",
    constants: "null", specials: "this super", atPrefix: .attribute)
  static let csharp = SyntaxLanguage(
    "C#", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["\"\"\""],
    keywords:
      "abstract as async await base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach get goto if implicit in init interface internal is lock namespace new operator out override params private protected public readonly record ref return sealed set sizeof stackalloc static struct switch throw try typeof unchecked unsafe using var virtual volatile when where while with yield",
    types: "bool byte char decimal double dynamic float int long nint nuint object sbyte short string uint ulong ushort void",
    constants: "null", specials: "this", hashPreprocessor: true)
  static let dart = SyntaxLanguage(
    "Dart", lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: ["\"\"\"", "'''"],
    keywords:
      "abstract as assert async await base break case catch class const continue covariant default deferred do else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync throw try typedef var when while with yield",
    types: "int double num bool void dynamic Object String List Map Set Future Stream", constants: "null",
    specials: "this", atPrefix: .attribute)
  static let haskell = SyntaxLanguage(
    "Haskell", lineComments: ["--"], blockComment: ("{-", "-}"), quotes: "\"",
    keywords: "case class data default deriving do else forall if import in infix infixl infixr instance let module newtype of qualified then type where",
    booleans: "True False")
  static let r = SyntaxLanguage(
    "R", lineComments: ["#"], keywords: "if else repeat while function for in next break return library",
    booleans: "TRUE FALSE T F", constants: "NULL NA NaN Inf")
  static let clojure = SyntaxLanguage(
    "Clojure", lineComments: [";"], quotes: "\"",
    keywords: "def defn defn- defmacro defprotocol defrecord deftype fn let loop recur if when cond do ns require import try catch finally throw",
    constants: "nil", namingConventions: false, dashInNames: true)
  static let nix = SyntaxLanguage(
    "Nix", lineComments: ["#"], blockComment: ("/*", "*/"), quotes: "\"", multilineQuotes: ["''"],
    keywords: "let in with rec inherit if then else assert import", constants: "null", namingConventions: false,
    equalsKeys: true, dashInNames: true)

  // MARK: Data and config

  static let yaml = SyntaxLanguage(
    "YAML", lineComments: ["#"], booleans: "true false yes no on off", constants: "null ~", namingConventions: false,
    colonKeys: true, stringKeys: true, dashInNames: true)
  static let toml = SyntaxLanguage(
    "TOML", lineComments: ["#"], multilineQuotes: ["\"\"\"", "'''"], namingConventions: false, equalsKeys: true,
    dashInNames: true)
  static let ini = SyntaxLanguage(
    "INI", lineComments: ["#", ";"], booleans: "true false", namingConventions: false, dollarVariables: true,
    equalsKeys: true, dashInNames: true)
  static let ignore = SyntaxLanguage("Ignore", lineComments: ["#"], quotes: "", booleans: "", namingConventions: false)
  static let hcl = SyntaxLanguage(
    "HCL", lineComments: ["#", "//"], blockComment: ("/*", "*/"), quotes: "\"",
    keywords: "resource data variable output module provider locals terraform for in if else endif endfor dynamic",
    constants: "null", namingConventions: false, dollarVariables: true, equalsKeys: true, dashInNames: true)
  static let proto = SyntaxLanguage(
    "Protocol Buffers", lineComments: ["//"], blockComment: ("/*", "*/"),
    keywords: "syntax edition package import option message enum service rpc returns repeated optional required map oneof reserved stream extend public weak",
    types: "double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes")
  static let sql = SyntaxLanguage(
    "SQL", lineComments: ["--"], blockComment: ("/*", "*/"),
    keywords:
      "select from where insert into values update set delete create table alter drop index view join inner left right outer full cross on and or not is in exists as order by group having limit offset union all distinct case when then else end primary key foreign references default unique check constraint begin commit rollback transaction returning with like ilike between asc desc if replace trigger function procedure return returns language cascade add column rename to grant revoke schema database extension sequence type enum using",
    types: "int integer bigint smallint text varchar char boolean bool date time timestamp timestamptz interval serial bigserial uuid json jsonb numeric decimal real float double precision bytea",
    constants: "null", caseInsensitive: true, namingConventions: false)
  static let markdown = SyntaxLanguage("Markdown", family: .markdown)
}
