# $Id$

package POE::Session;

use strict;
use Carp;
use POSIX qw(ENOSYS);

use POE::Preprocessor;

enum SE_NAMESPACE SE_OPTIONS SE_STATES

# I had made these constant subs, but you can't use constant subs as
# hash keys, so they're POE::Preprocessor constants.  Blargh!

const CREATE_ARGS     'args'
const CREATE_OPTIONS  'options'
const CREATE_INLINES  'inline_states'
const CREATE_PACKAGES 'package_states'
const CREATE_OBJECTS  'object_states'
const CREATE_HEAP     'heap'

const OPT_TRACE   'trace'
const OPT_DEBUG   'debug'
const OPT_DEFAULT 'default'

const EN_START   '_start'
const EN_DEFAULT '_default'

# Define some debugging flags for subsystems, unless someone already
# has defined them.
BEGIN {
  defined &DEB_DESTROY or eval 'sub DEB_DESTROY () { 0 }';
}

#------------------------------------------------------------------------------

macro make_session {
  my $self =
    bless [ { }, # SE_NAMESPACE
            { }, # SE_OPTIONS
            { }, # SE_STATES
          ], $type;
}

macro validate_kernel {
  croak "$type requires a working Kernel"
    unless defined $POE::Kernel::poe_kernel;
}

macro validate_state {
  carp "redefining state($name) for session(", {% fetch_id $self %}, ")"
    if ( (exists $self->[SE_OPTIONS]->{OPT_DEBUG}) &&
         (exists $self->[SE_STATES]->{$name})
       );
}

macro fetch_id (<whence>) {
  $POE::Kernel::poe_kernel->ID_session_to_id(<whence>)
}

macro verify_start_state {
  # Verfiy that the session has a special start state, otherwise how
  # do we know what to do?  Don't even bother registering the session
  # if the start state doesn't exist.

  if (exists $self->[SE_STATES]->{EN_START}) {
    $POE::Kernel::poe_kernel->session_alloc($self, @args);
  }
  else {
    carp "discarding session ", {% fetch_id $self %}, " - no '_start' state";
    $self = undef;
  }
}

# MACROS END <-- search tag for editing

#------------------------------------------------------------------------------
# Export constants into calling packages.  This is evil; perhaps
# EXPORT_OK instead?

sub OBJECT  () {  0 }
sub SESSION () {  1 }
sub KERNEL  () {  2 }
sub HEAP    () {  3 }
sub STATE   () {  4 }
sub SENDER  () {  5 }
sub ARG0    () {  6 }
sub ARG1    () {  7 }
sub ARG2    () {  8 }
sub ARG3    () {  9 }
sub ARG4    () { 10 }
sub ARG5    () { 11 }
sub ARG6    () { 12 }
sub ARG7    () { 13 }
sub ARG8    () { 14 }
sub ARG9    () { 15 }

use Exporter;
@POE::Session::ISA = qw(Exporter);
@POE::Session::EXPORT = qw( OBJECT SESSION KERNEL HEAP STATE SENDER
                            ARG0 ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8 ARG9
                          );

#------------------------------------------------------------------------------
# Classic style constructor.  This is unofficially depreciated in
# favor of the create() constructor.  Its DWIM nature does things
# people don't mean, so create() is a little more explicit.

sub new {
  my ($type, @states) = @_;

  my @args;

  croak "sessions no longer require a kernel reference as the first parameter"
    if ((@states > 1) && (ref($states[0]) eq 'POE::Kernel'));

  {% validate_kernel %}
  {% make_session %}

  # Scan all arguments.  It mainly expects them to be in pairs, except
  # for some, uh, exceptions.

  while (@states) {

    # If the first of a hypothetical pair of arguments is an array
    # reference, then this arrayref is the _start state's arguments.
    # Pull them out and look for another pair.

    if (ref($states[0]) eq 'ARRAY') {
      if (@args) {
        croak "$type must only have one block of arguments";
      }
      push @args, @{$states[0]};
      shift @states;
      next;
    }

    # If there is a pair of arguments (or more), then we can continue.
    # Otherwise this is done.

    if (@states >= 2) {

      # Pull the argument pair off the constructor parameters.

      my ($first, $second) = splice(@states, 0, 2);

      # Check for common problems.

      unless ((defined $first) && (length $first)) {
        carp "depreciated: using an undefined state name";
      }

      if (ref($first) eq 'CODE') {
        croak "using a code reference as an state name is not allowed";
      }

      # Try to determine what sort of state it is.  A lot of WIM is D
      # here.  It was nifty at the time, but it's gotten a little
      # scary as POE has evolved.

      # The first parameter has no blessing, so it's either a plain
      # inline state or a package state.

      if (ref($first) eq '') {

        # The second parameter is a coderef, so it's a plain old
        # inline state.

        if (ref($second) eq 'CODE') {
          $self->register_state($first, $second);
          next;
        }

        # If the second parameter in the pair is a list reference,
        # then this is a package state invocation.  Explode the list
        # reference into separate state registrations.  Each state is
        # a package method with the same name.

        elsif (ref($second) eq 'ARRAY') {
          foreach my $method (@$second) {
            $self->register_state($method, $first, $method);
          }

          next;
        }

        # If the second parameter in the pair is a hash reference,
        # then this is a mapped package state invocation.  Explode the
        # hash reference into separate state registrations.  Each
        # state is mapped to a package method with a separate
        # (although not guaranteed to be different) name.

        elsif (ref($second) eq 'HASH') {
          while (my ($first_name, $method_name) = each %$second) {
            $self->register_state($first_name, $first, $method_name);
          }
          next;
        }

        # Something unexpected happened.

        else {
          croak( "can't determine what you're doing with '$first'; ",
                 "perhaps you should use POE::Session->create"
               );
        }
      }

      # Otherwise the first parameter is a blessed something, and
      # these will be object states.  The second parameter is a plain
      # scalar of some sort, so we'll register the state directly.

      if (ref($second) eq '') {
        $self->register_state($second, $first, $second);
        next;
      }

      # The second parameter is a list reference; we'll explode it
      # into several state registrations, each mapping the state name
      # to a similarly named object method.

      if (ref($second) eq 'ARRAY') {
        foreach my $method (@$second) {
          $self->register_state($method, $first, $method);
        }
        next;
      }

      # The second parameter is a hash reference; we'll explode it
      # into several aliased state registrations, each mapping a state
      # name to a separately (though not guaranteed to be differently)
      # named object method.

      if (ref($second) eq 'HASH') {
        while (my ($first_name, $method_name) = each %$second) {
          $self->register_state($first_name, $first, $method_name);
        }
        next;
      }

      # Something unexpected happened.

      croak( "can't determine what you're doing with '$second'; ",
             "perhaps you should use POE::Session->create"
           );
    }

    # There are fewer than 2 parameters left.

    else {
      last;
    }
  }

  # If any parameters are left, then there's a syntax error in the
  # constructor parameter list.

  if (@states) {
    croak "odd number of parameters in POE::Session->new call";
  }

  {% verify_start_state %}

  $self;
}

