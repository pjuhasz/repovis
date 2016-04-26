package VCS::Visualize;

use 5.010001;
use strict;
use warnings;

use Module::Load;
use List::Util qw/sum shuffle first/;
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
	(join ", ", @curve_modules) . "\n" if not first {$_ eq $curve_module} @curve_modules;
	my $curve_class = 'Math::PlanePath::'.$curve_module;
	load $curve_class;

	my $self = {
		curve => $curve_class->new(),
		repo  => VCS::Visualize::Repo->new(
			dirs    => $args{dirs},
			include => $args{include},
			exclude => $args{exclude},
		),
		files => {},
		filetypes => {},
		users => {},
		xs => -1,
		ys => -1,
		output_dir => '.repovis',
	};

	srand(1234);

	bless $self, $class;
}

sub analyze_one_rev {
	my ($self, $rev) = @_;

	$rev //= $self->{repo}->current_rev();

	$self->{max_numeric_id} = $self->{repo}->numeric_id($rev);

	my $files = $self->{repo}->files();

	$self->{lcnt} = 0;
	$self->{fcnt} = 0;

	my ($max_x, $max_y, $min_x, $min_y) = (-1000000, -1000000, 1000000, 1000000);

	for my $file (@$files) {
		$self->do_one_file($file);
		my $ex = $self->{files}{$file}{extent};
		if (defined $ex) {
			$max_x = $max_x > $ex->{max_x} ? $max_x : $ex->{max_x};
			$max_y = $max_y > $ex->{max_y} ? $max_y : $ex->{max_y};
			$min_x = $min_x < $ex->{min_x} ? $min_x : $ex->{min_x};
			$min_y = $min_y < $ex->{min_y} ? $min_y : $ex->{min_y};
			$self->{fcnt}++;
		}
	}
	
	$self->{xs} = $max_x-$min_x;
	$self->{ys} = $max_y-$min_y;

	$self->grids_from_coords($min_x, $min_y);

	$self->trace_borders();
	
	$self->to_disk($rev);
}

# private methods

sub do_one_file {
	my ($self, $file) = @_;

	my $blame = $self->{repo}->blame($file);
	return if @$blame == 0 or $blame->[0] =~ /binary file/;

	my ($ext) = ($file =~ /\.(\w+)$/);
	$ext //= $file;
	$self->{filetypes}{$ext}{H} //= 320 * rand();
	$self->{files}{$file}{H} //= 36 * rand() + $self->{filetypes}{$ext}{H};
	$self->{files}{$file}{S} //= 0.4+0.2*rand();
	$self->{files}{$file}{V} //= 0.7+0.2*rand();

	my ($max_x, $max_y, $min_x, $min_y) = (-1000000, -1000000, 1000000, 1000000);

	my @coord_list;
	for my $line (@$blame) {
		if (my ($user, $id, $crev) = ($line =~ / \s* (.*?) \s+ (\d+) \s+ ([\da-f]+): /x)) {
			$self->{users}{$user} //= {
				n => scalar(keys %{$self->{users}}),
				H => 360*rand(),
			};

			my ($x, $y) = $self->{curve}->n_to_xy($self->{lcnt});
			$max_x = $max_x > $x ? $max_x : $x;
			$max_y = $max_y > $y ? $max_y : $y;
			$min_x = $min_x < $x ? $min_x : $x;
			$min_y = $min_y < $y ? $min_y : $y;

			my $blame_rgb = hsv2rgb($self->{users}{$user}{H}, $id/$self->{max_numeric_id}, 1);
			my $file_rgb  = $id == $self->{max_numeric_id} ?
								hsv2rgb(360, 1, 1) : # red
								hsv2rgb( map { $self->{files}{$file}{$_} } qw/H S V/ );

			push @coord_list, [$x, $y, $file_rgb, $blame_rgb];

			$self->{lcnt}++;
		}
	}
	
	my ($xmean, $ymean) = (0, 0);
	for my $pt (@coord_list) {
		$xmean += $pt->[0];
		$ymean += $pt->[1];
	}
	
	$xmean /= scalar @coord_list;
	$ymean /= scalar @coord_list;
	$self->{files}{$file}{coords} = \@coord_list;
	$self->{files}{$file}{center} = [$xmean, $ymean];
	$self->{files}{$file}{extent} = {
		max_x => $max_x,
		max_y => $max_y,
		min_x => $min_x,
		min_y => $min_y,
	};
}

