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
      before    => Exec['homebrew-xcode-license'],
    }
  }

  # brew refuses every command while the Xcode licence is not accepted, with
  # the same test as here (brew.sh: xcrun, only when a developer directory is
  # selected). Taps, packages and services then fail with secondary errors.
  # This module does not accept the licence on the institution's behalf: it
  # says so, as a warning. Failing instead would skip every later stage when
  # homebrew runs in an early one. Checked at run time, not from a fact, so a
  # licence accepted earlier in the same run (e.g. by the xcode class) counts.
  exec { 'homebrew-xcode-license':
    command   => "/bin/echo 'The Xcode licence is not accepted: brew refuses to run until it is. Declare the xcode class before homebrew, or run: sudo xcodebuild -license accept'", # lint:ignore:140chars
    onlyif    => "/bin/sh -c '/usr/bin/xcode-select -p >/dev/null 2>&1 && /usr/bin/xcrun --find clang 2>&1 | /usr/bin/grep -qi license'", # lint:ignore:140chars
    logoutput => true,
    loglevel  => warning,
  }
}
