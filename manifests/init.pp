class homebrew (
  $user,
  $group                      = 'admin',
  $multiuser                  = false,
  Optional[Stdlib::Absolutepath] $user_home = undef,
  Hash[String, String] $homebrew_environment = {},
  $github_token               = undef,
  $command_line_tools_package = undef,
  $command_line_tools_source  = undef,
  Boolean $manage_update      = false,
  Integer[60] $update_frequency   = 86400,
) {
  if $facts['os']['name'] != 'Darwin' {
    fail('This Module works on macOS only!')
  }

  if $homebrew::user == 'root' {
    fail('Homebrew does not support installation as the "root" user.')
  }

  class { 'homebrew::compiler': }
  -> class { 'homebrew::install': }

  contain 'homebrew::compiler'
  contain 'homebrew::install'

  if $manage_update {
    class { 'homebrew::update': }
    contain 'homebrew::update'
    Class['homebrew::install'] -> Class['homebrew::update']
  }

  # HOMEBREW_GITHUB_API_TOKEN keeps its dedicated parameter for backwards
  # compatibility; any additional HOMEBREW_* variable can be set through the
  # $homebrew_environment hash (e.g. { 'HOMEBREW_NO_AUTO_UPDATE' => '1' }).
  $_environment = $homebrew::github_token ? {
    undef   => $homebrew::homebrew_environment,
    default => $homebrew::homebrew_environment + { 'HOMEBREW_GITHUB_API_TOKEN' => $homebrew::github_token },
  }

  unless empty($_environment) {
    ensure_resource('file', '/etc/environment', { 'ensure' => 'file' })

    $_environment_lines = $_environment.reduce([]) |$memo, $pair| {
      $var   = $pair[0]
      $value = $pair[1]
      $entry = "${var}=${value}"

      file_line { "homebrew-environment-${var}":
        path    => '/etc/environment',
        line    => $entry,
        match   => "^${var}=",
        require => File['/etc/environment'],
      }

      $memo + [$entry]
    }

    # Homebrew >= 4.1 natively reads HOMEBREW_* vars from $HOME/.homebrew/brew.env,
    $_user_home = $homebrew::user_home ? {
      undef   => "/Users/${homebrew::user}",
      default => $homebrew::user_home,
    }

    file { "${_user_home}/.homebrew":
      ensure => directory,
      owner  => $homebrew::user,
      group  => $homebrew::group,
      mode   => '0755',
    }

    file { "${_user_home}/.homebrew/brew.env":
      ensure  => file,
      owner   => $homebrew::user,
      group   => $homebrew::group,
      mode    => '0644',
      content => "${_environment_lines.join("\n")}\n",
      require => File["${_user_home}/.homebrew"],
    }
  }
}
