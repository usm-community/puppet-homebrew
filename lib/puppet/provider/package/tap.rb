require 'puppet/provider/package'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:package).provide(:tap, :parent => Puppet::Provider::Package) do
  desc 'Tap management using HomeBrew on macOS'

  confine :operatingsystem => :darwin

  extend PuppetX::Homebrew::BrewCommand

  has_feature :installable
  has_feature :uninstallable
  has_feature :install_options

  @brewbin = detect_brew_bin
  commands :brew => @brewbin

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  def install_options
    Array(resource[:install_options]).flatten.compact
  end

  def install
    resource_name = @resource[:name].downcase

    begin
      Puppet.debug "Tapping #{resource_name}"
      run_brew('tap', resource_name, *install_options)
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not tap resource: #{detail}"
    end
  end

  def uninstall
    resource_name = @resource[:name].downcase

    begin
      Puppet.debug "Untapping #{resource_name}"
      run_brew('untap', resource_name)
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not untap resource: #{detail}"
    end
  end

  def query
    resource_name = @resource[:name].downcase

    begin
      Puppet.debug "Querying tap #{resource_name}"
      output = run_brew('tap')
      output.each_line do |line|
        line.chomp!
        next unless [resource_name, resource_name.gsub('homebrew-', '')].include?(line.downcase)

        return { :name => line, :ensure => 'present', :provider => 'tap' }
      end
    rescue Puppet::ExecutionFailure => detail
      Puppet.err "Could not query tap: #{detail}"
    end

    nil
  end

  def self.instances
    taps = []

    begin
      Puppet.debug "Listing currently tapped repositories"
      output = run_brew('tap')
      output.each_line do |line|
        line.chomp!
        next if line.empty?

        taps << new({ :name => line, :ensure => 'present', :provider => 'tap' })
      end
      taps
    rescue Puppet::ExecutionFailure => detail
      Puppet.err "Could not list taps: #{detail}"
      nil
    end
  end
end
