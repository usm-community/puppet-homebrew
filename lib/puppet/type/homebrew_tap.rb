Puppet::Type.newtype(:homebrew_tap) do
  @doc = <<-DOC
    Manages Homebrew taps (third-party repositories) on macOS.

    A tap is a git clone of a third-party formula/cask repository. This type
    wraps `brew tap` / `brew untap` and additionally supports a custom git URL,
    forced auto-update, and the `brew trust` workflow.

    @example Tap a repository
      homebrew_tap { 'myuser/tools':
        ensure => present,
      }

    @example Tap a private repository from a custom git URL
      homebrew_tap { 'mycompany/internal':
        ensure => present,
        url    => 'https://git.example.com/mycompany/homebrew-internal.git',
      }

    @example Always refresh a tap on `brew update` and trust it
      homebrew_tap { 'mycompany/tools':
        ensure            => present,
        force_auto_update => true,
        trust             => true,
      }
  DOC

  # Official taps that have been merged into another tap or built into Homebrew
  # and therefore no longer need to be tapped manually. Declaring one still
  # works (Homebrew treats it as a no-op or a git clone), but we warn so users
  # can clean up stale manifests. See docs.brew.sh/Taps.
  DEPRECATED_TAPS = {
    'homebrew/cask-fonts'    => 'has been merged into homebrew/cask; install fonts directly (e.g. font-fira-code)',
    'homebrew/cask-drivers'  => 'has been merged into homebrew/cask',
    'homebrew/cask-versions' => 'has been merged into homebrew/cask',
    'homebrew/core'          => 'is served via the Homebrew JSON API and no longer needs to be tapped manually',
    'homebrew/cask'          => 'is served via the Homebrew JSON API and no longer needs to be tapped manually',
    'homebrew/bundle'        => 'is now built into Homebrew and no longer needs to be tapped',
    'homebrew/services'      => 'is now built into Homebrew and no longer needs to be tapped',
  }.freeze

  ensurable

  newparam(:name, :namevar => true) do
    desc 'The tap name in "user/repo" format (e.g. myuser/tools).'

    validate do |value|
      unless value =~ %r{\A[\w.-]+/[\w.-]+\z}
        raise ArgumentError, "Tap name must be in 'user/repo' format, got '#{value}'"
      end
    end

    munge(&:downcase)
  end

  newparam(:force, :boolean => true) do
    desc <<-DOC
      When true, pass `--force` to `brew tap` / `brew untap`. On tap it forces
      the repository to be cloned even when Homebrew would otherwise serve it
      from the JSON API (e.g. force-cloning homebrew/cask). On untap it allows
      removal even while formulae/casks from the tap are still installed
      (`brew untap` refuses otherwise). Only affects the tap/untap commands; it
      is not a persistent, drift-detectable property.
    DOC

    newvalues(:true, :false)
    defaultto false
  end

  newproperty(:url) do
    desc <<-DOC
      Optional custom git URL for the tap. On creation this is passed as
      `brew tap user/repo <url>`. When the tap already exists and the declared
      URL differs from the actual git remote, the remote is corrected in place
      with `brew tap --custom-remote user/repo <url>` (no destructive re-tap).
      When omitted, the URL is not managed.
    DOC
  end

  newproperty(:force_auto_update) do
    desc <<-DOC
      When true, force Homebrew to `git pull` this tap on every `brew update`
      by setting the tap's `homebrew.forceautoupdate` git config. When false,
      the setting is removed. When unspecified, auto-update is not managed.

      (Homebrew removed the `brew tap --force-auto-update` CLI flag in 4.2.13;
      this property manages the underlying git config directly.)
    DOC

    newvalues(:true, :false)
  end

  newproperty(:trust) do
    desc <<-DOC
      When true, trust the tap with `brew trust --tap`; when false, revoke it
      with `brew untrust --tap`. Trusting is required to load
      formulae/casks/commands from non-official taps once
      `HOMEBREW_REQUIRE_TAP_TRUST` is set (the default from Homebrew 6.0.0).
      Official homebrew/* taps are always trusted. When unspecified, trust is
      not managed.

      Trust is granted before the tap is cloned: `brew tap` validates a new tap
      by loading its formulae and casks, which an untrusted tap refuses, and
      brew surfaces that as "Cannot tap <name>: invalid syntax in tap!" before
      deleting the clone. A tap containing casks therefore cannot be tapped at
      all without `trust => true`.

      When `url` is set, trust is recorded against that URL rather than the
      `user/repo` name. Homebrew matches a `user/repo` trust entry only against
      a tap on its canonical github.com remote; `brew trust --tap user/repo`
      resolves the name to the tap's real remote, but only once the tap is
      cloned. Trust being granted before the clone, the URL has to be given
      explicitly or the recorded entry would never match.

      A grant that matches nothing looks exactly like a successful one, so two
      things matter: the URL must be spelled as git records the remote (outside
      github.com, gitlab.com and codeberg.org a `.git` suffix or a trailing
      slash is significant), and the trust store is per user -- Puppet writes
      the brew owner's `$HOME/.homebrew/trust.json`, not the one of whoever runs
      `brew trust` in a terminal.

      Changing `url` moves the trust reference: the provider re-applies trust
      and drops the stale entry, since Homebrew migrates one only on a git
      redirect. `ensure => absent` revokes trust too, but only when this
      resource manages it -- `brew untap` leaves the store untouched.
    DOC

    newvalues(:true, :false)
  end

  validate do
    return if self[:ensure] == :absent

    reason = DEPRECATED_TAPS[self[:name]]
    Puppet.warning("homebrew_tap: '#{self[:name]}' #{reason}") if reason
  end
end
