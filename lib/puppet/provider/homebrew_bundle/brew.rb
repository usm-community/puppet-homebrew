require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:homebrew_bundle).provide(:brew) do
  desc 'Applies a Brewfile using `brew bundle` on macOS.'

  extend PuppetX::Homebrew::BrewCommand

  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin

  @brewbin = detect_brew_bin

  commands :brew => @brewbin

  def run_brew(*args)
    self.class.run_brew(*args)
  end

  def brewfile
    resource.brewfile
  end

  # `brew bundle check` exits non-zero when the Brewfile is not satisfied.
  def exists?
    run_brew('bundle', 'check', "--file=#{brewfile}")
    true
  rescue Puppet::ExecutionFailure
    false
  end

  def create
    Puppet.debug("Installing Brewfile #{brewfile}")
    run_brew('bundle', 'install', "--file=#{brewfile}")
    cleanup if resource[:cleanup] == :true
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not apply Brewfile #{brewfile}: #{e}"
  end

  private

  def cleanup
    Puppet.debug("Cleaning up packages not in #{brewfile}")
    run_brew('bundle', 'cleanup', '--force', "--file=#{brewfile}")
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not clean up Brewfile #{brewfile}: #{e}"
  end
end
