require 'json'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:homebrew_tap).provide(:brew) do
  desc 'Manages Homebrew taps using the `brew tap` command on macOS.'

  extend PuppetX::Homebrew::BrewCommand

  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin

  @brewbin = detect_brew_bin

  commands :brew => @brewbin
  commands :stat => '/usr/bin/stat'

  # git is used to read/write the tap's `homebrew.forceautoupdate` config. We
  # resolve it ourselves (rather than via `commands`) so a missing git never
  # makes the whole provider unsuitable -- it only disables force_auto_update.
  GIT_BIN = ['/usr/bin/git', '/opt/homebrew/bin/git', '/usr/local/bin/git'].find { |p| File.exist?(p) } || 'git'

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  def run_owned(*cmd, **opts)
    self.class.run_owned(*cmd, **opts)
  end

  # Every installed tap in one call: `name`, `path`, `remote` and a `trusted`
  # boolean. combine: false -- brew's stderr chatter would corrupt JSON.parse.
  def self.installed_taps
    output = run_brew('tap-info', '--installed', '--json', combine: false)
    JSON.parse(output)
  rescue StandardError => e
    Puppet.debug("Could not read homebrew taps: #{e}")
    []
  end

  # Read a single-value git config key from the tap's clone. Returns nil when
  # the key is unset or the read fails. combine: false so a git warning on
  # stderr can't leak into the value.
  def self.git_config(path, key)
    return nil if path.nil? || path.to_s.empty?

    value = run_owned(GIT_BIN, '-C', path.to_s, 'config', '--get', key, combine: false).to_s.strip
    value.empty? ? nil : value
  rescue StandardError
    nil
  end

  # The tap's git remote. tap-info reports it directly (nil only for API-backed
  # taps with no clone), which saves a privileged `git` per tap and sidesteps
  # git's "dubious ownership" refusal; the git read stays as a fallback.
  def self.remote_url_for(tap)
    remote = tap['remote'].to_s.strip
    return remote unless remote.empty?

    git_config(tap['path'], 'remote.origin.url')
  end

  # Whether the tap is configured to auto-update on every `brew update`.
  def self.force_auto_update_for(path)
    git_config(path, 'homebrew.forceautoupdate') == 'true' ? :true : :false
  end

  # tap-info's `trusted` covers official taps and trust.json entries alike.
  def self.trust_state(tap)
    tap['trusted'] ? :true : :false
  end

  def self.instances
    tap_info = installed_taps.each_with_object({}) { |t, h| h[t['name'].to_s.downcase] = t }

    # `brew tap` enumerates tap directories on disk, including those with a
    # corrupted git repo that `brew tap-info --json` silently omits.
    all_names = begin
      run_brew('tap', combine: false).to_s.lines.map { |l| l.chomp.strip.downcase }.reject(&:empty?)
    rescue StandardError => e
      Puppet.debug("Could not enumerate taps via 'brew tap': #{e}")
      tap_info.keys
    end

    all_names.map do |name|
      if (tap = tap_info[name])
        new(
          :name              => name,
          :ensure            => :present,
          :path              => tap['path'],
          :url               => remote_url_for(tap),
          :force_auto_update => force_auto_update_for(tap['path']),
          :trust             => trust_state(tap),
        )
      else
        Puppet.warning("homebrew_tap: '#{name}' is present on disk but missing from " \
                       "'brew tap-info --json' (possibly corrupted); only ensure is managed.")
        new(:name => name, :ensure => :present)
      end
    end
  end

  def self.prefetch(resources)
    instances.each do |provider|
      if (resource = resources[provider.name])
        resource.provider = provider
      end
    end
  end

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :present
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def url
    @property_hash[:url]
  end

  def url=(value)
    @property_flush[:url] = value
  end

  def force_auto_update
    @property_hash[:force_auto_update]
  end

  def force_auto_update=(value)
    @property_flush[:force_auto_update] = value
  end

  def trust
    @property_hash[:trust]
  end

  def trust=(value)
    @property_flush[:trust] = value
  end

  def flush
    if @property_flush[:ensure] == :absent
      untap
      # `brew untap` leaves the trust store untouched, so the entry would
      # outlive the tap and silently trust a later re-tap. Only when managed.
      revoke_trust unless resource[:trust].nil?
      @property_hash = { :ensure => :absent }
    elsif @property_flush[:ensure] == :present
      # Trust first: `brew tap` validates the clone by loading its formulae and
      # casks, which an untrusted tap refuses ("Cannot tap <name>: invalid
      # syntax in tap!"), then deletes the clone -- failing identically forever.
      apply_trust(resource[:trust]) unless resource[:trust].nil?
      tap
      # Read the tap back once, then apply the declared properties.
      fresh = self.class.installed_taps.find { |t| t['name'].to_s.downcase == resource[:name] }
      if fresh
        @property_hash = {
          :ensure            => :present,
          :path              => fresh['path'],
          :url               => self.class.remote_url_for(fresh),
          :force_auto_update => self.class.force_auto_update_for(fresh['path']),
          :trust             => self.class.trust_state(fresh),
        }
      else
        @property_hash = { :ensure => :present }
      end
      # :trust is absent on purpose: already applied above, before the clone.
      wanted = { :force_auto_update => resource[:force_auto_update] }.reject { |_, v| v.nil? }
      apply_properties(wanted)
      wanted.each { |k, v| @property_hash[k] = v }
      # Keep the state tap-info reported: a grant can match nothing.
      warn_trust_mismatch
    else
      # Existing tap: apply only drifted properties, update @property_hash in place.
      apply_properties(@property_flush)
      @property_flush.each { |k, v| @property_hash[k] = v }
      # Both move the trust reference: confirm it rather than assume it.
      refresh_trust_state if @property_flush.key?(:trust) || @property_flush.key?(:url)
    end
    @property_flush = {}
  end

  private

  def force?
    [true, :true].include?(resource[:force])
  end

  def tap
    args = ['tap']
    args << '--force' if force?
    args << resource[:name]
    args << resource[:url] if resource[:url]
    Puppet.debug("Tapping #{resource[:name]}")
    run_brew(*args)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not tap #{resource[:name]}: #{trust_hint(e)}"
  end

  # `brew tap` reports *any* formula or cask it cannot load as "Cannot tap
  # <name>: invalid syntax in tap!", a genuine syntax error included. Blame the
  # trust check only when brew said so, or when trust is not granted here:
  # insisting on `trust => true` for a trusted tap hides the real cause.
  def trust_hint(error)
    message = error.to_s
    untrusted = message.include?('untrusted tap') || message.include?('Refusing to load')
    return message unless untrusted || message.include?('invalid syntax in tap')

    if !untrusted && resource[:trust] == :true
      return "#{message}\n" \
             'This tap is already trusted, so this is not the tap-trust check: `brew tap` reports ' \
             'any formula or cask it cannot load as "invalid syntax in tap". The brew output above ' \
             'names the offending file.'
    end

    url_note = if resource[:url]
                 " It will be trusted as #{resource[:url]}, since Homebrew keys trust on the " \
                   'remote URL for custom-remote taps.'
               else
                 ''
               end
    lead = if untrusted
             "This is Homebrew's tap-trust check, not a syntax error: "
           else
             "This is most likely Homebrew's tap-trust check rather than a syntax error: "
           end

    "#{message}\n" \
      "#{lead}`brew tap` validates the clone by loading its formulae and casks, which is refused " \
      "for a tap that is not trusted. Declare `trust => true` on homebrew_tap { '#{resource[:name]}': } " \
      "so the tap is trusted before it is cloned.#{url_note}"
  end

  def untap
    args = ['untap']
    # brew refuses to untap while formulae/casks from the tap are installed
    # unless --force is given.
    args << '--force' if force?
    args << resource[:name]
    Puppet.debug("Untapping #{resource[:name]}")
    run_brew(*args)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not untap #{resource[:name]}: #{e}"
  end

  # Correct the git remote of an already-tapped repo in place, without a
  # destructive untap/re-tap.
  def set_remote(url)
    Puppet.debug("Setting custom remote for #{resource[:name]} to #{url}")
    run_brew('tap', '--custom-remote', resource[:name], url)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set custom remote for #{resource[:name]}: #{e}"
  end

  # `url` first: unlike `brew tap` on a new tap, `--custom-remote` does not
  # re-run the Readall verification (Tap#install returns in its `installed?`
  # branch), and trusting afterwards leaves no entry behind if it fails.
  #
  # That same branch deletes the tap's `homebrew.forceautoupdate`, and moving
  # the remote invalidates the trust entry keyed on the previous URL (brew
  # migrates one only on a git redirect). Both are therefore re-applied whenever
  # they are managed -- not only when they drifted, which is when Puppet would
  # otherwise lose them silently.
  def apply_properties(updates)
    url_changed = updates.key?(:url)

    if url_changed
      previous_url = @property_hash[:url]
      set_remote(updates[:url])
      @property_hash[:url] = updates[:url]
      # The entry for the previous remote cannot match any more; the new
      # reference is applied just below.
      if !resource[:trust].nil? && previous_url && previous_url != updates[:url]
        untrust_reference(previous_url)
      end
    end

    trust = updates.key?(:trust) ? updates[:trust] : (resource[:trust] if url_changed)
    apply_trust(trust) unless trust.nil?

    auto_update = if updates.key?(:force_auto_update)
                    updates[:force_auto_update]
                  elsif url_changed
                    resource[:force_auto_update]
                  end
    apply_force_auto_update(auto_update) unless auto_update.nil?
  end

  def apply_force_auto_update(value)
    dir = (@property_hash[:path] || tap_path).to_s
    return if dir.empty?

    if value == :true
      run_owned(GIT_BIN, '-C', dir, 'config', 'homebrew.forceautoupdate', 'true')
    elsif self.class.git_config(dir, 'homebrew.forceautoupdate')
      # Only unset when the key is actually present, so that any --unset failure
      # (permission, locked config) is a genuine error rather than git's exit-5
      # "nothing to unset" -- and it surfaces instead of being swallowed.
      run_owned(GIT_BIN, '-C', dir, 'config', '--unset', 'homebrew.forceautoupdate')
    end
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set force_auto_update for #{resource[:name]}: #{e}"
  end

  # The reference `brew trust` must record. Homebrew keys trust on the remote
  # for a custom-remote tap (a `user/repo` entry matches only a tap on its
  # canonical GitHub remote) and cannot resolve it before the clone, so the URL
  # is passed explicitly -- resource[:url] first, so a tap whose URL is changing
  # is trusted under the one it moves to. It must spell the remote as git
  # records it: outside github.com, gitlab.com and codeberg.org a `.git` suffix
  # or a trailing slash is significant.
  def trust_reference
    resource[:url] || @property_hash[:url] || resource[:name]
  end

  # Every reference this tap's trust may be recorded under: the name form and
  # the URLs we know of. Homebrew deletes an exact string, so revoking one form
  # leaves the other standing -- and a bare-name entry is what an earlier
  # release (or an operator) recorded before the clone. A missing entry is
  # reported as "Not trusted tap" with exit 0, so the extra calls are harmless.
  def trust_references(extra = [])
    ([resource[:url], @property_hash[:url], resource[:name]] + extra)
      .compact.map { |reference| reference.to_s.strip }.reject(&:empty?).uniq
  end

  def apply_trust(value)
    if value == :true
      reference = trust_reference
      Puppet.debug("Trusting #{resource[:name]} as #{reference}")
      run_brew('trust', '--tap', reference)
    else
      revoke_trust
    end
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not set trust for #{resource[:name]}: #{e}"
  end

  def revoke_trust(extra = [])
    trust_references(extra).each { |reference| untrust_reference(reference) }
  end

  def untrust_reference(reference)
    Puppet.debug("Untrusting #{resource[:name]} as #{reference}")
    run_brew('untrust', '--tap', reference)
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not revoke trust for #{resource[:name]}: #{e}"
  end

  # Re-read the real trust state after a change that moves the reference, so a
  # grant that matches nothing is reported rather than assumed.
  def refresh_trust_state
    fresh = self.class.installed_taps.find { |t| t['name'].to_s.downcase == resource[:name] }
    return if fresh.nil?

    @property_hash[:trust] = self.class.trust_state(fresh)
    warn_trust_mismatch
  end

  # A recorded entry that matches nothing looks exactly like a successful
  # `brew trust`, so report the disagreement instead of going green on it.
  def warn_trust_mismatch
    wanted = resource[:trust]
    actual = @property_hash[:trust]
    return if wanted.nil? || actual.nil? || actual == wanted

    Puppet.warning(
      "homebrew_tap: #{resource[:name]} is still #{actual == :true ? 'trusted' : 'untrusted'} " \
      "after applying trust => #{wanted}. Homebrew matches a custom-remote tap against its exact " \
      'remote URL -- outside github.com, gitlab.com and codeberg.org a `.git` suffix or a trailing ' \
      "slash is significant, so `url` must be spelled as git records it -- and the trust store is " \
      "per user: Puppet writes the brew owner's ~/.homebrew/trust.json, not the one of whoever runs " \
      '`brew trust` in a terminal.'
    )
  end

  def tap_path
    run_brew('--repository', resource[:name], combine: false).to_s.strip
  end

  def query
    self.class.installed_taps.each do |tap|
      next unless tap['name'].to_s.downcase == resource[:name]

      return {
        :name              => resource[:name],
        :ensure            => :present,
        :url               => self.class.remote_url_for(tap),
        :force_auto_update => self.class.force_auto_update_for(tap['path']),
        :trust             => self.class.trust_state(tap),
      }
    end
    nil
  end
end
