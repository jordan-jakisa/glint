import Foundation

/// The order changed files are shown in. Files shown later in a review get
/// less attention (Fregnan et al., ESEC/FSE 2022), so the ones worth reading
/// come first: source, each followed by its tests; then configuration and
/// docs; then lockfiles, generated, and vendored files, which are long and
/// rarely read line by line. Path order is a setting away.
enum FileOrder: String, CaseIterable, Sendable {
  /// Source first (Glint's default), by path as Zed does, or by file name
  /// with ties broken by path, as Zed's Sort By Name.
  case smart, path, name

  private static let key = "fileOrder"

  static var current: FileOrder {
    UserDefaults.standard.string(forKey: key).flatMap(FileOrder.init(rawValue:)) ?? .smart
  }

  static func set(_ order: FileOrder) {
    UserDefaults.standard.set(order.rawValue, forKey: key)
  }

  enum Kind: Int, Comparable, Sendable {
    case source, test, configuration, bulk

    static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
  }

  /// Sorts `items` by their paths.
  func sorted<T>(_ items: [T], path: (T) -> String) -> [T] {
    switch self {
    case .path:
      return items.sorted { Self.pathLess(path($0), path($1)) }
    case .name:
      return items.sorted {
        let (a, b) = (path($0), path($1))
        let (x, y) = ((a as NSString).lastPathComponent, (b as NSString).lastPathComponent)
        return x != y ? x < y : Self.pathLess(a, b)
      }
    case .smart:
      let order = Self.smartOrder(items.map(path))
      let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      return items.sorted { rank[path($0), default: .max] < rank[path($1), default: .max] }
    }
  }

  /// Zed's path order: folder by folder, so `src/lib.rs` comes before
  /// `src-old.rs`, where a plain string sort would put `-` first.
  static func pathLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: "/", omittingEmptySubsequences: false)
    let y = b.split(separator: "/", omittingEmptySubsequences: false)
    for (p, q) in zip(x, y) where p != q { return p < q }
    return x.count < y.count
  }

  /// Zed's tree order: at each level, folders before files, so a tree's
  /// rows read top to bottom in the same order the diff shows them.
  static func treeLess(_ a: String, _ b: String) -> Bool {
    let x = a.split(separator: "/")
    let y = b.split(separator: "/")
    for index in 0..<min(x.count, y.count) {
      let xFolder = index < x.count - 1
      let yFolder = index < y.count - 1
      if xFolder != yFolder { return xFolder }
      if x[index] != y[index] { return x[index] < y[index] }
    }
    return x.count < y.count
  }

  /// Sources in path order, each followed by the tests named after it; then
  /// tests that match no changed source; then configuration and docs; then
  /// bulk files.
  static func smartOrder(_ paths: [String]) -> [String] {
    let sorted = paths.sorted(by: pathLess)
    let sources = sorted.filter { kind(of: $0) == .source }
    var tests = sorted.filter { kind(of: $0) == .test }
    var result: [String] = []
    for source in sources {
      result.append(source)
      let stem = self.stem(of: source)
      let matching = tests.filter { testSubject(of: $0) == stem }
      result += matching
      tests.removeAll { matching.contains($0) }
    }
    result += tests
    result += sorted.filter { kind(of: $0) == .configuration }
    result += sorted.filter { kind(of: $0) == .bulk }
    return result
  }

  static func kind(of path: String) -> Kind {
    let lower = path.lowercased()
    let name = (lower as NSString).lastPathComponent
    let folders = Set((lower as NSString).deletingLastPathComponent.split(separator: "/").map(String.init))

    if bulkNames.contains(name) || bulkSuffixes.contains(where: name.hasSuffix)
      || !folders.isDisjoint(with: bulkFolders)
    {
      return .bulk
    }
    if testSubject(of: path) != nil || !folders.isDisjoint(with: testFolders) { return .test }
    if name.hasPrefix(".") || configurationNames.contains(name)
      || configurationSuffixes.contains(where: name.hasSuffix) || folders.contains(".github")
      || folders.contains("docs")
    {
      return .configuration
    }
    return .source
  }

  /// The file a test is named after (`GitRepositoryTests.swift` →
  /// `gitrepository`), or nil when the name doesn't say it's a test.
  static func testSubject(of path: String) -> String? {
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    // A word boundary is required, so "latest" isn't a test: CamelCase
    // (FooTests, FooSpec) or a separator (foo_test, foo.test, foo-spec).
    for suffix in ["Tests", "Test", "Spec"] where name.hasSuffix(suffix) && name.count > suffix.count {
      return String(name.dropLast(suffix.count)).lowercased()
    }
    let lower = name.lowercased()
    for suffix in ["_tests", "_test", ".test", "-test", "_spec", ".spec", "-spec"] where lower.hasSuffix(suffix) {
      return String(lower.dropLast(suffix.count))
    }
    if lower.hasPrefix("test_") { return String(lower.dropFirst(5)) }
    return nil
  }

  static func stem(of path: String) -> String {
    ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
  }

  private static let bulkNames: Set<String> = [
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", "cargo.lock",
    "gemfile.lock", "poetry.lock", "uv.lock", "package.resolved", "go.sum", "composer.lock",
    "podfile.lock", "mix.lock", "flake.lock", "pubspec.lock",
  ]
  private static let bulkSuffixes = [
    ".min.js", ".min.css", ".map", ".pb.go", ".pb.swift", ".g.dart", ".snap", ".svg", ".pbxproj",
  ]
  private static let bulkFolders: Set<String> = [
    "vendor", "vendored", "third_party", "thirdparty", "external", "node_modules", "dist", "build",
    "generated", "__generated__", "libgit2",
  ]
  private static let testFolders: Set<String> = ["test", "tests", "__tests__", "spec", "specs"]
  private static let configurationNames: Set<String> = [
    "package.json", "tsconfig.json", "makefile", "dockerfile", "procfile", "license", "readme",
    "cargo.toml", "pyproject.toml", "package.swift", "gemfile", "podfile",
  ]
  private static let configurationSuffixes = [
    ".json", ".yaml", ".yml", ".toml", ".ini", ".plist", ".xcconfig", ".entitlements", ".md",
    ".txt", ".lock", ".cfg", ".conf", ".env",
  ]
}
