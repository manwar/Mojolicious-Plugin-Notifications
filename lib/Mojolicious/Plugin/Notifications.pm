package Mojolicious::Plugin::Notifications;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::Notifications::Assets;
use Mojo::Util qw/camelize/;

our $TYPE_RE = qr/^[-a-zA-Z_]+$/;

our $VERSION = '0.4';

# Todo: Support Multiple Times Loading
# Explain camelize and :: behaviour for engine names
# Subroutines for Engines should be given directly

# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  $param ||= {};

  my $debug = $mojo->mode eq 'development' ? 1 : 0;

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Notifications')) {
    $param = { %$param, %$config_param };
  };

  $param->{HTML} = 1 unless keys %$param;

  # Get helpers object
  my $helpers = $mojo->renderer->helpers;

  # Add engines from configuration
  my %engine;
  foreach my $name (keys %$param) {
    my $engine = camelize $name;
    if (index($engine,'::') < 0) {
      $engine = __PACKAGE__ . '::' . $engine;
    };

    # Load engine
    my $e = $mojo->plugins->load_plugin($engine);
    $e->register($mojo, ref $param->{$name} ? $param->{$name} : undef);
    $engine{lc $name} = $e;
  };

  # Create asset object
  my $asset = Mojolicious::Plugin::Notifications::Assets->new;

  # Set assets
  foreach (values %engine) {
    # The check is a deprecation option!
    $asset->styles($_->styles)   if $_->can('styles');
    $asset->scripts($_->scripts) if $_->can('scripts');
  };

  # Add notifications
  $mojo->helper(
    notify => sub {
      my $c = shift;
      my $type = shift;
      my @msg = @_;

      # Ignore debug messages in production
      return if $type !~ $TYPE_RE || (!$debug && $type eq 'debug');

      my $array;

      # Notifications already set
      if ($array = $c->stash('notify.array')) {
	push (@$array, [$type => @msg]);
      }

      # New notifications
      else {
	$c->stash('notify.array' => [[$type => @msg]]);

	# Watch out - may break whenever something weird in the order
	# between after_dispatch and resume happens
	$c->tx->once(
	  resume => sub {
	    my $tx = shift;
	    if ($tx->res->is_status_class(300)) {
	      $c->flash('n!.a' => delete $c->stash->{'notify.array'});
	      $c->app->sessions->store($c);
	    };
	  });
      };
    }
  );


  # Embed notification display
  $mojo->helper(
    notifications => sub {
      my $c = shift;

      return $asset unless @_;

      my $e_type = lc shift;
      my @param = @_;

      my @notify_array;

      # Get flash notifications
      my $flash = $c->flash('n!.a');
      if ($flash && ref $flash eq 'ARRAY') {

	# Ensure that no harmful types are injected
	push @notify_array, grep { $_->[0] =~ $TYPE_RE } @$flash;

	# Use "n!.a" instead of notify.array as this goes into the cookie
	$c->flash('n!.a' => undef);
      };

      # Get stash notifications
      if ($c->stash('notify.array')) {
	push @notify_array, @{ delete $c->stash->{'notify.array'} };
      };

      # Nothing to do
      return '' unless @notify_array || @_;

      # Forward messages to notification center
      if (exists $engine{$e_type}) {

	my %rule;
	while ($param[-1] && index($param[-1], '-') == 0) {
	  $rule{lc(substr(pop @param, 1))} = 1;
	};

	return $engine{$e_type}->notifications($c, \@notify_array, \%rule, @param);
      }
      else {
	$c->app->log->error(qq{Unknown notification engine "$e_type"});
	return;
      };
    }
  );
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Notifications - Frontend Event Notifications


=head1 SYNOPSIS

  # Register the plugin and several engines
  plugin Notifications => {
    Humane => {
      base_class => 'libnotify'
    },
    JSON => 1
  };

  # Add notification messages in controllers
  $c->notify(warn => 'Something went wrong');

  # Render notifications in templates ...
  %= notifications 'humane';

  # ... or in any other responses
  my $json = { text => 'That\'s my response' };
  $c->render(json => $c->notifications(json => $json));


