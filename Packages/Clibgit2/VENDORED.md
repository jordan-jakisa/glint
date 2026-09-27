# Vendored libgit2

- **Version:** libgit2 v1.9.7, from
  https://github.com/libgit2/libgit2/archive/refs/tags/v1.9.7.tar.gz
- **Tarball SHA-256:** `1a4fbe7589e814777ae76b64734ad80f4ecad22cd33a22682a2aaea4ae5375e7`
- **License:** GPLv2 with the linking exception (`libgit2/COPYING`). Linking it
  into Adit, including statically, is allowed.

Built from source as a local Swift package so Adit has no third-party wrapper
dependency. SwiftGit2 was the original plan, but it only builds with Carthage
and hides the `git_diff_options` Adit needs for speed. See docs/DECISIONS.md.

## What was copied

`include/`, `src/libgit2/`, `src/util/`, `deps/xdiff/`, `deps/llhttp/`,
`COPYING`, `README.md`. Everything else (tests, CLI, CMake, other platforms'
backends, bundled zlib and pcre) was left out.

Removed from `src/util/hash/`: every backend except CommonCrypto. Removed from
`src/util/`: `win32/`. All `CMakeLists.txt` files deleted.

## Local changes

- `src/util/git2_features.h`: hand-written replacement for the CMake-generated
  header. Threads on, CommonCrypto for SHA-1 and SHA-256, system zlib and
  iconv, `regcomp_l` for regex, built-in llhttp. No HTTPS, SSH, or NTLM:
  Adit never talks to a remote.
- `include/git2/experimental.h`: hand-written, no experimental features.
- `include/module.modulemap`: exposes `git2.h` to Swift as `Clibgit2`.

- `include/git2/diff.h` and `src/libgit2/diff_xdiff.c`: a `GIT_DIFF_HISTOGRAM`
  flag (bit 31) that turns on xdiff's histogram algorithm, which libgit2
  bundles but doesn't expose. Marked "Adit: local patch" in both files.
  Reapply on upgrade, or drop it if upstream adds the flag.

Apart from that patch, the C sources are unmodified. `Package.swift` compiles them with
`-fno-modules`, because with Clang modules on, libgit2's own `struct entry`
collides with the one in `<search.h>`.

## Upgrading

Download the new release, copy the same directories over, redo the deletions
above, and diff `git2_features.h.in` against the previous release to see
whether any new feature flags need a decision.