#------------------------------------------------------------------------------
# New style constructor.  This uses less DWIM and more DWIS, and it's
# more comfortable for some folks; especially the ones who don't quite
# know WTM.

sub create {
  my ($type, @params) = @_;
  my @args;

  # We treat the parameter list strictly as a hash.  Rather than dying
  # here with a Perl error, we'll catch it and blame it on the user.

  if (@params & 1) {
    croak "odd number of states/handlers (missing one or the other?)";
  }
  my %params = @params;

  {% validate_kernel %}
  {% make_session %}

  # Process _start arguments.  We try to do the right things with what
  # we're given.  If the arguments are a list reference, map its items
  # to ARG0..ARGn; otherwise make whatever the heck it is be ARG0.

  if (exists $params{CREATE_ARGS}) {
    if (ref($params{CREATE_ARGS}) eq 'ARRAY') {
      push @args, @{$params{CREATE_ARGS}};
    }
    else {
      push @args, $params{CREATE_ARGS};
    }
    delete $params{CREATE_ARGS};
  }

  # Process session options here.  Several options may be set.

  if (exists $params{CREATE_OPTIONS}) {
    if (ref($params{CREATE_OPTIONS}) eq 'HASH') {
      $self->[SE_OPTIONS] = $params{CREATE_OPTIONS};
    }
    else {
      croak "options for $type constructor is expected to be a HASH reference";
    }
    delete $params{CREATE_OPTIONS};
  }

  # Get down to the business of defining states.

  while (my ($param_name, $param_value) = each %params) {

    # Inline states are expected to be state-name/coderef pairs.

    if ($param_name eq CREATE_INLINES) {
      croak "$param_name does not refer to a hash"
        unless (ref($param_value) eq 'HASH');

      while (my ($state, $handler) = each(%$param_value)) {
        croak "inline state '$state' needs a CODE reference"
          unless (ref($handler) eq 'CODE');
        $self->register_state($state, $handler);
      }
    }

    # Package states are expected to be package-name/list-or-hashref
    # pairs.  If the second part of the pair is a listref, then the
    # package methods are expected to be named after the states
    # they'll handle.  If it's a hashref, then the keys are state
    # names and the values are package methods that implement them.

    elsif ($param_name eq CREATE_PACKAGES) {
      croak "$param_name does not refer to an array"
        unless (ref($param_value) eq 'ARRAY');
      croak "the array for $param_name has an odd number of elements"
        if (@$param_value & 1);

      while (my ($package, $handlers) = splice(@$param_value, 0, 2)) {

        # -><- What do we do if the package name has some sort of
        # blessing?  Do we use the blessed thingy's package, or do we
        # maybe complain because the user might have wanted to make
        # object states instead?

        # An array of handlers.  The array's items are passed through
        # as both state names and package method names.

        if (ref($handlers) eq 'ARRAY') {
          foreach my $method (@$handlers) {
            $self->register_state($method, $package, $method);
          }
        }

        # A hash of handlers.  Hash keys are state names; values are
        # package methods to implement them.

        elsif (ref($handlers) eq 'HASH') {
          while (my ($state, $method) = each %$handlers) {
            $self->register_state($state, $package, $method);
          }
        }

        else {
          croak "states for '$package' needs to be a hash or array ref";
        }
      }
    }

    # Object states are expected to be object-reference/
    # list-or-hashref pairs.  They must be passed to &create in a list
    # reference instead of a hash reference because making object
    # references into hash keys loses their blessings.

    elsif ($param_name eq CREATE_OBJECTS) {
      croak "$param_name does not refer to an array"
        unless (ref($param_value) eq 'ARRAY');
      croak "the array for $param_name has an odd number of elements"
        if (@$param_value & 1);

      while (@$param_value) {
        my ($object, $handlers) = splice @$param_value => 0, 2;

        # Verify that the object is an object.  This may catch simple
        # mistakes; or it may be overkill since it already checks that
        # $param_value is a listref.

        carp "'$object' is not an object" unless ref($object);

        # An array of handlers.  The array's items are passed through
        # as both state names and object method names.

        if (ref($handlers) eq 'ARRAY') {
          foreach my $method (@$handlers) {
            $self->register_state($method, $object, $method);
          }
        }

        # A hash of handlers.  Hash keys are state names; values are
        # package methods to implement them.

        elsif (ref($handlers) eq 'HASH') {
          while (my ($state, $method) = each %$handlers) {
            $self->register_state($state, $object, $method);
          }
        }

        else {
          croak "states for '$object' needs to be a hash or array ref";
        }

      }
    }

    # Import an external heap.  This is a convenience, since it
    # eliminates the need to connect _start options to heap values.

    elsif ($param_name eq CREATE_HEAP) {
      $self->[SE_NAMESPACE] = $param_value;
    }

    else {
      croak "unknown $type parameter: $param_name";
    }
  }

  {% verify_start_state %}

  $self;
}

