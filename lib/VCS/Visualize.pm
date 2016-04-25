package VCS::Visualize;

use 5.010001;
use strict;
use warnings;

use Module::Load;
use List::Util qw/sum shuffle/;
use File::Basename;
use POSIX qw/floor/;

our $VERSION = '0.01';

our @curve_modules = (
		'PeanoCurve',             #3x3 self-similar quadrant
		'WunderlichSerpentine',   #transpose parts of PeanoCurve
		'HilbertCurve',           #2x2 self-similar quadrant
		'HilbertSpiral',          #2x2 self-similar whole-plane
		'ZOrderCurve',            #replicating Z shapes
		'WunderlichMeander',      #3x3 "R" pattern quadrant
		'BetaOmega',              #2x2 self-similar half-plane
		'AR2W2Curve',             #2x2 self-similar of four parts
		'KochelCurve',            #3x3 self-similar of two parts
		'DekkingCurve',           #5x5 self-similar, edges
		'DekkingCentres',         #5x5 self-similar, centres
		'CincoCurve',             #5x5 self-similar
);

sub new {
	my $class = shift;
	my %args = @_;
	
	my $self = {};
	
	bless $self, $class;
}

1;
__END__

=head1 NAME

VCS::Visualize - Visualize a software repository with space-filling curves

=head1 SYNOPSIS

  use VCS::Visualize;
  VCS::Visualize->new->run;

=head1 DESCRIPTION

TODO

=head1 SEE ALSO



=head1 AUTHOR

Juhász Péter, E<lt>kikuchiyo@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Juhász Péter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
