# CHANGELOG

## 3.1.3 (2026-09-14)
- fix: brew commands no longer abort with `getcwd: cannot access parent directories` and `USER: unbound variable` — every privileged brew invocation now runs with a cwd the brew owner can read (their home, `/tmp` as fallback) and with `USER`/`LOGNAME` set, which a launchd-started Puppet agent does not provide. Affects every brew-invoking provider: the `brew`, `homebrew`, `brewcask` and `tap` package providers and the `homebrew_tap`, `homebrew_pin`, `homebrew_service` and `homebrew_bundle` types

## 3.1.2 (2026-07-20)
- feature: `homebrew_environment` (and `github_token`) now also write `$HOME/.homebrew/brew.env`, the file Homebrew (>= 4.1) natively reads on startup — the mechanism actually honored by `brew` invocations, unlike `/etc/environment` which macOS doesn't read automatically. New optional `user_home` parameter overrides the assumed `/Users/<user>` home directory for non-standard accounts
- internal: environment-variable-to-line formatting is now computed once and shared between `/etc/environment` and `brew.env` to avoid the two files drifting out of sync

## 3.1.1 (2026-07-08)
- fix: the `homebrew` package provider now falls back to a cask lookup when a formula is not found, so installed casks are reported accurately
- internal: `run_brew` accepts a `failonfail` parameter so expected non-zero exit codes are treated as normal outcomes, plus improved debug logging for package installation status
- fix: the `install-clt` exec now uses `/bin/test` instead of `/usr/bin/test` in its `unless` guard for Command Line Tools installation compatibility

## 3.1.0 (2026-07-07)
- feature: optional idempotent `brew update` to refresh taps, via the new opt-in `homebrew::update` class and the `manage_update` / `update_frequency` parameters on the `homebrew` class (#4)
- internal: the update runs at most once per interval (guarded by a timestamp marker) so it produces no per-run `changed` churn, is bounded by a finite `timeout`, and swallows transient failures for retry on the next run

## 3.0.0 (2026-07-06)
- feature: native `homebrew_tap` type/provider for managing taps, including custom (non-GitHub/private) git remotes with in-place drift correction and tap priority (#3)
- feature: native `homebrew_pin` type/provider to pin/unpin installed formulae against `brew upgrade`
- feature: native `homebrew_service` type/provider to manage `brew services` daemons (running/stopped)
- feature: native `homebrew_bundle` type/provider to apply a `Brewfile` declaratively (idempotence via `brew bundle check`)
- feature: `is_arm64` fact and Apple Silicon support (`/opt/homebrew` prefix) across install and all providers
- internal: shared `PuppetX::Homebrew::BrewCommand` mixin — brew commands drop privileges to the brew owner and set `HOMEBREW_NO_AUTO_UPDATE=1` on reads; brew/brewcask/homebrew/tap package providers refactored on top of it
- compatibility: now requires Puppet >= 8, Ruby >= 3.2, and puppetlabs/stdlib >= 9 (breaking)

## 1.9.1 (2021-09-23)
- internal: fixup overly-narrow stdlib version pin
- feature: upgrade casks

## 1.9.0 (2021-04-21)
- fix: update cask syntax for brew changes (#144) ([6a273ca4](6a273ca4))
- fix: fixup "ensure" for specific version pins (#114) ([defc03f3](defc03f3))
- internal: build via pdk (#122) ([07607a68](07607a68))
- internal: fixup linters and test matrix for newer ruby versions

## 1.8.3
- fix: avoid mangling names when resource target is a url (#110)

## 1.8.2
- compatibility: first release to officially support Puppet 5 (previous versions worked unofficially)

## 1.8.1
- fix: fix installation of first-ever Brew package on machine (#98)

## 1.8.0
- feature: support multi-user environments with new `$multiuser` flag (#89)
- fix: support for High Sierra
- compatibility: drop support for Puppet 3

## 1.7.1
- fix: include ruby 1.8.3 in metadata.json
- compatibility: last release to include Puppet 3 support

## 1.7.0
- feature: allow usage within non-brew and bundler environments
- feature: support ruby 1.8.3 installations
- meta: more and better linting

## 1.6.0
- feature: permission management more closely aligns to brew install
- bugfix: ensure providers load regardless of configured puppet load order
- bugfix: ensure facts work on all puppet versions
- bugfix: ensure packages with 'homebrew-' prefix are not re-installed
- bugfix: do not allow homebrew root install

## 1.5.0
- feature: allow package to set HOMEBREW_GITHUB_API_TOKEN
- feature/bugfix: stop parsing homebrew output, parse response codes instead
- bugfix: manage /usr/local/Homebrew rather than parent directory
- meta: speed up tests

## 1.4.3
- bugfix: manage objects (packages, taps, etc) case-insensitively
- meta: deprecate root-owned homebrew
- meta: clean up tests

## 1.4.2
- bugfix: fixed bug where brew-cask provider didn't work the first time
- meta: updated to new homebrew install location

## 1.4.1
- feature: allow usage by any member of homebrew group

## 1.4.0
- feature: remove files with invalid checksums for easier retrying
- bugfix: ensure `install_options` propgates correctly
- bugfix: detect and fail properly on checksum errors
- meta: include README section on ordering taps/packages

## 1.3.3
- feature: allow user/group override
- bugfix: remove `err` from facter code

## 1.3.2
- bugfix: fix compat issues for facter booleans
- bugfix: use puppet warning over ruby warn

## 1.3.1
- bugfix: only download CLI tools if values are set
- meta: move away from params class

## 1.3.0
- feature: allow users to manage taps
- meta: better testing, OSX-specific tests on Travis
- meta: fix typos, add contributer list

## 1.2.0
- bugfix: set directory permissions to brew defaults
- bugfix: fix brewcask parsing
- meta: enable auto-testing

## 1.1.1
- bugfix: ensure brew is called with correct user

## 1.1.0
- feature: add install_options
- feature: add upgradeable
- tech debt: clean up inheritance pattern

## 1.0.1
- documentation fixes

## 1.0.0
- initial release