#------------------------------------------------------------------------------

sub DESTROY {
  my $self = shift;

  # Session's data structures are destroyed through Perl's usual
  # garbage collection.  DEB_DESTROY here just shows what's in the
  # session before the destruction finishes.

  DEB_DESTROY and do {
    print "----- Session $self Leak Check -----\n";
    print "-- Namespace (HEAP):\n";
    foreach (sort keys (%{$self->[SE_NAMESPACE]})) {
      print "   $_ = ", $self->[SE_NAMESPACE]->{$_}, "\n";
    }
    print "-- Options:\n";
    foreach (sort keys (%{$self->[SE_OPTIONS]})) {
      print "   $_ = ", $self->[SE_OPTIONS]->{$_}, "\n";
    }
    print "-- States:\n";
    foreach (sort keys (%{$self->[SE_STATES]})) {
      print "   $_ = ", $self->[SE_STATES]->{$_}, "\n";
    }
  };
}

#------------------------------------------------------------------------------

sub _invoke_state {
  my ($self, $source_session, $state, $etc, $file, $line) = @_;

  # Trace the state invocation if tracing is enabled.

  if (exists($self->[SE_OPTIONS]->{OPT_TRACE})) {
    warn {% fetch_id $self %}, " -> $state\n";
  }

  # The desired destination state doesn't exist in this session.
  # Attempt to redirect the state transition to _default.

  unless (exists $self->[SE_STATES]->{$state}) {

    # There's no _default either; redirection's not happening today.
    # Drop the state transition event on the floor, and optionally
    # make some noise about it.

    unless (exists $self->[SE_STATES]->{EN_DEFAULT}) {
      $! = ENOSYS;
      if (exists $self->[SE_OPTIONS]->{OPT_DEFAULT}) {
        warn( "a '$state' state was sent from $file at $line to session ",
              {% fetch_id $self %}, ", but session ", {% fetch_id $self %},
              " has neither that state nor a _default state to handle it\n"
            );
      }
      return undef;
    }

    # If we get this far, then there's a _default state to redirect
    # the transition to.  Trace the redirection.

    if (exists($self->[SE_OPTIONS]->{OPT_TRACE})) {
      warn {% fetch_id $self %}, " -> $state redirected to _default\n";
    }

    # Transmogrify the original state transition into a corresponding
    # _default invocation.

    $etc   = [ $state, $etc ];
    $state = EN_DEFAULT;
  }

  # If we get this far, then the state can be invoked.  So invoke it
  # already!

  # Inline states are invoked this way.

  if (ref($self->[SE_STATES]->{$state}) eq 'CODE') {
    return &{$self->[SE_STATES]->{$state}}
      ( undef,                          # object
        $self,                          # session
        $POE::Kernel::poe_kernel,       # kernel
        $self->[SE_NAMESPACE],          # heap
        $state,                         # state
        $source_session,                # sender
        @$etc                           # args
      );
  }

  # Package and object states are invoked this way.

  my ($object, $method) = @{$self->[SE_STATES]->{$state}};
  return
    $object->$method                    # package/object (implied)
      ( $self,                          # session
        $POE::Kernel::poe_kernel,       # kernel
        $self->[SE_NAMESPACE],          # heap
        $state,                         # state
        $source_session,                # sender
        @$etc                           # args
      );
}

#------------------------------------------------------------------------------
# Add, remove or replace states in the session.

sub register_state {
  my ($self, $name, $handler, $method) = @_;
  $method = $name unless defined $method;

  # There is a handler, so try to define the state.  This replaces an
  # existing state.

  if ($handler) {

    # Coderef handlers are inline states.

    if (ref($handler) eq 'CODE') {
      {% validate_state %}
      $self->[SE_STATES]->{$name} = $handler;
    }

    # Non-coderef handlers may be package or object states.  See if
    # the method belongs to the handler.

    elsif ($handler->can($method)) {
      {% validate_state %}
      $self->[SE_STATES]->{$name} = [ $handler, $method ];
    }

    # Something's wrong.  This code also seems wrong, since
    # ref($handler) can't be 'CODE'.

    else {
      if ( (ref($handler) eq 'CODE') and
           exists($self->[SE_OPTIONS]->{OPT_TRACE})
         ) {
        carp( {% fetch_id $self %},
              " : state($name) is not a proper ref - not registered"
            )
      }
      else {
        croak "object $handler does not have a '$method' method"
          unless ($handler->can($method));
      }
    }
  }

  # No handler.  Delete the state!

  else {
    delete $self->[SE_STATES]->{$name};
  }
}

#------------------------------------------------------------------------------
# Return the session's ID.  This is a thunk into POE::Kernel, where
# the session ID really lies.

sub ID {
  {% fetch_id shift %}
}

#------------------------------------------------------------------------------
# Set or fetch session options.

