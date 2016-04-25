package VCS::Visualize;

use 5.010001;
use strict;
use warnings;

use Module::Load;
use List::Util qw/sum shuffle any/;
use File::Basename;
use POSIX qw/floor/;
use Carp;

use VCS::Visualize::Repo;

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

	my $curve_module = $args{curve_module} // 'AR2W2Curve';
	carp "error: '$curve_module' is not a valid Math::PlanePath module, it must be one of the following:\n" .
	(join ", ", @curve_modules) . "\n" if not any {$_ eq $curve_module} @curve_modules;
	my $curve_class = 'Math::PlanePath::'.$curve_module;
	load $curve_class;

	my $self = {
		curve => $curve_class->new(),
		repo  => VCS::Visualize::Repo->new(
			dir     => $args{dir},
			include => $args{include},
			exclude => $args{exclude},
		),
		files => {},
		filetypes => {},
		users => {},
	};

	srand(1234);

	bless $self, $class;
}

sub analyze_one_rev {
	my ($self, $rev) = @_;

	$rev //= $self->{repo}->current_rev();

	my $max_numeric_id = $self->{repo}->numeric_id($rev);

	my $files = $self->{repo}->files();

	my @file_color_idxs = shuffle (0..(-1+scalar @$files));

	my $lcnt = 0;
	my $fcnt = 0;

	for my $file (@$files) {
		my $blame = $self->{repo}->blame($file);
		next if $blame->[0] =~ /binary file/ or @$blame == 0;

		my ($ext) = ($file =~ /\.(\w+)$/);
		$ext //= $file;
		$self->{filetypes}{$ext}{hue} //= 280 * rand();
		$self->{files}{$file}{hue} = 72 * rand() + $self->{filetypes}{$ext}{hue};

		my (@x, @y);
		for my $line (@$blame) {
			if (my ($user, $id, $crev) = ($line =~ / \s* (.*?) \s+ (\d+) \s+ ([\da-f]+): /x)) {
				$self->{users}{$user} //= { n => scalar keys %{$self->{users}}, hue => 360*rand() };

				my ($x, $y) = $self->{curve}->n_to_xy($lcnt);
				push @x, $x;
				push @y, $y;

				my $blame_rgb = hsv2rgb($self->{users}{$user}{hue}, $id/$max_numeric_id, 1);
				my $file_rgb  = $id == $max_numeric_id ?
									hsv2rgb(360, 1, 1) : # red
									hsv2rgb($self->{files}{$file}{hue}, 0.5, 0.8);
				say join "\t", $user, $self->{users}{$user}{n}, $id, $fcnt, $file_rgb, $blame_rgb, $x, $y;
				$lcnt++;
			}
		}
		my $xmean = (sum @x) / (scalar @x);
		my $ymean = (sum @y) / (scalar @y);
		push @{$self->{files}{$file}{coords}}, $xmean, $ymean;

		$fcnt++;
	}

	print "\n\n";

	for my $file (sort keys %{$self->{files}}) {
		my $basename = basename($file);
		say join "\t", qq{"$basename"}, @{$self->{files}{$file}{coords}};
	}
}

sub hsv2rgb {
	my ( $h, $s, $v ) = @_;
	my ($r, $g, $b);

	if ( $s == 0 ) {
		($r, $g, $b) = ($v, $v, $v);
		return (int($r*255.9)<<16) + (int($g*255.9)<<8) + int($b*255.9);
	}

	$h = ($h % 360) / 60;
	my $i = floor( $h );
	my $f = $h - $i;
	my $p = $v * ( 1 - $s );
	my $q = $v * ( 1 - $s * $f );
	my $t = $v * ( 1 - $s * ( 1 - $f ) );

	if ( $i == 0 ) {
		($r, $g, $b) = ( $v, $t, $p);
	}
	elsif ( $i == 1 ) {
		($r, $g, $b) = ( $q, $v, $p);
	}
	elsif ( $i == 2 ) {
		($r, $g, $b) = ( $p, $v, $t);
	}
	elsif ( $i == 3 ) {
		($r, $g, $b) = ( $p, $q, $v);
	}
	elsif ( $i == 4 ) {
		($r, $g, $b) = ( $t, $p, $v);
	}
	else {
		($r, $g, $b) = ( $v, $p, $q);
	}
	return (int($r*255.9)<<16) + (int($g*255.9)<<8) + int($b*255.9);
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
