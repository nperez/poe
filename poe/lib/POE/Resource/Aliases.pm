# $Id$

# Manage the POE::Kernel data structures necessary to keep track of
# session aliases.

package POE::Resources::Aliases;

use vars qw($VERSION);
$VERSION = (qw($Revision$))[1];

# These methods are folded into POE::Kernel;
package POE::Kernel;

use strict;

### The table of session aliases, and the sessions they refer to.

my %kr_aliases;
#  ( $alias => $session_ref,
#    ...,
#  );

my %kr_ses_to_alias;
#  ( $session_ref =>
#    { $alias => $placeholder_value,
#      ...,
#    },
#    ...,
#  );

### End-run leak checking.

sub _data_alias_finalize {
  while (my ($alias, $ses) = each(%kr_aliases)) {
    warn "!!! Leaked alias: $alias = $ses\n";
  }
  while (my ($ses, $alias_rec) = each(%kr_ses_to_alias)) {
    my @aliases = keys(%$alias_rec);
    warn "!!! Leaked alias cross-reference: $ses (@aliases)\n";
  }
}

### Add an alias to a session.

sub _data_alias_add {
  my ($self, $session, $alias) = @_;
  $self->_data_ses_refcount_inc($session);
  $kr_aliases{$alias} = $session;
  $kr_ses_to_alias{$session}->{$alias} = 1;
}

### Remove an alias from a session.

sub _data_alias_remove {
  my ($self, $session, $alias) = @_;
  delete $kr_aliases{$alias};
  delete $kr_ses_to_alias{$session}->{$alias};
  unless (keys %{$kr_ses_to_alias{$session}}) {
    delete $kr_ses_to_alias{$session};
  }
  $self->_data_ses_refcount_dec($session);
}

### Clear all the aliases from a session.

sub _data_alias_clear_session {
  my ($self, $session) = @_;
  return unless exists $kr_ses_to_alias{$session}; # avoid autoviv
  foreach (keys %{$kr_ses_to_alias{$session}}) {
    $self->_data_alias_remove($session, $_);
  }
}

### Resolve an alias.  Just an alias.

sub _data_alias_resolve {
  my ($self, $alias) = @_;
  return undef unless exists $kr_aliases{$alias};
  return $kr_aliases{$alias};
}

### Return a list of aliases for a session.

sub _data_alias_list {
  my ($self, $session) = @_;
  return () unless exists $kr_ses_to_alias{$session};
  return sort keys %{$kr_ses_to_alias{$session}};
}

### Return the number of aliases for a session.

sub _data_alias_count_ses {
  my ($self, $session) = @_;
  return 0 unless exists $kr_ses_to_alias{$session};
  return scalar keys %{$kr_ses_to_alias{$session}};
}

### Return a session's ID in a form suitable for logging.

sub _data_alias_loggable {
  my ($self, $session) = @_;
  confess "internal inconsistency" unless ref($session);
  "session " . $session->ID . " (" .
    ( (exists $kr_ses_to_alias{$session})
      ? join(", ", keys(%{$kr_ses_to_alias{$session}}))
      : $session
    ) . ")"
}

1;

__END__

=head1 NAME

POE::Resources::Aliases - manage session aliases for POE::Kernel

=head1 SYNOPSIS

Used internally by POE::Kernel.  Better documentation will be
forthcoming.

=head1 DESCRIPTION

This module manages session aliases for POE::Kernel.  It is used
internally by POE::Kernel and has no public interface.

=head1 SEE ALSO

See L<POE::Kernel> for documentation on session aliases.

=head1 BUGS

Probably.

=head1 AUTHORS & COPYRIGHTS

Please see L<POE> for more information about authors and contributors.

=cut