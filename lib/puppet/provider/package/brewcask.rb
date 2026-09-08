require 'puppet/provider/package'
require 'puppet_x/homebrew/brew_command'

Puppet::Type.type(:package).provide(:brewcask, :parent => Puppet::Provider::Package) do
  desc 'Package management using HomeBrew casks on OSX'

  confine :operatingsystem => :darwin

  extend PuppetX::Homebrew::BrewCommand

  has_feature :installable
  has_feature :uninstallable
  has_feature :upgradeable
  has_feature :versionable
  has_feature :install_options

  @brewbin = detect_brew_bin
  commands :brew => @brewbin
  commands :stat => '/usr/bin/stat'

  def run_brew(*args, **opts)
    self.class.run_brew(*args, **opts)
  end

  def fix_checksum(files)
    begin
      for file in files
        File.delete(file)
      end
    rescue Errno::ENOENT
      Puppet.warning "Could not remove mismatched checksum files #{files}"
    end

    raise Puppet::ExecutionFailure, "Checksum error for package #{name} in files #{files}"
  end

  def resource_name
    if @resource[:name].match(/^https?:\/\//)
      @resource[:name]
    else
      @resource[:name].downcase
    end
  end

  def install_name
    should = @resource[:ensure].downcase

    case should
    when true, false, Symbol
      resource_name
    else
      "#{resource_name}@#{should}"
    end
  end

  def install_options
    Array(resource[:install_options]).flatten.compact
  end

  def self.instances
    package_list.collect { |hash| new(hash) }
  end

  def latest
    begin
      Puppet.debug "Querying latest for #{resource_name}"
      output = run_brew('info', '--cask', resource_name)

      output.each_line do |line|
        line.chomp!
        next if line.empty?
        next if line !~ /^#{resource_name}:\s([.\d]+)/i
        Puppet.debug "  Latest versions for #{resource_name}: #{$1}"
        return $1
      end
      nil
    rescue Puppet::ExecutionFailure
      Puppet.err "Package #{resource_name} Query Latest failed: #{$!}"
      nil
    end
  end

  def query
    self.class.package_list(:justme => resource_name)
  end

  def install
    begin
      Puppet.debug "Looking for #{install_name} package..."
      run_brew('info', '--cask', install_name)
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not find package: #{install_name}"
    end

    begin
      Puppet.debug "Package found, installing..."
      output = run_brew('install', '--cask', install_name, *install_options)

      if output =~ /sha256 checksum/
        Puppet.debug "Fixing checksum error..."
        mismatched = output.match(/Already downloaded: (.*)/).captures
        fix_checksum(mismatched)
      end
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not install package: #{detail}"
    end
  end

  def uninstall
    begin
      Puppet.debug "Uninstalling #{resource_name}"
      run_brew('uninstall', '--cask', resource_name)
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not uninstall package: #{detail}"
    end
  end

  def update
    if installed?
      Puppet.debug "Updating #{resource_name}"
      begin
        run_brew('info', '--cask', resource_name)
      rescue Puppet::ExecutionFailure => detail
        raise Puppet::Error, "Could not find package: #{install_name}"
      end

      begin
        Puppet.debug "Package found, upgrading..."
        output = run_brew('upgrade', '--cask', install_name, *install_options)

        if output =~ /sha256 checksum/
          Puppet.debug "Fixing checksum error..."
          mismatched = output.match(/Already downloaded: (.*)/).captures
          fix_checksum(mismatched)
        end
      rescue Puppet::ExecutionFailure => detail
        raise Puppet::Error, "Could not upgrade package: #{detail}"
      end
    else
      install
    end
  end

  def installed?
    is_not_installed = run_brew('info', '--cask', install_name).split("\n").grep(/^Not installed$/).first
    is_not_installed.nil?
  rescue Puppet::ExecutionFailure => detail
    raise Puppet::Error, "Could not get status of package: #{detail}"
  end

  def self.package_list(options={})
    Puppet.debug "Listing installed packages"
    begin
      if resource_name = options[:justme]
        result = run_brew('list', '--cask', '--versions', resource_name, failonfail: false)
        if result.empty?
          Puppet.debug "Package #{resource_name} not installed"
        else
          Puppet.debug "Found package #{result}"
        end
      else
        result = run_brew('list', '--cask', '--versions')
      end
      list = result.lines.map { |line| name_version_split(line) }
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list packages: #{detail}"
    end

    if options[:justme]
      return list.shift
    else
      return list
    end
  end

  def self.name_version_split(line)
    if line =~ (/^(\S+)\s+([.\d]+)/)
      {
        :name     => $1,
        :ensure   => $2,
        :provider => :brewcask
      }
    else
      Puppet.warning "Could not match #{line}"
      nil
    end
  end
end
