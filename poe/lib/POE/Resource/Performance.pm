# $Id$

# Data and methods to manage performance metrics, allowing clients to
# look at how much work their POE server is performing.
# None of this stuff will activate unless TRACE_PERFORMANCE or
# TRACE_PROFILE are enabled.

package POE::Resources::Performance;

use vars qw($VERSION);
$VERSION = do {my@r=(q$Revision$=~/\d+/g);sprintf"%d."."%04d"x$#r,@r};

# We fold all this stuff back into POE::Kernel
package POE::Kernel;

use strict;

# We keep a number of metrics (idle time, user time, etc).
# Every tick (by default 30secs), we compute the rolling average
# of those metrics. The rolling average is computed based on
# the number of readings specified in $_perf_window_size.

my $_perf_metrics     = []; # the data itself
my $_perf_interval    = 30; # how frequently we take readings
my $_perf_window_size = 4;  # how many readings we average across
my $_perf_wpos        = 0;  # where to currrently write metrics (circ. buffer)
my $_perf_rpos        = 0;  # where to currrently write metrics (circ. buffer)
my %average;

# This is for collecting event frequencies if TRACE_PROFILE is
# enabled.
my %profile;

sub _data_perf_initialize {
    my ($self) = @_;
    $self->_data_perf_reset;
    $self->_data_ev_enqueue(
      $self, $self, EN_PERF, ET_PERF, [ ],
      __FILE__, __LINE__, time() + $_perf_interval
    );
}

sub _data_perf_finalize {
    my ($self) = @_;
    $self->_data_perf_tick();

    if (TRACE_PERFORMANCE) {
      POE::Kernel::_warn('<pr> ,----- Performance Data ' , ('-' x 50), ",\n");
      foreach (sort keys %average) {
          next if /epoch/;
          POE::Kernel::_warn(
            sprintf "<pr> | %60.60s %9.1f  |\n", $_, $average{$_}
          );
      }

      unless (keys %average) {
          POE::Kernel::_warn '<pr> `', ('-' x 73), "'\n";
          return;
      }

      # Division by zero sucks.
      $average{blocked}     ||= 0;
      $average{user_events} ||= 1;

      POE::Kernel::_warn(
        '<pr> +----- Derived Performance Metrics ', ('-' x 39), "+\n",
        sprintf(
          "<pr> | %60.60s %9.1f%% |\n",
          'idle', 100 * $average{avg_idle_seconds} / $average{interval}
        ),
        sprintf(
          "<pr> | %60.60s %9.1f%% |\n",
          'user', 100 * $average{avg_user_seconds} / $average{interval}
        ),
        sprintf(
          "<pr> | %60.60s %9.1f%% |\n",
          'blocked', 100 * $average{avg_blocked} / $average{user_events}
        ),
        sprintf(
          "<pr> | %60.60s %9.1f  |\n",
          'user load', $average{avg_user_events} / $average{interval}
        ),
        '<pr> `', ('-' x 73), "'\n"
      );
    }

    if (TRACE_PROFILE) {
      perf_show_profile();
    }
}

sub _data_perf_add {
    my ($self, $key, $count) = @_;
    $_perf_metrics->[$_perf_wpos] ||= {};
    $_perf_metrics->[$_perf_wpos]->{$key} += $count;
}

sub _data_perf_tick {
    my ($self) = @_;

    my $pos = $_perf_rpos;
    $_perf_wpos = ($_perf_wpos+1) % $_perf_window_size;
    if ($_perf_wpos == $_perf_rpos) {
	$_perf_rpos = ($_perf_rpos+1) % $_perf_window_size;
    }

    my $count = 0;
    %average = ();
    my $epoch = 0;
    while ($count < $_perf_window_size && $_perf_metrics->[$pos]->{epoch}) {
 	$epoch = $_perf_metrics->[$pos]->{epoch} unless $epoch;
	while (my ($k,$v) = each %{$_perf_metrics->[$pos]}) {
	    next if $k eq 'epoch';
	    $average{$k} += $v;
	}
	$count++;
	$pos = ($pos+1) % $_perf_window_size;
    }

    if ($count) {
        my $now = time();
 	map { $average{"avg_$_"} = $average{$_} / $count } keys %average;
 	$average{total_duration} = $now - $epoch;
 	$average{interval}       = ($now - $epoch) / $count;
    }

    $self->_data_perf_reset;
    $self->_data_ev_enqueue(
      $self, $self, EN_PERF, ET_PERF, [ ],
      __FILE__, __LINE__, time() + $_perf_interval
    ) if $self->_data_ses_count() > 1;
}

sub _data_perf_reset {
    $_perf_metrics->[$_perf_wpos] = {
      epoch => time,
      idle_seconds => 0,
      user_seconds => 0,
      kern_seconds => 0,
      blocked_seconds => 0,
    };
}

# Profile this event.

sub _perf_profile {
  my ($self, $event) = @_;
  $profile{$event}++;
}

# Public routines...

sub perf_getdata {
    return %average;
}

sub perf_show_profile {
  POE::Kernel::_warn('<pr> ,----- Event Profile ' , ('-' x 53), ",\n");
  foreach (sort keys %profile) {
    POE::Kernel::_warn(
      sprintf "<pr> | %60.60s %9d  |\n", $_, $profile{$_}
    );
  }
  POE::Kernel::_warn '<pr> `', ('-' x 73), "'\n";
}

1;
__END__

=head1 NAME

POE::Resource::Performance -- Performance metrics for POE::Kernel

=head1 SYNOPSIS

  my %stats = $poe_kernel->perf_getdata;
  printf "Idle = %3.2f\n", 100*$stats{avg_idle_seconds}/$stats{interval};

=head1 DESCRIPTION

This module tracks POE::Kernel's performance metrics and provides
accessors to them.  To enable this monitoring, the TRACE_PERFORMANCE
flag must be true.  Otherwise no statistics will be gathered.

The performance counters are totalled every 30 seconds and a rolling
average is maintained for the last two minutes worth of data. At any
time the data can be retrieved using the perf_getdata() method of the
POE::Kernel. On conclusion of the program, the statistics will be
printed out by the POE::Kernel.

The time() function is used to gather performance metrics.  If
Time::HiRes is available, it will be used automatically.  Otherwise
time is measured in whole seconds, and the resulting rounding errors
will make the statistics useless.

The performance metrics were added to POE 0.28.  They are still
considered highly experimental.  Please be advised that the figures
are quite likely wrong.  They may in fact be useless.  The reader is
invited to investigate and improve the module's methods.

=head1 METRICS

The following fields are members of the hash returned by perf_getdata.

For each of the counters, there will a corresponding entry prefixed
'avg_' which is the rolling average of that counter.

=over 4

=item B<blocked>

The number of events (both user and kernel) which were delayed due to
a user event running for too long. On conclusion of the program, POE
will display the blocked count.  By comparing this value with
B<user_events>.  This value should be as low as possible to ensure
minimal latency.

In practice, this number is very close to (or even above)
B<user_events>.  Events that are even the slightest bit late count as
"blocked".  See B<blocked_seconds>.

TODO - Perhaps this should only count events that were dispatched more
than 1/100 second or so late?  Even then, the hundredths add up in
long running programs.

=item B<blocked_seconds>

The total number of seconds that handlers waited for other events or
POE before being dispatched.  This value is not as useful as its
average version, B<avg_blocked_seconds>, which tells you the average
latency between an event's due time and its dispatch time.

=item B<idle_seconds>

The number of seconds which were spent doing nothing at all (typically
waiting for a select/poll event or a timeout to trigger).

=item B<interval>

The average interval over which the counters are recorded. This will
typically be 30 seconds, however it can be more if there are
long-running user events which prevent the performance monitoring from
running on time, and it may be less if the program finishes in under
30 seconds. Often the very last measurement taken before the program
exits will use a duration less than 30 seconds and this will cause the
average to be lower.

=item B<total_duration>

The counters are averaged over a 2 minute duration, but for the same
reasons as described in the B<interval> section, this time may vary.
This value contains the total time over which the average was
calculated.

=item B<user_events>

The number of events which are performed for the user code. I.e. this
does not include POE's own internal events such as polling for child
processes. At program termination, a user_load value is computed
showing the average number of user events which are running per
second. A very active web server would have a high load value. The
higher the user load, the more important it is that you have small
B<blocked> and B<blocked_seconds> values.

=item B<user_seconds>

The time which was spent running user events. The user_seconds +
idle_seconds will typically add up to total_duration. Any difference
comes down to time spent in the POE kernel (which should be minimal)
and rounding errors.

=back

=head1 SEE ALSO

See L<POE::Kernel>.

=head1 BUGS

Probably.

=head1 AUTHORS & COPYRIGHTS

Contributed by Nick Williams <Nick.Williams@morganstanley.com>.

Please see L<POE> for more information about authors and contributors.

=cut