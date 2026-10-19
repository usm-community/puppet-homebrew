class homebrew::compiler {

  if $facts['has_compiler'] {
    notice('Compiler already present; skipping command line tools installation.')
  } elsif $homebrew::command_line_tools_package and $homebrew::command_line_tools_source {
    notice('Installing Command Line Tools from DMG.')

    package { $homebrew::command_line_tools_package:
      ensure   => present,
      provider => pkgdmg,
      source   => $homebrew::command_line_tools_source,
    }
  } else {
    notice('Installing Command Line Tools via softwareupdate.')

    # As in Homebrew's installer: the placeholder makes softwareupdate list
    # the Command Line Tools, and is removed however the script ends. The
    # label is the newest Command Line Tools, in both `softwareupdate -l`
    # formats. A literal heredoc needs no escaping.
    $install_clt = @(SCRIPT)
      placeholder=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      trap '/bin/rm -f "${placeholder}"' EXIT
      /usr/bin/touch "${placeholder}"
      label=$(/usr/sbin/softwareupdate -l |
        /usr/bin/grep -B 1 -E 'Command Line Tools' |
        /usr/bin/awk -F'*' '/^ *\*/ {print $2}' |
        /usr/bin/sed -e 's/^ *Label: //' -e 's/^ *//' |
        /usr/bin/sort -V |
        /usr/bin/tail -n 1)
      if [ -z "${label}" ]; then
        echo 'softwareupdate lists no Command Line Tools' >&2
        exit 1
      fi
      /usr/sbin/softwareupdate -i "${label}"
      | SCRIPT

    exec { 'install-clt':
      command   => $install_clt,
      provider  => shell,
      unless    => '/bin/test -f /Library/Developer/CommandLineTools/usr/bin/cc',
      timeout   => 0,
      logoutput => on_failure,
    }
  }
}
