class homebrew::install {

  # Homebrew/install dropped Intel on 2026-09-11 (e078684): HEAD now aborts on
  # x86_64 and only knows the /opt/homebrew prefix. brew itself still runs on
  # Intel, so Intel is pinned to the last installer commit supporting it, which
  # already knows macOS 27 and still checks out the latest brew tag.
  $homebrew_install_commit = '0f5b7666a65fc2d1a2615549f02771353c250f9a'

  # The layout comes from the homebrew fact, so that site manifests reading it
  # agree with this class.
  unless $facts['homebrew'] {
    fail('The homebrew fact is missing: is pluginsync enabled?')
  }
  $brew_root = $facts['homebrew']['prefix']
  $inst_dir  = $facts['homebrew']['repository']
  $brew      = $facts['homebrew']['brew']

  # A repository apart from the prefix (Intel) is managed, and brew linked
  # from it.
  $link_bin           = $inst_dir != $brew_root
  $brew_folders_extra = $link_bin ? { true => [$inst_dir], default => [] }

  if $brew_root == '/opt/homebrew' {
    $homebrew_install_url = 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'

    # Homebrew owns its prefix: created here, or the installer needs sudo to
    # create it. Recent macOS ship /opt, older ones may not, and a file
    # resource does not create parents.
    unless defined(File['/opt']) {
      file { '/opt':
        ensure => directory,
      }
    }
    unless defined(File[$brew_root]) {
      file { $brew_root:
        ensure => directory,
        owner  => $homebrew::user,
        group  => $homebrew::group,
      }
    }
    File[$brew_root] -> Exec['install-homebrew']
  } else {
    $homebrew_install_url = "https://raw.githubusercontent.com/Homebrew/install/${homebrew_install_commit}/install.sh"
  }

  $brew_sys_folders = [
    "${brew_root}/bin",
    "${brew_root}/etc",
    "${brew_root}/Frameworks",
    "${brew_root}/include",
    "${brew_root}/lib",
    "${brew_root}/lib/pkgconfig",
    "${brew_root}/var",
  ]

  $brew_sys_folders.each |String $brew_sys_folder| {
    unless defined(File[$brew_sys_folder]) {
      file { $brew_sys_folder:
        ensure => directory,
        owner  => $homebrew::user,
        group  => $homebrew::group,
      }
    }
  }

  $brew_sys_chmod_folders = [
    "${brew_root}/bin",
    "${brew_root}/include",
    "${brew_root}/lib",
    "${brew_root}/etc",
    "${brew_root}/Frameworks",
    "${brew_root}/var",
  ]

  $brew_sys_chmod_folders.each |String $brew_sys_chmod_folder| {
    exec { "brew-chmod-sys-${brew_sys_chmod_folder}":
      command => "/bin/chmod -R 775 ${brew_sys_chmod_folder}",
      unless  => "/usr/bin/stat -f '%OLp' ${brew_sys_chmod_folder} | /usr/bin/grep -w '775'",
      notify  => Exec["set-${brew_sys_chmod_folder}-directory-inherit"],
    }

    exec { "set-${brew_sys_chmod_folder}-directory-inherit":
      command     => "/bin/chmod -R +a 'group:${homebrew::group}:allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit' ${brew_sys_chmod_folder}", # lint:ignore:140chars
      refreshonly => true,
    }
  }

  $brew_folders = flatten(
    $brew_folders_extra,
    [
      "${brew_root}/opt",
      "${brew_root}/Caskroom",
      "${brew_root}/Cellar",
      "${brew_root}/var/homebrew",
      "${brew_root}/share",
      "${brew_root}/share/doc",
      "${brew_root}/share/info",
      "${brew_root}/share/man",
    ],
  )

  file { $brew_folders:
    ensure => directory,
    owner  => $homebrew::user,
    group  => $homebrew::group,
  }

  if $homebrew::multiuser {
    $brew_folders.each |String $brew_folder| {
      exec { "chmod-${brew_folder}":
        command => "/bin/chmod -R 775 ${brew_folder}",
        unless  => "/usr/bin/stat -f '%OLp' '${brew_folder}' | /usr/bin/grep -w '775'",
        notify  => Exec["set-${brew_folder}-directory-inherit"],
      }

      exec { "chown-${brew_folder}":
        command => "/usr/sbin/chown -R :${homebrew::group} ${brew_folder}",
        unless  => "/usr/bin/stat -f '%Sg' '${brew_folder}' | /usr/bin/grep -w '${homebrew::group}'",
      }

      exec { "set-${brew_folder}-directory-inherit":
        command     => "/bin/chmod -R +a 'group:${homebrew::group}:allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit' ${brew_folder}", # lint:ignore:140chars
        refreshonly => true,
      }
    }
  }

  # Run from memory, as Homebrew documents it: a file in /tmp could be
  # replaced by another local user before it runs. && stops on a failed
  # download, where bash -c "$(curl ...)" would run an empty script.
  $homebrew_install_cmd = "script=\$(/usr/bin/curl -fsSL ${homebrew_install_url}) && /usr/bin/env NONINTERACTIVE=1 /bin/bash -c \"\$script\"" # lint:ignore:140chars

  # su hands the command to the brew user's login shell, which may not be
  # sh-compatible: it only gets a quoted string to pass to bash. As an array,
  # the command skips Puppet's own shell.
  exec { 'install-homebrew':
    cwd       => '/tmp',
    command   => ['/usr/bin/su', $homebrew::user, '-c', "/bin/bash -c '${homebrew_install_cmd}'"],
    creates   => $brew,
    logoutput => on_failure,
    timeout   => 0,
  }

  if $link_bin {
    file { $brew:
      ensure => link,
      target => "${inst_dir}/bin/brew",
      owner  => $homebrew::user,
      group  => $homebrew::group,
    }
  }
}
