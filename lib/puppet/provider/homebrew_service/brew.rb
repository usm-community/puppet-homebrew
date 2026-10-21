require 'json'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:homebrew_service).provide(:brew) do
  desc 'Manages Homebrew services using `brew services` on macOS.'

  extend PuppetX::Homebrew::BrewCommand

  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin

  @brewbin = detect_brew_bin

  commands :brew => @brewbin

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  # `brew services list --json` returns an array of objects exposing the
  # service `name` and `status` (started/stopped/none/error/scheduled).
  # An unreadable list fails the prefetch: an empty one would hide every
  # service's real state. Older brew prints nothing, not `[]`, when there
  # are no services.
  def self.service_list
    brew_json('services', 'list', '--json', empty: [])
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not read homebrew services: #{e}"
  end

  def self.instances
    service_list.map do |svc|
      new(
        :name   => svc['name'].to_s.downcase,
        :ensure => svc['status'].to_s == 'started' ? :running : :stopped,
      )
    end
  end

  def self.prefetch(resources)
    instances.each do |provider|
      if (resource = resources[provider.name])
        resource.provider = provider
      end
    end
  end

  # A service missing from the list is stopped.
  def status
    @property_hash[:ensure] || :stopped
  end

  def start
    Puppet.debug("Starting brew service #{resource[:name]}")
    run_brew('services', 'start', resource[:name])
    @property_hash[:ensure] = :running
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not start service #{resource[:name]}: #{e}"
  end

  def stop
    Puppet.debug("Stopping brew service #{resource[:name]}")
    run_brew('services', 'stop', resource[:name])
    @property_hash[:ensure] = :stopped
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not stop service #{resource[:name]}: #{e}"
  end
end