sub option {
  my $self = shift;
  my %return_values;

  # Options are set in pairs.

  while (@_ >= 2) {
    my ($flag, $value) = splice(@_, 0, 2);
    $flag = lc($flag);

    # If the value is defined, then set the option.

    if (defined $value) {

      # Change some handy values into boolean representations.  This
      # clobbers the user's original values for the sake of DWIM-ism.

      ($value = 1) if ($value =~ /^(on|yes|true)$/i);
      ($value = 0) if ($value =~ /^(no|off|false)$/i);

      $return_values{$flag} = $self->[SE_OPTIONS]->{$flag};
      $self->[SE_OPTIONS]->{$flag} = $value;
    }

    # Remove the option if the value is undefined.

    else {
      $return_values{$flag} = delete $self->[SE_OPTIONS]->{$flag};
    }
  }

  # If only one option is left, then there's no value to set, so we
  # fetch its value.

  if (@_) {
    my $flag = lc(shift);
    $return_values{$flag} =
      ( exists($self->[SE_OPTIONS]->{$flag})
        ? $self->[SE_OPTIONS]->{$flag}
        : undef
      );
  }

  # If only one option was set or fetched, then return it as a scalar.
  # Otherwise return it as a hash of option names and values.

  my @return_keys = keys(%return_values);
  if (@return_keys == 1) {
    return $return_values{$return_keys[0]};
  }
  else {
    return \%return_values;
  }
}

# Fetch the session's heap.  In rare cases, libraries may need to
# break encapsulation this way, probably also using
# $kernel->get_current_session as an accessory to the crime.

sub get_heap {
  my $self = shift;
  return $self->[SE_NAMESPACE];
}

#------------------------------------------------------------------------------
# Create an anonymous sub that, when called, posts an event back to a
# session.  This is highly experimental code to support Tk widgets and
# maybe Event callbacks.  There's no guarantee that this code works
# yet, nor is there one that it'll be here in the next version.

# This maps postback references (stringified; blessing, and thus
# refcount, removed) to parent session IDs.  Members are set when
# postbacks are created, and postbacks' DESTROY methods use it to
# perform the necessary cleanup when they go away.  Thanks to njt for
# steering me right on this one.

my %postback_parent_id;

# I assume that when the postback owner loses all reference to it,
# they are done posting things back to us.  That's when the postback's
# DESTROY is triggered, and referential integrity is maintained.

sub POE::Session::Postback::DESTROY {
  my $self = shift;
  my $parent_id = delete $postback_parent_id{$self};
  $POE::Kernel::poe_kernel->refcount_decrement( $parent_id, 'postback' );
}

# Create a postback closure, maintaining referential integrity in the
# process.  The next step is to give it to something that expects to
# be handed a callback.

sub postback {
  my ($self, $event, @etc) = @_;
  my $id = {% fetch_id $self %};

  my $postback = bless
    sub {
      $POE::Kernel::poe_kernel->post( $id, $event, [ @etc ], [ @_ ] );
      0;
    }, 'POE::Session::Postback';

  $postback_parent_id{$postback} = $id;
  $POE::Kernel::poe_kernel->refcount_increment( $id, 'postback' );

  $postback;
}

###############################################################################
1;

__END__

=head1 NAME

POE::Session - a cooperatively threaded abstract state machine

=head1 SYNOPSIS

  # Import POE::Session constants.
  use POE::Session;

  # The older, more DWIMmy constructor.
  POE::Session->new(

    # Inline or coderef states.
    state_one => \&coderef_one,
    state_two => sub { ... },

    # Plain object and package states.
    $object_one  => [ 'state_three', 'state_four',  'state_five'  ],
    $package_one => [ 'state_six',   'state_seven', 'state_eight' ],

    # Mapped object and package states.
    $object_two  => { state_nine => 'method_nine', ... },
    $package_two => { state_ten  => 'method_ten', ... },

    # Parameters for the session's initial state.
    \@start_args,
  );

  # The newer, more explicit and safer constructor.
  POE::Session->create(

    # Inline or coderef states.
    inline_states =>
      { state_one => \&coderef_one,
        state_two => sub { ... },
      },

    # Plain and mapped object states.
    object_states =>
    [ $object_one => [ 'state_three', 'state_four', 'state_five' ],
      $object_two => { state_nine => 'method_nine' },
    ],

    # Plain and mapped package states.
    package_states =>
    [ $package_one => [ 'state_six', 'state_seven', 'state_eight' },
      $package_two => { state_ten => 'method_ten' },
    ],

    # Parameters for the session's initial state.
    args => [ argument_zero, argument_one, ... ],

    # Initial options.  See the option() method.
    options => \%options,

    # Change the session's heap representation.
    heap => [ ],
  );

Other methods:

  # Retrieve a session's unique identifier.
  $session_id = $session->ID;

  # Retrieve a reference to the session's heap.
  $session_heap = $session->get_heap();

  # Set or clear session options.
  $session->option( trace => 1, default => 1 );
  $session->option( trace );

  # Create a postback, then invoke it and pass back additional
  # information.
  $postback_coderef = $session->postback( $state_name, @state_args );
  &{ $postback_coderef }( @additional_args );

=head1 DESCRIPTION

POE::Session combines a runtime context with an event driven state
machine.  Together they implement a simple cooperatively timesliced
thread.

Sessions receive their timeslices as events from POE::Kernel.  Each
event has two fields, a state name and a session identifier.  These
fields describe the code to run and the context to run it in,
respectively.  Events carry several other fields which will be
discussed in the "Predefined Event Fields" section.

States are re-entrant since they are invoked with their runtime
contexts.  Although it's not usually necessary, this re-entrancy
allows a single function to be bound to several different sessions,
under several different state names.

As sessions run, they post new events through the Kernel.  These
events may be for themselves or other sessions, in which case they act
as a form of inter-session communications.  The Kernel can also
generate events based on external conditions such as file activity or
the passage of time.

POE provides some convenient built-in states with special meanings.
They will be covered later on in the "Predefined States" section.

=head1 PUBLIC METHODS

=over 2

=item ID

ID() returns the session instance's unique identifier.  This is a
number that starts with 1 and counts up forever, or until something
causes the number to wrap.  It's theoretically possible that session
IDs may collide after about 4.29 billion sessions have been created.

=item create LOTS_OF_STUFF

create() is the recommended Session constructor.  It binds states to
their corresponding event names, initalizes other parts of the
session, and then fires off its C<_start> state, possibly with some
parameters.

