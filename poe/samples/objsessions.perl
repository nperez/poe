#!perl -w -I..
# $Id$

use strict;

use POE; # Kernel and Session are always included

#------------------------------------------------------------------------------
# an object that counts for a while, then stops

package Counter;

sub new {
  my ($type, $name) = @_;
  bless { 'name' => $name }, $type;
}

sub _start {
  my ($self, $k, $me) = @_;
  $k->sig('INT', 'sigint');
  $self->{'counter'} = 0;
  print "Session $self->{'name'} started.\n";
  $k->post($me, 'increment');
}

sub _stop {
  my ($self, $k, $me, $from) = @_;
  print "Session $self->{'name'} stopped after $self->{'counter'} loops.\n";
}

sub sigint {
  my ($self, $k, $me, $from, $signal_name) = @_;
  print "$self->{'name'} caught SIG$signal_name from $from\n";
                                        # did not handle the signal
  return 0;
}

sub increment {
  my ($self, $k, $me, $from, $session_name, $counter) = @_;
  $self->{'counter'}++;
  print "Session $self->{'name'}, iteration $self->{'counter'}.\n";
  if ($self->{'counter'} < 5) {
    $k->post($me, 'increment');
  }
  else {
    # no more states; nothing left to do.  session stops.
  }
}

#------------------------------------------------------------------------------

package main;

my $kernel = new POE::Kernel();

foreach my $session_name (
  qw(one two three four five six seven eight nine ten)
) {
  new POE::Session( $kernel,
                    new Counter($session_name),
                    [ qw(_start _stop increment sigint) ]
                  );
}

$kernel->run();

exit;
