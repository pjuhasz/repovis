package VCS::Visualize::BoundingRectangle;

use 5.010001;
use strict;
use warnings;

sub new {
    my $class = shift;
	my ($max_x, $max_y, $min_x, $min_y) = @_;
    
    my $self = {
        max_x => $max_x // -1000000,
        max_y => $max_y // -1000000,
        min_x => $min_x //  1000000,
        min_y => $min_y //  1000000,
    };

    bless $self, $class;
}

sub update {
    my ($self, $ex) = @_;
    $self->{max_x} = $self->{max_x} > $ex->{max_x} ? $self->{max_x} : $ex->{max_x};
    $self->{max_y} = $self->{max_y} > $ex->{max_y} ? $self->{max_y} : $ex->{max_y};
    $self->{min_x} = $self->{min_x} < $ex->{min_x} ? $self->{min_x} : $ex->{min_x};
    $self->{min_y} = $self->{min_y} < $ex->{min_y} ? $self->{min_y} : $ex->{min_y};
}

sub update_xy {
    my ($self, $x, $y) = @_;
    $self->{max_x} = $self->{max_x} > $x ? $self->{max_x} : $x;
    $self->{max_y} = $self->{max_y} > $y ? $self->{max_y} : $y;
    $self->{min_x} = $self->{min_x} < $x ? $self->{min_x} : $x;
    $self->{min_y} = $self->{min_y} < $y ? $self->{min_y} : $y;
}

sub xs { $_[0]->{max_x} - $_[0]->{min_x} }

sub ys { $_[0]->{max_y} - $_[0]->{min_y} }

1;

__END__

=head1 NAME

VCS::Visualize::BoundingRectangle - Helper class to track the bounding rectangle of a set of points

=head1 SYNOPSIS

  use VCS::Visualize::BoundingRectangle;
  
  my $extent = VCS::Visualize::BoundingRectangle->new;
  
  $extent->update_xy($x1, $y1);
  $extent->update_xy($x2, $y2);

  my $extent2 = VCS::Visualize::BoundingRectangle->new;
  
  $extent2->update($extent);

=head1 DESCRIPTION

TODO

=head1 SEE ALSO

Mercurial 2.4 or newer required

=head1 AUTHOR

Juhász Péter, E<lt>kikuchiyo@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Juhász Péter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
