# $Id$

# Plain Perl signal handling is something shared by several event
# loops.  The invariant code has moved out here so that each loop may
# use it without reinventing it.  This will save maintenance and
# shrink the distribution.  Yay!

package POE::Loop::PerlSignals;

use strict;

use vars qw($VERSION);
$VERSION = do {my@r=(q$Revision$=~/\d+/g);sprintf"%d."."%04d"x$#r,@r};

# Everything plugs into POE::Kernel.
package POE::Kernel;

use strict;
use POE::Kernel;

#------------------------------------------------------------------------------
# Signal handlers/callbacks.

sub _loop_signal_handler_generic {
  if (TRACE_SIGNALS) {
    POE::Kernel::_warn "<sg> Enqueuing generic SIG$_[0] event";
  }

  $poe_kernel->_data_ev_enqueue(
    $poe_kernel, $poe_kernel, EN_SIGNAL, ET_SIGNAL, [ $_[0] ],
    __FILE__, __LINE__, undef, time()
  );
  $SIG{$_[0]} = \&_loop_signal_handler_generic;
}

sub _loop_signal_handler_pipe {
  if (TRACE_SIGNALS) {
    POE::Kernel::_warn "<sg> Enqueuing PIPE-like SIG$_[0] event";
  }

  $poe_kernel->_data_ev_enqueue(
    $poe_kernel, $poe_kernel, EN_SIGNAL, ET_SIGNAL, [ $_[0] ],
    __FILE__, __LINE__, undef, time()
  );
  $SIG{$_[0]} = \&_loop_signal_handler_pipe;
}

#------------------------------------------------------------------------------
# Signal handler maintenance functions.

sub loop_watch_signal {
  my ($self, $signal) = @_;

  # Child process has stopped.
  if ($signal eq 'CHLD' or $signal eq 'CLD') {

    # Begin constant polling loop.  Only start it on CHLD or on CLD if
    # CHLD doesn't exist.
    $SIG{$signal} = 'DEFAULT';
    $self->_data_ev_enqueue(
      $self, $self, EN_SCPOLL, ET_SCPOLL, [ ],
      __FILE__, __LINE__, undef, time() + 1
    ) if $signal eq 'CHLD' or not exists $SIG{CHLD};

    return;
  }

  # Broken pipe.
  if ($signal eq 'PIPE') {
    $SIG{$signal} = \&_loop_signal_handler_pipe;
    return;
  }

  # Everything else.
  $SIG{$signal} = \&_loop_signal_handler_generic;
}

sub loop_ignore_signal {
  my ($self, $signal) = @_;
  $SIG{$signal} = "DEFAULT";
}

1;

__END__

=head1 NAME

POE::Loop::PerlSignals - plain Perl signal handlers used by many loops

=head1 SYNOPSIS

See L<POE::Loop>.

=head1 DESCRIPTION

This class is an implementation of the signal handling functions
defined by the abstract POE::Loop interface.  It follows POE::Loop's
public interface for signal handling exactly.  Therefore, please see
L<POE::Loop> for its documentation.

=head1 SEE ALSO

L<POE>, L<POE::Loop>

=head1 AUTHORS & LICENSING

Please see L<POE> for more information about authors, contributors,
and POE's licensing.

=cut
