package APISchema::Schema;
use strict;
use warnings;
use 5.014;
use Scalar::Util qw(blessed);

use APISchema::Route;
use APISchema::Resource;

use Class::Accessor::Lite (
    rw => [qw(title description)],
);

sub new {
    my ($class) = @_;

    bless {
        resources => {},
        routes => [],
        references => {},
    }, $class;
}

sub register_resource {
    my ($self, $title, $definition) = @_;

    my $resource = APISchema::Resource->new(
        title => $title,
        definition => $definition,
    );
    $self->{resources}->{$title} = $resource;

    return $resource;
}

sub get_resources {
    my ($self) = @_;

    [ sort { $a->title cmp $b->title } values %{$self->{resources}} ];
}

sub get_resource_by_name {
    my ($self, $name) = @_;

    $self->{resources}->{$name || ''};
}

sub get_resource_root {
    my ($self) = @_;
    return +{
        resource   => +{ map {
            $_ => $self->{resources}->{$_}->definition;
        } keys %{$self->{resources}} },
        properties => {},
    };
}

sub _next_title_candidate {
    my ($self, $base_title) = @_;
    if ($base_title =~ /\(([0-9]+)\)$/) {
        my $index = $1 + 1;
        return $base_title =~ s/\([0-9]+\)$/($index)/r;
    } else {
        return $base_title . '(1)';
    }
}

sub register_route {
     my ($self, %values) = @_;

     # make fresh title
     my $title = $values{title} // $values{route} // 'empty_route';
     while ($self->get_route_by_name($title)) {
         $title = $self->_next_title_candidate($title);
     }

     my $route = APISchema::Route->new(
         %values,
         title => $title,
     );
     push @{$self->{routes}}, $route;
     return $route;
}

sub get_routes {
    my ($self) = @_;

    $self->{routes};
}

sub get_route_by_name {
    my ($self, $name) = @_;
    my ($route) = grep { ($_->title||'') eq $name } @{$self->get_routes};
    return $route;
}

sub register_references {
    my ($self, $resource, $reference) = @_;
    push @{$self->{references}->{$resource->title}}, $reference;
}

sub get_references {
    my ($self, $resolver) = @_;

    my $root = $self->get_resource_root;
    for my $route (@{$self->get_routes}) {
        my $default_code = $route->default_responsible_code;
        my $resources = [grep {
            blessed($_) && $_->isa('APISchema::Resource')
        } (
            values %{$route->canonical_request_resource($root)},
            values %{$route->canonical_response_resource($root, [$default_code])},
        )];
        for my $resource (@$resources) {
            my $properties = $resolver->properties($resource->definition);
            for my $key (sort keys %$properties) {
                my $prop = $properties->{$key};
                if (exists $prop->{'$ref'}) {
                    my $ref = $prop->{'$ref'} =~ s!^#/resource/!!r;
                    push @{$self->{references}->{$ref}}, $route;
                }
            }
        }
    }

    for my $resource (@{$self->get_resources}) {
        my $properties = $resolver->properties($resource->definition);
        for my $key (sort keys %$properties) {
            my $prop = $properties->{$key};
            if (exists $prop->{'$ref'}) {
                my $ref = $prop->{'$ref'} =~ s!^#/resource/!!r;
                push @{$self->{references}->{$ref}}, $resource;
            }
        }
    }

    for my $references (values %{$self->{references}}) {
        my %seen;
        $references = [
            grep { !$seen{$_->title}++ } @$references
        ];
    }

    return $self->{references};
}

1;
