# Fact: homebrew
#
# Purpose: where Homebrew lives, as homebrew::install lays it out
#
# Resolution:
#   Paths follow the processor (is_arm64), not the agent's architecture: an
#   Intel agent under Rosetta gets the Apple Silicon paths, although it cannot
#   install there. Returns a hash with prefix, repository, brew and installed.
#   No value set if not on Darwin

Facter.add(:homebrew) do
  confine kernel: 'Darwin'

  setcode do
    # is_arm64 is nil here when overridden through FACTER_is_arm64, and a
    # string when given as an external fact: test the processor again then.
    arm64 = Facter.value(:is_arm64)
    arm64 = system('arch -arm64 true >/dev/null 2>&1') unless [true, false].include?(arm64)
    if arm64
      prefix     = '/opt/homebrew'
      repository = prefix
    else
      prefix     = '/usr/local'
      repository = "#{prefix}/Homebrew"
    end
    brew = "#{prefix}/bin/brew"

    {
      'prefix'     => prefix,
      'repository' => repository,
      'brew'       => brew,
      'installed'  => File.executable?(brew),
    }
  end
end
