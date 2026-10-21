# Install a formula and keep its brew service running.
package { 'postgresql@14':
  ensure   => present,
  provider => homebrew,
}

homebrew_service { 'postgresql@14':
  ensure  => running,
  require => Package['postgresql@14'],
}

# Ensure another service stays stopped.
homebrew_service { 'redis':
  ensure => stopped,
}
