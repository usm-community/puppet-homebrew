# Tap a repository
homebrew_tap { 'myuser/tools':
  ensure => present,
}

# Tap a private repository from a custom git URL. A later change to `url` is
# corrected in place via `brew tap --custom-remote` (no destructive re-tap).
#
# A tap that ships casks needs `trust => true` as well: `brew tap` validates the
# clone by loading its casks, which is refused for an untrusted tap and reported
# as "Cannot tap ...: invalid syntax in tap!". With `url` set, trust is recorded
# against the URL, since Homebrew keys trust on the remote for custom-remote taps.
homebrew_tap { 'mycompany/internal':
  ensure => present,
  url    => 'https://git.example.com/mycompany/homebrew-internal.git',
  trust  => true,
}

# Always refresh this tap on `brew update`, and trust it so its formulae load
# when HOMEBREW_REQUIRE_TAP_TRUST is enabled.
homebrew_tap { 'mycompany/tools':
  ensure            => present,
  force_auto_update => true,
  trust             => true,
}

# Force-clone a tap that Homebrew would otherwise serve from the JSON API.
homebrew_tap { 'homebrew/cask':
  ensure => present,
  force  => true,
}

# Untap a repository
homebrew_tap { 'myuser/old-tap':
  ensure => absent,
}

# Purge: only allow declared taps, untap everything else
# resources { 'homebrew_tap': purge => true }

# Ordering: ensure taps happen before installing packages from them
Homebrew_tap <| |> -> Package <| provider == homebrew |>
