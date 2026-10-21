# Pin an installed formula so `brew upgrade` leaves it alone.
package { 'postgresql@14':
  ensure   => present,
  provider => homebrew,
}

homebrew_pin { 'postgresql@14':
  ensure  => present,
  require => Package['postgresql@14'],
}

# Explicitly unpin another formula.
homebrew_pin { 'openssl@3':
  ensure => absent,
}
