require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:homebrew_pin).provide(:brew) do
  desc 'Pins/unpins Homebrew formulae using `brew pin` / `brew unpin` on macOS.'

  extend PuppetX::Homebrew::BrewCommand

  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin

  @brewbin = detect_brew_bin

  commands :brew => @brewbin

  def run_brew(*args)
    self.class.run_brew(*args)
  end

  # `brew list --pinned` prints one pinned formula name per line.
  def self.pinned_formulae
    output = run_brew('list', '--pinned')
    output.to_s.split("\n").map { |line| line.strip.downcase }.reject(&:empty?)
  rescue StandardError => e
    Puppet.debug("Could not read pinned homebrew formulae: #{e}")
    []
  end

  def self.instances
    pinned_formulae.map do |name|
      new(:name => name, :ensure => :present)
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

  def flush
    if @property_flush[:ensure] == :absent
      unpin
    elsif @property_flush[:ensure] == :present
      pin
    end

    @property_hash = { :name => resource[:name], :ensure => @property_flush[:ensure] || :absent }
    @property_flush = {}
  end

  private

  def pin
    Puppet.debug("Pinning #{resource[:name]}")
    run_brew('pin', resource[:name])
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not pin #{resource[:name]}: #{e}"
  end

  def unpin
    Puppet.debug("Unpinning #{resource[:name]}")
    run_brew('unpin', resource[:name])
  rescue Puppet::ExecutionFailure => e
    raise Puppet::Error, "Could not unpin #{resource[:name]}: #{e}"
  end
end