create's parameters look like a hash of name/value pairs, but it's
really just a list.  create() is preferred over the older, more DWIMmy
new() constructor because each kind of parameter is explicitly named.
This makes it easier for maintainers to understand the constructor
call, and it lets the constructor unambiguously recognize and validate
parameters.

=over 2

=item args => LISTREF

The C<args> parameter accepts a reference to a list of parameters that
will be passed to the machine's C<_start> state.  They are passed in
the C<_start> event's C<ARG0..$#_> fields.

  args => [ 'arg0', 'arg1', 'etc.' ],

  sub _start {
    my @args = @_[ARG0..#$_];
    print "I received these parameters from create()'s args: @args\n";
  }

=item heap => ANYTHING

The C<heap> parameter defines a session's heap.  The heap is passed
into states as the $_[HEAP] field.  Heaps are anonymous hash
references by default.

  POE::Session->create( ..., heap => { runstate_variable => 1 }, ... );

  sub state_function {
    my $heap = $_[HEAP];
    print "runstate variable is $heap->{runstate_variable}\n";
  }

It's also possible to use create's C<heap> parameter to change the
heap into something completely different, such as a list reference or
even an object.

  sub RUNSTATE_VARIABLE () { 0 } # offset into the heap
  POE::Session->create( ..., heap => [ 1 ], ... );

  sub state_function {
    my $heap = $_[HEAP];
    print "runstate variable is ", $heap->[RUNSTATE_VARIABLE], "\n";
  }

=item inline_states => HASHREF

C<inline_states> maps events names to the plain coderefs which will
handle them.  Its value is a reference to a hash of event names and
corresponding coderefs.

  inline_states =>
  { _start => sub { print "arg0=$_[ARG0], arg1=$_[ARG1], etc.=$_[ARG2]\n"; }
    _stop  => \&stop_handler,
  },

These states are called "inline" because they can be inline anonymous
subs.

=item object_states => LISTREF

C<object_states> maps event names to the object methods which will
handle them.  Its value is a B<listref> of object references and the
methods to use.  It's a listref because using a hashref would
stringify its keys, and the object references would become unusable.

The object's methods can be specified in two ways.

The first form associates a listref to each object reference.  This
form maps each event to an object method with the same name.  In this
example, C<event_one> is handled by C<$object>'s C<event_one()>
method.

  object_states =>
  [ $object => [ 'event_one', 'event_two' ],
  ];

The second form associates a hashref to each object reference.  In
turn, the hashref maps each event name to a method in the object.  In
this form, the object's method names needn't match the event names
they'll handle.  For example, C<event_four> is handled by C<$object's>
C<handler_four()> method.

  object_states =>
  [ $object => { event_three => 'handler_three',
                 event_four  => 'handler_four',
               }
  ];

=item options => HASHREF

C<options> contains a new session's initial options.  It's equivalent
to creating the session and then calling its option() method to set
them.  HASHREF contains a set of option/value pairs.

These two statements are equivalent:

  POE::Session->create(
    ...,
    options => { trace => 1, debug => 1 },
    ...,
  );

  POE::Session->create(
    ...,
  )->option( trace => 1, debug => 1 );

See the option() method for a list of options and values.

=item package_states => LISTREF

C<package_states> maps event names to the package methods which will
handle them.  It's very similar to C<object_states>.
C<package_states>' value is a B<listref> of package names and the
methods to use.  It's a listref for consistency with C<object_states>.

The package's methods can be specified in two ways.

The first form associates a listref to each package name.  This form
maps each event to a package method with the same name.  In this
example, C<event_ten> is handled by C<Package>'s C<event_ten()>
method.

  package_states =>
  [ Package => [ 'event_ten', 'event_eleven' ],
  ];

The second form associates a hashref to each package n ame.  In turn,
the hashref maps each event name to a method in the package.  In this
form, the package's method names needn't match the event names they'll
handle.  For example, C<event_twelve> is handled by C<Package>'s
C<handler_twelve()> method.

  package_states =>
  [ Package => { event_twelve   => 'handler_twelve',
                 event_thirteen => 'handler_thirteen',
               }
  ];

=back

=item new LOTS_OF_STUFF

C<new()> is Session's older constructor.  Its design was clever at the
time, but it didn't expand well.  It's still useful for quick one-line
hacks, but consider using C<create()> for more complex sessions.

Inline states, object states, package states, and _start arguments are
all inferred by their contexts.  This context sensitivity makes it
harder for maintainers to understand what's going on, and it allows
errors to be interpreted as different behavior.

Inline states are specified as a scalar mapped to a coderef.

  event_one => \&state_one,
  event_two => sub { ... },

Object states are specified as object references mapped to list or
hash references.  Objects that are mapped to listrefs will handle
events with identically named methods.

  $object_one => [ 'event_one', 'event_two' ],

Objects that are mapped to hashrefs can handle events with differently
named methods.

  $object_two => { event_ten => 'method_foo', event_eleven => 'method_bar' },

Packgae states are specified as package names mapped to list or hash
references.  Package names that are mapped to listrefs will handle
events with identically named methods.

  PackageOne => [ 'event_five', 'event_six' ],

Package names that are mapped to hashrefs can handle events with
differently named methods.

  PackageTwo => { event_seven => 'method_baz', event_eight => 'method_quux' },

Arguments for the C<_start> state are specified as listrefs.

  [ 'arg0', 'arg1', ... ],

So, in summary, the rules for this constructor are:

  If a scalar appears as the "key" field ...
    If a coderef appears as its "value" ...
      Then it's an inline event handler.
    If a listref appears as its "value" ...
      Then it's a set of package states with the same names.
    If a hashref appears as its "value" ...
      Then it's a set of package states with possibly different names.
    Otherwise, it's an error.
  If an object reference appears as the "key" field ...
    If a listref appears as its "value" ...
      Then it's a set of object states with the same names.
    If a hashref appears as its "value" ...
      Then it's a set of object states with possibly different names.
    Otherwise, it's an error.
  If a listref appears as the "key" field ...
    Then it's a set of C<_start> arguments, and it has no "value".

=item option OPTION_NAME

=item option OPTION_NAME, OPTION_VALUE

=item option NAME_VALUE_PAIR_LIST

C<option()> sets and/or retrieves options' values.

The first form returns the value of a single option, OPTION_NAME,
without changing it.

  my $trace_value = $_[SESSION]->option( 'trace' );

The second form sets OPTION_NAME to OPTION_VALUE, returning the
B<previous> value of OPTION_NAME.

  my $old_trace_value = $_[SESSION]->option( trace => $new_trace_value );

The final form sets several options, returning a hashref containing
pairs of option names and their B<previous> values.

  my $old_values = $_[SESSION]->option(
    trace => $new_trace_value,
    debug => $new_debug_value,
  );
  print "Old option values:\n";
  while (my ($option, $old_value) = each %$old_values) {
    print "$option = $old_value\n";
  }

=item postback EVENT_NAME, PARAMETER_LIST

C<postback()> creates anonymous coderefs which, when called, post
EVENT_NAME events back to the same session.  Postbacks hold external
references on the sessions they're created for, so they keep their
sessions alive.

The EVENT_NAME event includes two fields.  C<ARG0> contains a
reference to the PARAMETER_LIST passed to C<postback()>.  This is the
"request" field.  C<ARG1> holds a reference to the parameters passed
to the coderef when it's called.  That's the "response" field.

This creates a Tk button that posts an "ev_counters_begin" event to
C<$session> whenever it's pressed.

  $poe_tk_main_window->Button
    ( -text    => 'Begin Slow and Fast Alarm Counters',
      -command => $session->postback( 'ev_counters_begin' )
    )->pack;

C<postback()> works wherever a callback does.  It's also possible to
use postbacks for request/response protocols between sessions.

  # The server session initializes and makes a name for itself.

  sub Servlet::_start {
    ...;
    $_[KERNEL]->alias_set( 'server' );
  }

  # The server accepts a request.  It creates a postback to respond to
  # its client, and saves it until a response is known.

  sub Servlet::accept_request_event {
    my ($heap, $sender, $reply_to, @request_args) =
      @_[HEAP, SENDER, ARG0, ARG1..$#_];

    # Build a postback, which also keeps the sender alive until a
    # response can be given back.
    $heap->{postback}->{$sender} =
      $sender->postback( $reply_to, @request_args );

    # Do something with @request_args.
    ...;
  }

  # The server is ready to respond.  It retrieves the postback and
  # calls it with the response values.

  sub Servlet::ready_to_respond {
    my ($heap, $sender, @response_values) = @_[HEAP, ARG0, ARG1..$#_];

    my $postback = delete $heap->{postback}->{$sender};
    $postback->( @response_values );
  }

  # The client posts a request.

  sub Client::request {
    my $kernel = $_[KERNEL];
    $kernel->post( servlet => accept_request_event => reply_to => 1, 2, 3 );
  }

  # The client receives a response.

  sub Client::reply_to {
    my ($session, $request, $response) = @_[SESSION, ARG0, ARG1];

    print "Session ", $session->ID, " requested: @$request\n";
    print "Session ", $session->ID, " received : @$response\n";
  }

=item get_heap

C<get_heap()> returns a reference to a session's heap.  It's the same
value that's passed to every state via the C<HEAP> field, so it's not
necessary within states.

Combined with the Kernel's C<get_active_session()> method,
C<get_heap()> lets libraries access a Session's heap without having to
be given it.  It's convenient, for example, to write a function like
this:

  sub put_stuff {
    my @stuff_to_put = @_;
    $poe_kernel->get_active_session()->heap()->{wheel}->put( @stuff_to_put );
  }

  sub some_state {
    ...;
    &put_stuff( @stuff_to_put );
  }

While it's more efficient to pass C<HEAP> along, it's also less
convenient.

  sub put_stuff {
    my ($heap, @stuff_to_put) = @_;
    $heap->{wheel}->put( @stuff_to_put );
  }

  sub some_state {
    ...;
    &put_stuff( $_[HEAP], @stuff_to_put );
  }

Although if you expect to have a lot of calls to &put_a_wheel() in
your program, you may want to optimize for programmer efficiency by
using the first form.

=back

=head1 Predefined Event Fields

Each session maintains its unique runtime context.  Sessions pass
their contexts on to their states through a series of standard
parameters.  These parameters tell each state about its Kernel, its
Session, itself, and the events that invoke it.

State parameters' offsets into @_ are never used directly.  Instead
they're referenced by symbolic constant.  This lets POE to change
their order without breaking programs, since the constants will always
be correct.

These are the @_ fields that make up a session's runtime context.

=over 2

=item ARG0
=item ARG1
=item ARG2
=item ARG3
=item ARG4
=item ARG5
=item ARG6
=item ARG7
=item ARG8
=item ARG9

C<ARG0..ARG9> are a state's first ten custom parameters.  They will
always be at the end of C<@_>, so it's possible to access more than
ten parameters with C<$_[ARG9+1]> or even this:

  my @args = @_[ARG0..$#_];

The custom parameters often correspond to PARAMETER_LIST in many of
the Kernel's methods.  This passes the words "zero" through "four" to
C<some_state> as C<@_[ARG0..ARG4]>:

  $_[KERNEL]->yield( some_state => qw( zero one two three four ) );

=item HEAP

C<HEAP> is a session's unique runtime storage space.  It's separate
from everything else so that Session authors don't need to worry about
namespace collisions.

States that store their runtime values in the C<HEAP> will always be
saving it in the correct session.  This makes them re-entrant, which
will be a factor when Perl's threading stops being experimental.

  sub _start {
    $_[HEAP]->{start_time} = time();
  }

  sub _stop {
    my $elapsed_runtime = time() - $_[HEAP]->{start_time};
    print 'Session ', $_[SESSION]->ID, " elapsed runtime: $elapsed_runtime\n";
  }

=item KERNEL

C<KERNEL> is a reference to the Kernel.  It's used to access the
Kernel's methods from within states.

  # Fire a "time_is_up" event in ten seconds.
  $_[KERNEL]->delay( time_is_up => 10 );

It can also be used with C<SENDER> to make sure Kernel events have
actually come from the Kernel.

=item OBJECT

C<OBJECT> is only meaningful in object and package states.

In object states, it contains a reference to the object whose method
is being invoked.  This is useful for invoking plain object methods
once an event has arrived.

  sub ui_update_everything {
    my $object = $_[OBJECT];
    $object->update_menu();
    $object->update_main_window();
    $object->update_status_line();
  }

In package states, it contains the name of the package whose method is
being invoked.  Again, it's useful for invoking plain package methods
once an event has arrived.

  sub Package::_stop {
    $_[PACKAGE]->shutdown();
  }

C<OBJECT> is undef in inline states.

=item SENDER

C<SENDER> is a reference to the session that sent an event.  It can be
used as a return address for service requests.  It can also be used to
validate events and ignore them if they've come from unexpected
places.

This example shows both common uses.  It posts a copy of an event back
to its sender unless the sender happens to be itself.  The condition
is important in preventing infinite loops.

  sub echo_event {
    $_[KERNEL]->post( $_[SENDER], $_[STATE], @_[ARG0..$#_] )
      unless $_[SENDER] == $_[SESSION];
  }

=item SESSION

C<SESSION> is a reference to the current session.  This lets states
access their own session's methods, and it's a convenient way to
determine whether C<SENDER> is the same session.

  sub enable_trace {
    $_[SESSION]->option( trace => 1 );
    print "Session ", $_[SESSION]->ID, ": dispatch trace is now on.\n";
  }

=item STATE

C<STATE> contains the event name that invoked a state.  This is useful
in cases where a single state handles several different events.

  sub some_state {
    print( "some_state in session ", $_[SESSION]-ID,
           " was invoked as ", $_[STATE], "\n"
         );
  }

  POE::Session->create(
    inline_states =>
    { one => \&some_state,
      two => \&some_state,
      six => \&some_state,
      ten => \&some_state,
    }
  );

The most common use is in the C<_default> state, which can be invoked
by almost anything.

=back

###############################################################################
###############################################################################
###############################################################################
##### AM HERE ### AM HERE ### AM HERE ### AM HERE ### AM HERE ### AM HERE #####
###############################################################################
###############################################################################
###############################################################################

=head1 Predefined Event Names

POE contains helpers which, in order to help, need to emit predefined
events.  These events all being with a single leading underscore, and
it's recommended that sessions not post leading-underscore events
unless they know what they're doing.

Predefined events generally have serious side effects.  The C<_start>
event, for example, performs a lot of internal session initialization.
Posting a redundant C<_start> event may try to allocate a session that
already exists, which in turn would do terrible, horrible things to
the Kernel's internal data structures.  Such things would normally be
outlawed outright, but the extra overhead to check for them would slow
everything down all the time.  Please be careful!  The clock cycles
you save may be your own.

These are the predefined events, why they're emitted, and what their
parameters mean.

=over 2

=item _child

C<_child> is a job-control event.  It notifies a parent session when
its set of child sessions changes.

C<ARG0> contains one of three strings describing what is happening to
the child session.

=over 2

=item 'create'

A child session has just been created, and the current session is its
original parent.

=item 'gain'

This session is gaining a new child from a child session that has
stopped.  A grandchild session is being passed one level up the
inheritance tree.

=item 'lose'

This session is losing a child which has stopped.

=back

C<ARG1> is a reference to the child session.  It will still be valid,
even if the child is in its death throes, but it won't last long
enough to receive posted events.  If the parent must interact with
this child, it should do so with C<call()> or some other means.

C<ARG2> is only valid when a new session has been created.  When
C<ARG0> is 'create', this holds the new session's C<_start> state's
return value.

=item _default

C<_default> is the event that's delivered whenever an event isn't
handled.  The unhandled event becomes parameters for C<_default>.

It's perfectly okay to post events to a session that can't handle
them.  When this occurs, the session's C<_default> handler is invoked
instead.  If the session doesn't have a C<_default> handler, then the
event is quietly discarded.

Quietly discarding events is a feature, but it makes catching mistyped
event names kind of hard.  There are a couple ways around this: One is
to define event names as symbolic constants.  Perl will catch typos at
compile time.  The second way around it is to turn on a session's
C<debug> option (see Session's C<option()> method).  This makes
unhandled events hard runtime errors.

As was previously mentioned, unhandled events become C<_default>'s
parameters.  The original state's name is preserved in C<ARG0> while
its custom parameter list is preserved as a reference in C<ARG1>.

  sub _default {
    print "Default caught an unhandled $_[ARG0] event.\n";
    print "The $_[ARG0] event was given these parameters: @{$_[ARG1]}\n";
  }

All the other C<_default> parameters are the same as the unhandled
event's, with the exception of C<STATE>, which becomes C<_default>.

B<Beware!> A C<_default> handler will catch unhandled signal events.
In this case, C<_default>'s return value is used to determine whether
the signal has been handled.  If any C<_default> handler always
returns true, then it will catch all but the nonmaskable signals, and
only SIGKILL may stop them.

L<POE::Kernel> discusses signal handlers in "Signal Watcher Methods".
It also covers the pitfals of C<_default> states in more detail

=item _parent

C<_parent> It notifies child sessions that their parent sessions are
in the process of changing.  It is the complement to C<_child>.

C<ARG0> contains the session's previous parent, and C<ARG1> contains
its new parent.

=item _signal

C<_signal> is a session's default signal handler.  Every signal that
isn't mapped to a specific state will be delivered to this one.

C<ARG0> contains the signal's name as it appears in Perl's %SIG hash.
That is, it's the root name of the signal without the SIG prefix.

Unhandled C<_signal> events will be forwarded to C<_default>.  In this
case, the C<_default> handler's return value becomes significant.
It's possible to accidentally write unkillable programs this way.

If C<_signal> and C<_default> handlers don't exist, then signals will
always be unhandled.

L<POE::Kernel>'s "Signal Watcher Methods" section is recommended
reading before using C<_signal> or C<_default>.  It discusses the
different signal levels, the mechanics of signal propagation, and why
it's always important to return an explicit value from a signal
handler, among other things.

=item _start

C<_start> is a session's initialization event.  It tells a session
that the Kernel has allocated and initialized resources for it, and it
may now start doing things.  A session's constructors invokes the
C<_start> handler before it returns, so it's possible for some
sessions' C<_start> states to run before $poe_kernel->run() is called.

Every session must have a C<_start> handler.  Its parameters are
slightly different from normal ones.

C<SENDER> contains a reference to the new session's parent.  Sessions
created before $poe_kernel->run() is called will have C<KERNEL> as
their parents.

C<ARG0..$#_> contain the parameters passed into the Session's
constructor.  See Session's C<new()> and C<create()> methods for more
information on passing parameters to new sessions.

=item _stop

C<_stop> is sent to a session when it's about to stop.  This usually
occurs when a session has run out of events to handle and resources to
generate new events.

The C<_stop> handler is used to perform shutdown tasks, such as
releasing custom resources and breaking circular references so that
Perl's garbage collection will properly destroy things.

=back

=head2 States' Return Values

States are always evaluated in a scalar context.  States that must
return more than one value should therefore return them as a reference
to something bigger.

Signal handlers' return values are significant.  L<POE::Kernel>'s
"Signal Watcher Methods" sections covers this is detail.

States may not return references to objects in the "POE" namespace.
The Kernel will stringify these references to prevent them from
lingering and beraking its own garbage collection.

=head2 Resource Tracking

POE::Kernel tracks resources on behalf of its active sessions.  It
generates events corresponding to these resources' activity, notifying
sessions when it's time to do things.

The conversation goes something like this.

  Session: Be a dear, Kernel, and let me know when someone clicks on
           this widget.  Thanks so much!

  [TIME PASSES]  [SFX: MOUSE CLICK]

  Kernel: Right, then.  Someone's clicked on your widget.
          Here you go.

Furthermore, since the Kernel keeps track of everything sessions do,
it knows when a session has run out of tasks to perform.  When this
happens, the Kernel emits a C<_stop> event at the dead session so it
can clean up and shutdown.

  Kernel: Please switch off the lights and lock up; it's time to go.

Likewise, if a session stops on its own and there still are opened
resource watchers, the Kernel knows about them and cleans them up on
the session's behalf.  POE excels at long-running services because it
so meticulously tracks and cleans up its resources.

=head2 Synchronous and Asynchronous Events

While time's passing, however, the Kernel may be telling Session other
things are happening.  Or it may be telling other Sessions about
things they're interested in.  Or everything could be quiet... perhaps
a little too quiet.  Such is the nature of non-blocking, cooperative
timeslicing, which makes up the heart of POE's threading.

Some resources must be serviced right away, or they'll faithfully
continue reporting their readiness.  These reports would appear as a
stream of duplicate events, which would be bad.  Filehandles are like
this: They remain ready as long as they're not serviced.  For this
reason, some events (namely filehandle readiness events) invoke their
handlers immediately.  These are "synchronous" events because they're
handled right away.

The other kind of event is called "asynchronous" because they're
posted and dispatched through a queue.  There's no telling just when
they'll arrive.

Synchronous event handlers should perform simple tasks limited to
handling the resources that invoked them.  They are very much like
device drivers in this regard.

Synchronous events that need to do more than just service a resource
should pass the resource's information to an asynchronous handler.
Otherwise synchronous operations will occur out of order in relation
to asynchronous events.  It's very easy to have race conditions or
break causality this way, so try to avoid it unless you're okay with
the consequences.

=head2 Postbacks

Many external libraries expect plain coderef callbacks, but sometimes
programs could use asynchronous events instead.  POE::Session's
C<postback()> method was created to fill this need.

C<postback()> creates coderefs suitable to be used in traditional
callbacks.  When invoked as callbacks, these coderefs post their
parameters as POE events.  This lets POE interact with nearly every
callback currently in existing, and most future ones.

=head2 Job Control and Family Values

Sessions are resources, too.  The Kernel watches sessions come and go,
maintains parent/child relationships, and notifies sessions when these
relationships change.  These events, C<_parent> and C<_child>, are
useful for job control and managing pools of worker sessions.

Parent/child relationships are maintained automatically.  "Child"
sessions simply are ones which have been created from an existing
session.  The existing session which created a child becomes its
"parent".

A session with children will not spontaneously stop.  In other words,
the presence of child sessions will keep a parent alive.

=head1 SEE ALSO

POE::Kernel.

The SEE ALSO section in L<POE> contains a table of contents covering
the entire POE distribution.

=head1 BUGS

There is a chance that session IDs may collide after Perl's integer
value wraps.  This can occur after as few as 4.29 billion sessions.

=head1 AUTHORS & COPYRIGHTS

Please see L<POE> for more information about authors and contributors.

=cut
