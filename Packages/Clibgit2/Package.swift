// swift-tools-version: 6.0

import PackageDescription

// libgit2, vendored and built from source for macOS. See VENDORED.md for the
// version, what was copied, and which build options are enabled.
let package = Package(
  name: "Clibgit2",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "Clibgit2", targets: ["Clibgit2"]),
  ],
  targets: [
    .target(
      name: "Clibgit2",
      path: "libgit2",
      exclude: [
        "COPYING",
        "README.md",
        "deps/llhttp/LICENSE-MIT",
      ],
      sources: [
        "src/libgit2",
        "src/util",
        "deps/xdiff",
        "deps/llhttp",
      ],
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("src/libgit2"),
        .headerSearchPath("src/util"),
        .headerSearchPath("deps/xdiff"),
        .headerSearchPath("deps/llhttp"),
        .define("_FILE_OFFSET_BITS", to: "64"),
        .define("GIT_DEPRECATE_HARD"),
        .unsafeFlags(["-w", "-fno-modules"]),
      ],
      linkerSettings: [
        .linkedLibrary("z"),
        .linkedLibrary("iconv"),
        .linkedFramework("CoreFoundation"),
        .linkedFramework("Security"),
      ]
    ),
  ]
)