sub grids_from_coords {
	my ($self, $min_x, $min_y) = @_;

	for my $file (keys %{$self->{files}}) {
		for my $pt (@{$self->{files}{$file}{coords}}) {
			$self->{file_grid}[ $pt->[0]-$min_x+1][$pt->[1]-$min_y+1] = $pt->[2];
			$self->{blame_grid}[$pt->[0]-$min_x+1][$pt->[1]-$min_y+1] = $pt->[3];
		}
	}
}

sub trace_borders {
	my ($self) = @_;
	
	my @border;
	for my $y (0..($self->{ys}+1)) {
		for my $x (0..($self->{xs}+1)) {
			my $v = $self->{file_grid}[$x][$y]//0;
			push @border, [$x-0.5, $y-1.5, 0, 1]  if ($v != ($self->{file_grid}[$x+1][$y]//0));
			push @border, [$x-1.5, $y-0.5, 1, 0]  if ($v != ($self->{file_grid}[$x][$y+1]//0));
		}
	}

	@border = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @border;

	for my $i (0..$#border-1) {
		if ($border[$i][1] + $border[$i][3] == $border[$i+1][1] and $border[$i][0] == $border[$i+1][0] and $border[$i+1][2] == 0) {
			$border[$i+1][1] = $border[$i][1];
			$border[$i+1][3] = $border[$i][3] + 1;
			$border[$i][3] = 0;
		}
	}

	@border = grep { $_->[2] || $_->[3] } @border;

	@border = sort { $a->[1] <=> $b->[1] || $a->[0] <=> $b->[0] } @border;

	for my $i (0..$#border-1) {
		if ($border[$i][0] + $border[$i][2] == $border[$i+1][0] and $border[$i][1] == $border[$i+1][1] and $border[$i+1][3] == 0) {
			$border[$i+1][0] = $border[$i][0];
			$border[$i+1][2] = $border[$i][2] + 1;
			$border[$i][2] = 0;
		}
	}

	@border = grep { $_->[2] || $_->[3] } @border;

	$self->{borders} = \@border;
}

sub to_disk {
	my ($self, $rev) = @_;

	$self->print_binary_matrix($rev.'_f.dat', 'file_grid');
	$self->print_binary_matrix($rev.'_b.dat', 'blame_grid');
	$self->print_files($rev.'_l.dat');
	$self->print_borders($rev.'_c.dat');
}

# gnuplot recognizes this format as AVS
sub print_binary_matrix {
	my ($self, $fn, $key) = @_;
	
	open (my $fh, '>', $fn) or carp "can't open $fn";
	binmode($fh);

	print {$fh} pack 'L> L>', ($self->{xs}+1), ($self->{ys}+1);

	for my $y (1..$self->{ys}+1) {
		for my $x (1..$self->{xs}+1) {
			print {$fh} pack 'L>', ($self->{$key}[$x][$y] // 0xffffff); 
		}
	}
	close $fh;
}

sub print_files {
	my ($self, $fn) = @_;

	open (my $fh, '>', $fn) or carp "can't open $fn";
	for my $file (sort keys %{$self->{files}}) {
		my $basename = basename($file);
		say {$fh} join "\t", qq{"$basename"}, @{$self->{files}{$file}{center}} if defined $self->{files}{$file}{center};
	}
	close $fh;
}

sub print_borders {
	my ($self, $fn) = @_;

	open (my $fh, '>', $fn) or carp "can't open $fn";
	say {$fh} join "\t", @$_ for @{$self->{borders}};
	close $fh;
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
