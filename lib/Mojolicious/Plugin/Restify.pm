package Mojolicious::Plugin::Restify;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Util qw(camelize);

our $VERSION = '0.01';

sub register {
  my ($self, $app, $conf) = @_;

  $conf //= {};
  # over defaults to the standard route condition check (allow all)
  $conf->{over} //= 'standard';
  # unders are added to all the element resource routes by default
  $conf->{under} //= 1;

  # When adding route conditions, warn developers if the exported conditions
  # already exist.
  if (exists $app->routes->conditions->{int}) {
    $app->log->debug("The int route condition already exists, skipping");
  }
  else {
    $app->routes->add_condition(
      int => sub {
        my ($r, $c, $captures, $pattern) = @_;
        my $int
          = defined $pattern
          ? ($captures->{$pattern} // $captures->{int})
          : ($captures->{int} // '');

        return 1 if $int =~ /^\d+$/;
      }
    );
  }

  if (exists $app->routes->conditions->{standard}) {
    $app->log->debug("The standard route condition already exists, skipping");
  }
  else {
    $app->routes->add_condition(standard => sub {1});
  }

  if (exists $app->routes->conditions->{uuid}) {
    $app->log->debug("The uuid route condition already exists, skipping");
  }
  else {
    $app->routes->add_condition(
      uuid => sub {
        my ($r, $c, $captures, $pattern) = @_;
        my $uuid
          = defined $pattern
          ? ($captures->{$pattern} // $captures->{uuid})
          : ($captures->{uuid} // '');

        return 1
          if $uuid
          =~ /^[a-f0-9]{8}-?[a-f0-9]{4}-?[a-f0-9]{4}-?[a-f0-9]{4}-?[a-f0-9]{12}$/i;
      }
    );
  }

  $app->routes->add_shortcut(
    collection => sub {
      my $r       = shift;
      my $path    = shift;
      my $options = ref $_[0] eq 'HASH' ? shift : {@_};

      $options->{element} //= 1;
      $options->{route_path} = $path;
      $path =~ tr/-/_/;
      $options->{route_name}
        = $options->{prefix} ? "$options->{prefix}_$path" : $path;

      # generate "/$path" collection route
      my $controller
        = $options->{controller} ? "$options->{controller}-$path" : $path;
      my $collection
        = $r->route("/$options->{route_path}")->to("$controller#");
      $collection->get->to("#list")->name("$options->{route_name}_list");
      $collection->post->to("#create")->name("$options->{route_name}_create");

      return $options->{element}
        ? $collection->element($options->{route_path}, $options)
        : $collection;
    }
  );

  $app->routes->add_shortcut(
    element => sub {
      my $r       = shift;
      my $path    = shift;
      my $options = ref $_[0] eq 'HASH' ? shift : {@_};

      $options->{over}  //= $conf->{over};
      $options->{under} //= $conf->{under};
      $path =~ tr/-/_/;
      $options->{route_name}
        = $options->{prefix} ? "$options->{prefix}_$path" : $path;

      # generate "/$path/:id" element route with standard placeholder
      my $element
        = $r->route("/:${path}_id")->over($options->{over} => "${path}_id")
        ->name($options->{route_name});

      # Generate remaining CRUD routes for "/$path/:id", but also create an
      # under for the resource $element.
      #
      # This method allows loading an object using the :id in the under,
      # and have it accessible via the stash in DELETE, GET, PUT etc. methods
      # in your controller.
      my $under
        = $options->{under}
        ? $element->under->to('#under')->name("$options->{route_name}_under")
        : $element;
      $under->delete->to('#delete')->name("$options->{route_name}_delete");
      $under->get->to('#read')->name("$options->{route_name}_read");
      $under->patch->to('#patch')->name("$options->{route_name}_patch");
      $under->put->to('#update')->name("$options->{route_name}_update");

      return $element;
    }
  );

  $app->helper(
    'restify.current_id' => sub {
      my $c    = shift;
      my $name = $c->stash->{controller};
      $name =~ s,^.*?\-,,;
      return $c->match->stack->[-1]->{"${name}_id"} // '';
    }
  );

  $app->helper(
    'restify.routes' => sub {
      my ($self, $r, $routes, $defaults) = @_;
      return unless $routes;

      $defaults //= {};
      $defaults->{under} //= $conf->{under};

      while (my ($name, $attrs) = each %$routes) {
        my $paths   = {};
        my $options = {%$defaults};

        if (ref $attrs eq 'ARRAY') {
          $options = {%$options, %{$attrs->[-1]}}
            if ref $attrs->[-1] eq 'HASH';
          $paths = shift @$attrs if ref $attrs->[0] eq 'HASH';
        }
        elsif (ref $attrs eq 'HASH') {
          $paths = $attrs;
        }

        if (scalar keys %$paths) {
          my $controller = $name;
          $controller =~ tr/-/_/;
          my $collection = $r->collection($name, {%$options, element => 0});
          my $under
            = $options->{under}
            ? $collection->under->to("$controller#under")
            : $collection;
          my $endpoint = $under->element($name, {%$options, under => 0});
          $options->{controller}
            = $options->{controller}
            ? "$options->{controller}-$controller"
            : $controller;
          $options->{prefix}
            = $options->{prefix}
            ? "$options->{prefix}_$controller"
            : $controller;
          $self->restify->routes($endpoint, $paths, $options);
        }
        else {
          $r->collection($name, $options);
        }
      }

      return;
    }
  );
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Restify - Route shortcuts & helpers for REST collections

=head1 SYNOPSIS

  # Mojolicious example (Mojolicious::Lite isn't supported)
  package MyApp;
  use Mojo::Base 'Mojolicious';

  sub startup {
    my $self = shift;

    # imports the `collection' route shortcut and `restify' helpers
    $self->plugin('Restify');

    # add REST collection endpoints manually
    my $r = $self->routes;
    my $accounts = $r->collection('accounts');      # /accounts
    $accounts->collection('invoices');              # /accounts/:accounts_id/invoices

    # or add the equivalent REST routes using the restify helper
    # my $r = $self->routes;
    # $self->restify->routes($r, {accounts => {invoices => undef}});
  }

  # Restify controller depicting the REST actions for the /accounts collection.
  # (The name of the controller is the Mojo::Util::camelized version of the
  # collection path.)
  package MyApp::Controller::Accounts;
  use Mojo::Base 'Mojolicious::Controller';

  sub under {
    my $c = shift;

    # To consistenly get the element's ID relative to the under action, use the
    # helper as shown below. If you need to access an element ID from a
    # collection further up the chain, you can access it from the stash.
    #
    # The naming convention is the name of the collection appended with '_id'.
    # E.g., $c->stash('accounts_id').
    my $account = lookup_account_resource($c->restify->current_id);

    # By stashing the $account here, it will now be available in the delete,
    # read, patch, and update actions. This under action is added to every
    # collection by default to help reduce your code, but can be disabled if
    # you wish.
    $c->stash(account => $account);

    # must return a positive value to continue the dispatch chain
    return 1 if $account;

    # inform the end user that this specific resource does not exist
    $c->reply->not_found and return 0;
  }

  sub create { ... }

  sub delete { ... }

  sub list { ... }

  sub read {
    my $c = shift;

    # account was placed in the stash in the under method
    $c->render(json => $c->stash('account'));
  }

  sub patch { ... }

  sub update { ... }

  1;

=head1 DESCRIPTION

L<Mojolicious::Plugin::Restify> is a L<Mojolicious::Plugin>. It simplifies
generating all of the L<Mojolicious::Routes> for a typical REST I<collection>
endpoint (e.g., C</accounts> or C</invoices>) and maps the common HTTP verbs
(C<DELETE>, C<GET>, C<PATCH>, C<POST>, C<PUT>) to underlying controller class
methods.

For example, creating a I<collection> called C</accounts> would create the
routes as shown below. N.B. The C<over> option in the example below corresponds
to the name of a route condition. See L<Mojolicious::Routes/conditions>.

  # The collection route shortcut below creates the following routes, and maps
  # them to controllers of the camelized route's name.
  #
  # /accounts           *         accounts
  #   +/                GET       "accounts_list"       Accounts::list
  #   +/                POST      "accounts_create"     Accounts::create
  #   +/:accounts_id    *         "accounts"
  #     +/              *         "accounts_under"      Accounts::under
  #       +/            DELETE    "accounts_delete"     Accounts::delete
  #       +/            GET       "accounts_read"       Accounts::read
  #       +/            PATCH     "accounts_patch"      Accounts::patch
  #       +/            PUT       "accounts_update"     Accounts::update

  # expects the element id (:accounts_id) for this collection to be a uuid
  my $route = $r->collection('accounts', over => 'uuid');

L<Mojolicious::Plugin::Restify> tries not to make too many assumptions, but the
author's recent experience writing a REST-based API using L<Mojolicious> has
helped shaped this plugin, and might unwittingly express some of his bias.

=head1 HELPERS

L<Mojolicious::Plugin::Restify> implements the following helpers.

=head2 restify->current_id

  my $id = $c->restify->current_id;

Returns the I<element> id at the current point in the dispatch chain.

This is the only way to guarantee the correct I<element>'s resource ID in a
L<Mojolicious::Plugin::Restify> I<action>. The C<under> I<action> which is added
by default in both L</collection> and L</restify-routes> is added at different
positions of the dispatch chain. As such, the router might not have added the
value of any placeholders to the L<Mojolicious::Controller::stash> yet.

=head2 restify->routes

This helper allows you to create REST I<collections> from a Perl C<HASH>. It
uses the key/values to invoke the L</collection> route shortcut with any route-
specific options. It automatically chains routes to each parent, and
progressively builds a namespace as it traverses through every key.

See L</collection> for more route-specific options.

  my $restify_routes = {
    # /area-codes
    #   /area-codes/:area_codes_id/numbers
    'area-codes' => {
      'numbers' => undef
    },
    # /news
    'news' => undef,
    # /payments
    'payments' => [undef, {over => 'int'}],   # overrides default uuid route condition set below
    # /users
    #   /users/:users_id/messages
    #     /users/:users_id/messages/:messages_id/recipients
    'users' => {
      'messages' => {
        'recipients' => undef
      }
    },
  };

  $self->restify->routes($self->routes, $restify_routes, {over => 'uuid'});

=head1 METHODS

L<Mojolicious::Plugin::Restify> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head1 ROUTE CONDITIONS

L<Mojolicious::Plugin::Restify> implements the following route conditions. These
conditions can be used with the C<over> option in the L</collection> shortcut.

Checks are made for the existence of the C<int>, C<standard> and C<uuid>
conditions before adding them. This allows you to replace them with your own
conditions of the same name by creating them before registering this plugin.

See L<Mojolicious::Guides::Routing/Adding-conditions> to add your own.

=head2 int

  # /numbers/1        # GOOD
  # /numbers/0        # GOOD
  # /numbers/one      # BAD
  # /numbers/-1       # BAD
  # /numbers/0.114    # BAD (the standard :placeholder notation doesn't allow a '.')

  my $r = $self->routes;
  $r->collection('numbers', over => 'int');

A L<Mojolicious> route condition (see L<Mojolicious::Routes/conditions>) which
restricts a route's I<collection>'s I<element> id to whole positive integers
which are C<E<gt>= 0>.

=head2 standard

  my $r = $self->routes;
  $r->collection('numbers', over => 'standard');

A I<collection>'s I<element> resource ID is captured using
L<Mojolicious::Guides::Routing/Standard-placeholders>. This route condition
allows everything the standard placeholder allows, which is similar to the
regular expression C<([^/.]+)>.

This is the default I<over> option for a L</collection>.

=head2 uuid

  # /uuids/8ebef0d0-d6cf-11e4-8830-0800200c9a66     GOOD
  # /uuids/8EBEF0D0-D6CF-11E4-8830-0800200C9A66     GOOD
  # /uuids/8ebef0d0d6cf11e488300800200c9a66         GOOD
  # /uuids/malformed-uuid                           BAD

  my $r = $self->routes;
  $r->collection('uuids', over => 'uuid');

A L<Mojolicious> route condition (see L<Mojolicious::Routes/conditions>) which
restricts a route's I<collection>'s I<element> id to UUIDs only (with or without
the separating hyphens).

=head1 ROUTE SHORTCUTS

L<Mojolicious::Plugin::Restify> implements the following route shortcuts.

=head2 collection

  my $r = $self->routes;
  $r->collection('accounts');

A L<Mojolicious routes shortcut|Mojolicious::Routes/shortcuts> which helps
create the most common REST L<routes|Mojolicious::Routes::Route> for a
I<collection> endpoint and its associated I<element>.

A I<collection> endpoint (e.g., C</accounts>) supports I<list> (C<GET>) and
I<create> (C<POST>) actions. The I<collection>'s I<element> (e.g.,
C</accounts/:accounts_id>) supports I<delete> (C<DELETE>), I<read> (C<GET>),
I<patch> (C<PATCH>), and I<update> (C<PUT>) actions.

By default, every HTTP request to a I<collection>'s I<element> is routed through
an C<under> I<action> (see L<Mojolicious::Routes::Route/under>). This helps
reduce the process of looking up a resource to a single location. See
L</SYNOPSIS> for an example of its use.

=head4 options

The following options allow a I<collection> to be fine-tuned.

=over

=item controller

  # collection doesn't build a namespace for subroutes by default
  my $accounts = $r->collection('accounts');    # MyApp::Controller::Accounts
  $accounts->collection('invoices');            # MyApp::Controller::Invoices

  # collection can build namespaces, but can be difficult to keep track of. Use
  # the restify helper if namespaces are important to you.
  #
  # MyApp::Controller::Accounts
  my $accounts = $r->collection('accounts');
  # MyApp::Controller::Accounts::Invoices
  my $invoices = $accounts->collection('invoices', controller => 'accounts');
  # MyApp::Controller::Accounts::Invoices::Foo
  $invoices->collection('foo', controller => 'accounts-invoices');

Prepends the controller name (which is automatically generated based on the path
name) with this option value if present. Used internally by L</restify> to build
a perlish namespace from the paths. L</collection> does not build a namespace by
default.

=item element

  # GET,POST                      /messages     200
  # DELETE,GET,PATCH,PUT,UPDATE   /messages/1   200
  $r->collection('messages');     # element routes are created by default

  # GET,POST                      /messages     200
  # DELETE,GET,PATCH,PUT,UPDATE   /messages/1   404
  $r->collection('messages', element => 0);

Enables or disables adding an I<element> to the I<collection>. Disabling the
element portion of a I<collection> means that only the I<create> and I<list>
actions will be created.

=item over

  $r->collection('accounts', over => 'uuid');
  $r->collection('invoices', over => 'int');

Allows a I<collection>'s I<element> to be restricted to a specific data type
using Mojolicious' route conditions. L</int>, L</standard> and L</uuid> are
added automatically if they don't already exist.

=item prefix

  # without a prefix
  $r->collection('invoices');
  say $c->url_for('invoices', invoices_id => 1);

  # with a prefix
  $r->collection('invoices', prefix => 'v1');
  say $c->url_for('v1_invoices', invoices_id => 1);

Adds a prefix to the automatically generated route
L<name|Mojolicious::Routes::Route/name> for each I<collection> and I<element>
I<action>.

=item under

  $r->collection('nounder', under => 0);

Enables or disables adding an C<under> I<action> to the I<element> of the
I<collection>.

=back

=head2 element

  my $r    = $self->routes;
  my $news = $r->get('/news')->to('foo#news');
  $news->element('news');

A L<Mojolicious route shortcut|Mojolicious::Routes/shortcuts> called internally
by L</collection> to add the I<element> routes to a I<collection>. You shouldn't
need to call this shortcut directly.

When an element is added to a I<collection>'s route, the resource ID is captured
using a standard placeholder.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015, Paul Williams.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Paul Williams <kwakwa@cpan.org>

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Plugin::REST>, L<Mojolicious::Plugin::RESTRoutes>.

=cut