=head1 DESCRIPTION

L<Mojolicious::Plugin::Notifications> supports several engines
to notify users on events. Notifications will survive redirects
and can be served depending on response types.


=head1 METHODS

L<Mojolicious::Plugin::Notifications> inherits all methods
from L<Mojolicious::Plugin> and implements the following new one.

=head2 register

  plugin Notifications => {
    Humane => {
      base_class => 'libnotify'
    },
    HTML => 1
  };

Called when registering the plugin.

Accepts the registration of multiple L<engines|/ENGINES> for notification
responses. Configurations of the engines can be passed as hash
references. If no configuration should be passed, just pass a scalar value.

All parameters can be set either as part of the configuration
file with the key C<Notifications> or on registration
(that can be overwritten by configuration).


=head1 HELPERS

=head2 notify

  $c->notify(error => 'Something went wrong');
  $c->notify(error => { timeout => 4000 } => 'Something went wrong');

Notify the user about an event.
Expects an event type and a message as strings.
In case a notification engine supports further refinements,
these can be passed in a hash reference as a second parameter.
Event types are free and its treatment is up to the engines,
however notifications of the type C<debug> will only be passed in
development mode.


=head2 notifications

  %= notifications 'humane' => [qw/warn error success/];
  %= notifications 'html';

  $c->render(json => $c->notifications(json => {
    text => 'My message'
  }));

Serve notifications to your user based on an engine.
The engine's name has to be passed as the first parameter
and the engine has to be L<registered|/register> in advance.
Notifications won't be invoked in case no notifications are
in the queue and no further engine parameters are passed.
Engine parameters are documented in the respective plugins.

In case no engine name is passed to the notifications method,
an L<assets object|Mojolicious::Plugin::Notifications::Assets>
is returned, bundling all registered engines' assets for use
in the L<AssetPack|Mojolicious::Plugin::AssetPack> pipeline.

  # Register Notifications plugin
  app->plugin('Notifications' => {
    Humane => {
      base_class => 'libnotify'
    },
    Alertify => 1
  );

  # Register AssetPack plugin
  app->plugin('AssetPack');

  # Add notification assets to pipeline
  my $assets = app->notifications;
  app->asset('myApp.js'  => $assets->scripts);
  app->asset('myApp.css' => $assets->styles);

  %# In templates embed assets ...
  %= asset 'myApp.js'
  %= asset 'myApp.css'

  %# ... and notifications (without assets)
  %= notifications 'humane', -no_include;

B<The asset helper option is experimental and may change without warnings!>


=head1 ENGINES

L<Mojolicious::Plugin::Notifications> bundles a couple of different
notification engines, but you can
L<easily write your own engine|Mojolicious::Plugin::Notifications::Engine>.


=head2 Bundled engines

The following engines are bundled with this plugin:
L<HTML|Mojolicious::Plugin::Notifications::HTML>,
L<JSON|Mojolicious::Plugin::Notifications::JSON>,
L<Humane.js|Mojolicious::Plugin::Notifications::Humane>, and
L<Alertify.js|Mojolicious::Plugin::Notifications::Alertify>,


=head1 SEE ALSO

If you want to use Humane.js without L<Mojolicious::Plugin::Notifications>,
you should have a look at L<Mojolicious::Plugin::Humane>,
which was the original inspiration for this plugin.

Without my knowledge (due to a lack of research by myself),
L<Mojolicious::Plugin::BootstrapAlerts> already established
a similar mechanism for notifications using Twitter Bootstrap
(not yet supported by this module).
Accidentally the helper names collide - I'm sorry for that!
On the other hands, that makes these modules in most occasions
compatible.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Notifications


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

Part of the code was written at the
L<Mojoconf 2014|http://www.mojoconf.org/mojo2014/> hackathon.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
