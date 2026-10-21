require 'etc'
require 'json'

module PuppetX
  module Homebrew
    # Shared brew-invocation logic for the custom Homebrew providers
    # (homebrew_tap, homebrew_pin, homebrew_service, homebrew_bundle).
    #
    # `extend` this module into a provider class that has already declared
    # `commands :brew => ...`. It then exposes `detect_brew_bin` (to pick the
    # brew path at class-load time) and `run_brew` (which drops privileges to
    # the brew owner, since Homebrew refuses to run as root while Puppet usually
    # does).
    module BrewCommand
      INTEL_BREW         = '/usr/local/bin/brew'.freeze
      APPLE_SILICON_BREW = '/opt/homebrew/bin/brew'.freeze
      OFFICIAL_TAPS      = { formula: 'homebrew/core', cask: 'homebrew/cask' }.freeze

      # Locate the brew binary. The default prefix is architecture-dependent
      # (/opt/homebrew on Apple Silicon, /usr/local on Intel), so we use the
      # is_arm64 custom fact (which runs `arch -arm64 true`) rather than a
      # filesystem probe — both prefixes can coexist under Rosetta 2 and a
      # probe would silently pick the wrong one. We still fall back to the
      # other prefix to support non-default install locations.
      def detect_brew_bin
        is_arm64 = begin
          Facter.value('is_arm64')
        rescue StandardError
          nil
        end

        candidates = if is_arm64
                       [APPLE_SILICON_BREW, INTEL_BREW]
                     else
                       [INTEL_BREW, APPLE_SILICON_BREW]
                     end

        candidates.find { |path| File.exist?(path) } || candidates.first
      end

      # Run a brew command as the user who owns the brew binary. Homebrew
      # refuses to run as root, but Puppet usually runs as root, so we drop
      # privileges to the brew owner.
      #
      # Pass `combine: false` for commands whose stdout must be parsed (e.g.
      # `--json`): brew writes status chatter ("Fetching...", JSON-API refresh
      # notices, env hints) to stderr, and combining it into stdout corrupts
      # JSON.parse.
      # Pass `failonfail: false` for commands whose non-zero exit is a normal
      # outcome rather than an error (e.g. `brew list --versions <name>`, which
      # exits 1 when the named package simply isn't installed). Execution then
      # returns the output instead of raising Puppet::ExecutionFailure.
      def run_brew(*args, combine: true, failonfail: true)
        run_owned(command(:brew), *args, combine: combine, failonfail: failonfail)
      end

      # Parsed `brew list --json --versions [extra args]`, or nil when brew
      # cannot serve it -- `--json` exists only in brew's Bash fast path
      # (list.sh), which needs `jq`; cmd/list.rb raises a UsageError for it, and
      # macOS ships /usr/bin/jq only from 15 on, so callers keep a text
      # fallback. Preferred where available: nothing to misparse, and no "Cask
      # <token> exists in multiple taps" abort losing the whole listing.
      #
      # combine: false -- brew writes tap deprecation warnings to stderr, and
      # merged output is not parseable JSON.
      def brew_list_json(*args)
        output = run_brew('list', '--json', '--versions', *args, failonfail: false, combine: false)
        return nil if output.respond_to?(:exitstatus) && !output.exitstatus.zero?

        JSON.parse(output.to_s)
      rescue JSON::ParserError => detail
        Puppet.debug "Could not parse the brew JSON listing: #{detail}"
        nil
      end

      # Outdated installed packages, keyed by name => { 'version', 'tap',
      # 'pinned' }, as brew itself compares versions. Whole-installation
      # queries only: named ones fail on ambiguous tokens.
      #
      # `brew info`, unlike `brew outdated`, includes untrusted taps.
      def outdated_formulae
        list = {}
        installed_info(:formula).each do |formula|
          next unless formula['outdated']

          stable   = formula.dig('versions', 'stable').to_s
          revision = formula['revision'].to_i
          list[formula['full_name'].to_s] = {
            'version' => revision > 0 ? "#{stable}_#{revision}" : stable,
            'tap'     => formula['tap'],
            'pinned'  => formula['pinned'] ? true : false,
          }
        end
        list
      end

      # `brew info` omits auto_updates casks, `brew outdated` untrusted taps:
      # both are needed. --greedy would add `version :latest` casks, which are
      # always outdated.
      def outdated_casks
        list = {}
        taps = {}
        installed_info(:cask).each do |cask|
          taps[cask['token'].to_s] = cask['tap']
          next unless cask['outdated']

          list[cask['full_token'].to_s] = { 'version' => cask['version'].to_s, 'tap' => cask['tap'] }
        end
        Array(brew_json('outdated', '--json=v2', '--greedy-auto-updates', '--cask')['casks']).each do |cask|
          name = cask['name'].to_s
          list[name] = { 'version' => cask['current_version'].to_s, 'tap' => taps[name.split('/').last] }
        end
        list
      end

      # `brew info --json=v2 --installed` entries of one kind (:formula or
      # :cask), fetched once per run. A failure is kept and raised again.
      def installed_info(kind)
        @installed_info ||= {}
        @installed_info[kind] ||= begin
          Array(brew_json('info', '--json=v2', '--installed', "--#{kind}")[kind == :cask ? 'casks' : 'formulae'])
        rescue Puppet::ExecutionFailure => detail
          detail
        end
        raise @installed_info[kind] if @installed_info[kind].is_a?(Exception)

        @installed_info[kind]
      end

      # Whether the brew owner has not trusted `tap` (trust is per user).
      # Packages from such taps are not upgraded. Unknown taps and brew
      # without tap trust count as trusted.
      def untrusted_tap?(tap)
        @untrusted_taps ||= Array(brew_json('tap-info', '--json', '--installed'))
                            .select { |info| info['trusted'] == false }
                            .map { |info| info['name'] }
        @untrusted_taps.include?(tap)
      end

      def untrusted_tap_message(current, entry)
        "#{entry['version']} is available (installed: #{current}) but will not be installed: " \
          "tap #{entry['tap']} is not trusted by the brew owner. " \
          "Trust it with homebrew_tap { '#{entry['tap']}': trust => true }"
      end

      # Called from prefetch: a daemon keeps provider classes between runs.
      def forget_brew_state
        @outdated       = nil
        @untrusted_taps = nil
        @installed_info = nil
      end

      # Exact name first, then short name (tapped packages are keyed in full).
      # A qualified name only matches an entry from its own tap.
      def outdated_lookup(list, name)
        return list[name] if list.key?(name)

        qualified, tap, short = parse_package_name(name)
        list.each do |key, entry|
          next unless key.split('/').last == short
          return entry if !qualified || third_party_tap(entry['tap']) == tap
        end
        nil
      end

      # [qualified?, tap, short name] of a package name. `user/repo/name` is
      # qualified; tap is nil for a bare name or an official tap.
      def parse_package_name(name)
        parts = name.to_s.split('/')
        return [false, nil, name.to_s] if parts.size != 3 || name.to_s =~ %r{\Ahttps?://}

        [true, third_party_tap(tap_name(parts[0], parts[1])), parts[2]]
      end

      # A tap named as brew names it (Tap.fetch): `user/homebrew-repo` is
      # `user/repo`.
      def tap_name(user, repo)
        user = user.downcase
        repo = repo.downcase.sub(/\A(?:home|linux)brew-/, '')
        return 'homebrew/core' if %w[homebrew linuxbrew].include?(user) && %w[core homebrew].include?(repo)

        "#{user}/#{repo}"
      end

      # nil for an official tap or none, the tap otherwise.
      def third_party_tap(tap)
        tap.nil? || OFFICIAL_TAPS.value?(tap) ? nil : tap
      end

      # [kind, tap] an installed package was installed from, by short name,
      # in `kinds` order; tap is nil for an official one.
      def installed_origin(short, kinds)
        kinds.each do |kind|
          key   = kind == :cask ? 'token' : 'name'
          entry = installed_info(kind).find { |pkg| pkg[key].to_s == short }
          return [kind, third_party_tap(entry['tap'])] if entry
        end
        nil
      end

      # A package declared as `user/tap/name` but installed from another tap is
      # left as is with this warning; nil otherwise.
      def other_tap_warning(name, kinds)
        qualified, tap, short = parse_package_name(name)
        return nil unless qualified

        kind, origin = installed_origin(short, kinds)
        return nil if kind.nil? || origin == tap

        "#{short} is installed from #{origin || OFFICIAL_TAPS[kind]}, not #{name.to_s.rpartition('/').first}; leaving it as is"
      rescue Puppet::ExecutionFailure => detail
        Puppet.debug "Could not check where #{name} was installed from: #{detail}"
        nil
      end

      # `query` for a package that may be named `user/tap/name`. One installed
      # from another tap is found, but absent for ensure => absent: brew
      # refuses to uninstall it under that name.
      def tap_checked_query(resource, name, kinds)
        found   = package_list(:justme => name)
        warning = found && other_tap_warning(name, kinds)
        return found unless warning

        resource.warning warning
        resource[:ensure] == :absent ? nil : found
      end

      # Parsed JSON output of a brew command. stderr is kept out of the parse,
      # and fetched again on failure for the error message. `empty` is
      # returned when the command succeeds without output.
      def brew_json(*cmd, empty: nil)
        output = run_brew(*cmd, failonfail: false, combine: false)
        if !output.respond_to?(:exitstatus) || output.exitstatus.zero?
          return empty if !empty.nil? && output.to_s.strip.empty?

          begin
            parsed = JSON.parse(output.to_s)
            return parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)
          rescue JSON::ParserError
            nil
          end
        end

        detail = run_brew(*cmd, failonfail: false).to_s.strip
        raise Puppet::ExecutionFailure, "brew #{cmd.join(' ')} failed: #{detail}"
      end

      # Run an arbitrary command as the brew owner, using the same privilege
      # drop as run_brew. Useful for tap-adjacent commands that are not `brew`
      # itself (e.g. `git config` on a tap's clone, which is owned by the brew
      # user). The owner is derived from the brew binary's ownership.
      #
      # `combine` controls whether stderr is merged into the returned stdout
      # (default true, matching Puppet's usual behaviour); set false when the
      # caller parses stdout.
      def run_owned(*cmd, combine: true, failonfail: true)
        brew_path    = command(:brew)
        owner, group = brew_owner(brew_path)
        passwd       = Etc.getpwuid(owner)
        home         = passwd.dir

        if owner.zero?
          raise Puppet::ExecutionFailure,
                'Homebrew does not support installations owned by the "root" user. ' \
                'Please check the ownership of the brew binary.'
        end

        # uid/gid can only be set when the current process is root.
        if Process.uid.zero?
          uid = owner
          gid = group
        else
          uid = nil
          gid = nil
        end

        opts = {
          :uid                => uid,
          :gid                => gid,
          :combine            => combine,
          # brew refuses to start on a cwd it cannot read, and Puppet's own is
          # often untraversable for the brew owner. Puppet chdirs before
          # dropping privileges, so this is checked as the target user.
          :cwd                => safe_cwd(home),
          :custom_environment => {
            'HOME'                    => home,
            # brew dereferences $USER under `set -u`; a launchd-started agent
            # has none, aborting with "unbound variable".
            'USER'                    => passwd.name,
            'LOGNAME'                 => passwd.name,
            # Reads must not trigger a network `brew update` mid-run.
            'HOMEBREW_NO_AUTO_UPDATE' => '1',
          },
          :failonfail         => failonfail,
        }

        if Puppet.features.bundled_environment?
          Bundler.with_clean_env do
            Puppet::Util::Execution.execute(cmd, opts)
          end
        else
          Puppet::Util::Execution.execute(cmd, opts)
        end
      end

      # uid and gid of the brew binary, read in process: run before every brew
      # command. lstat, like `stat -f`: a symlink's own owner.
      def brew_owner(path)
        info = File.lstat(path)
        [info.uid, info.gid]
      rescue SystemCallError => detail
        raise Puppet::ExecutionFailure, "Could not read the owner of #{path}: #{detail}"
      end

      # A working directory the brew owner can read; /tmp when their home is
      # missing (service accounts).
      def safe_cwd(home)
        home && File.directory?(home) ? home : '/tmp'
      end
    end
  end
end
