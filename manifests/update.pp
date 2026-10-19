class homebrew::update {
  $brew   = $facts['homebrew']['brew']
  $marker = "${facts['homebrew']['prefix']}/var/homebrew/.puppet-last-brew-update"

  # $update_frequency is expressed in seconds; find -mmin works in minutes.
  $frequency_minutes = $homebrew::update_frequency / 60

  # Refresh every git tap (official + third-party) at most once per interval.
  # The marker is only touched on success (&&), so a transient failure leaves it
  # untouched and is retried on the next run; `|| true` swallows that failure so
  # a network blip is not reported as a failed Puppet resource. Between intervals
  # the `unless` guard skips the exec, so the resource stays unchanged (no churn).
  # su keeps Puppet's working directory, which brew refuses if its user cannot
  # read it. As in homebrew::install, the login shell only passes the command
  # to bash.
  exec { 'homebrew-update':
    cwd       => '/tmp',
    command   => ['/usr/bin/su', $homebrew::user, '-c', "/bin/bash -c '(${brew} update && /usr/bin/touch ${marker}) || true'"],
    unless    => "/usr/bin/find ${marker} -mmin -${frequency_minutes} | /usr/bin/grep -q .",
    logoutput => on_failure,
    timeout   => 300,
  }
}
