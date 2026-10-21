package { 'git':  # in homebrew
  ensure   => present,
  provider => homebrew,
}

package { 'bazaar':  # in homebrew
  ensure   => present,
  provider => homebrew,
}

package { 'clementine':  # in brewcask
  ensure   => present,
  provider => brewcask,
}

package { 'google-chrome':  # in brewcask
  ensure   => present,
  provider => brewcask,
}
