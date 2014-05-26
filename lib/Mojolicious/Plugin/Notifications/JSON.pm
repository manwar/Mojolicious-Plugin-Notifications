package Mojolicious::Plugin::Notifications::JSON;
use Mojo::Base 'Mojolicious::Plugin';

has key => 'notifications';

# Nothing to register
sub register {
  my ($plugin, $mojo, $param) = @_;
  $plugin->key($param->{key}) if $param->{key};
};


# Notification method
sub notifications {
  my ($self, $c, $notify_array, $json, %param) = @_;

  my $key = $param{key} // $self->key;

  return $json unless @$notify_array;

  if (!$json || ref $json) {
    my @msgs;
    foreach (@$notify_array) {
      push(@msgs, [$_->[0], $_->[-1]]);
    };

    if (!$json) {
      return { $key => \@msgs }
    }

    # Obect is an array
    elsif (index(ref $json, 'ARRAY') >= 0) {
      push(@$json, { $key => \@msgs });
    }

    # Object is a hash
    elsif (index(ref $json, 'HASH') >= 0) {
      my $n = ($json->{$key} //= []);
      push(@$n, @msgs);
    };
  };

  return $json;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Notifications::JSON - Event Notification in JSON


=head1 SYNOPSIS

  # Register the engine
  plugin Notifications => { JSON => 1 };

  # In the controller
  $c->render(json => $c->notifications(json => $json));


=head1 DESCRIPTION

This plugin is a simple notification engine for JSON.

If this does not suit your needs, you can easily
L<write your own engine|Mojolicious::Plugin::Notifications/Writing your own engine>.


=head1 METHODS

=head2 register

  plugin Notifications => {
    JSON => {
      key => 'notes'
    }
  };

Called when registering the main plugin.
All parameters under the key C<JSON> are passed to the registration.

Accepts the following parameters:

=over 4

=item B<key>

Define the attribute name of the notification array.
Defaults to C<notifications>.

=back


=head1 HELPERS

=head2 notify

See L<notify|Mojolicious::Plugin::Notifications/notify>.


=head2 notifications

  $c->render(json => $c->notifications(json => $json));
  $c->render(json => $c->notifications(json => $json, key => 'notes'));

Merge notifications into your JSON response.

In case JSON is an object, it will inject an attribute
that points to an array reference containing the notifications.
If the JSON object is a array, an object is appended with one attribute
that points to an array reference containing the notifications.
If the JSON object is empty, an object will be created an attribute
that points to an array reference containing the notifications.

If the JSON is not of one of the descripted types, it's returned
unaltered.

The name of the attribute can either be given on registration or
by passing a parameter for C<key>.
The name defaults to C<notifications>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Notifications


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
