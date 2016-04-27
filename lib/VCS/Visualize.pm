package VCS::Visualize;

use 5.010001;
use strict;
use warnings;

use Module::Load;
use List::Util qw/sum shuffle first/;
use File::Basename;
use POSIX qw/floor/;
use Carp;
use File::Spec;
use Cwd;

use VCS::Visualize::Repo;

our $VERSION = '0.01';

my @curve_modules = (
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

use constant FILE_GRID  => 0;
use constant BLAME_GRID => 1;

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
		cache_dir => $args{cache_dir},
		commit_rgb => 0xff0000, # red
		cached_n_to_xy => [],
		relative_anal => 0,
		quiet => $args{quiet},
	};

	srand(1234);

	bless $self, $class;
	
	$self->{cache_dir} //= File::Spec->catfile($self->{repo}->{root_dir}, '.repovis');
	
	if (not -e $self->{cache_dir}) {
		mkdir($self->{cache_dir}) or croak "error: can't create cache dir $self->{cache_dir}";
	}
	elsif (-e $self->{cache_dir} and not -d $self->{cache_dir}) {
		croak "error: can't create cache dir $self->{cache_dir} because a file with that name already exists"
	}
	
	return $self;
}

sub analyze_all {
	my ($self) = @_;

	my $revs = $self->{repo}->get_log();
	my $top = shift @$revs;
	$self->analyze_one_rev($top);

	$self->{relative_anal} = 1;
	for my $rev (@$revs) {
		$self->analyze_one_rev($rev);
	}
}

sub analyze_one_rev {
	my ($self, $rev) = @_;

	$rev //= $self->{repo}->current_rev();

	$self->{max_numeric_id} = 0+$self->{repo}->numeric_id(rev => $rev);

	# keep previously collected file data, but mark them invalid
	for my $file (keys %{$self->{files}}) {
		$self->{files}{$file}{status} = 0;
	}

	my $files = $self->{repo}->files(rev => $rev);

	$self->{lcnt} = 0;
	$self->{fcnt} = 0;

	my ($max_x, $max_y, $min_x, $min_y) = (-1000000, -1000000, 1000000, 1000000);

	for my $file (@$files) {
		my $name = $file->{name};
		$self->do_one_file($file, $rev);
		my $ex = $self->{files}{$name}{extent};
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

# extract and and process revision and committer information of one file
# in the specified revision, calculate coordinates of pixels on the 
# space-filling curve that correspond to this file's lines
# and update internal data structures
sub do_one_file {
	my ($self, $file_data, $rev) = @_;

	# get file name, check if we have a record for it already
	my $file = $file_data->{name};
	if (not exists $self->{files}{$file}) {
		# assign similar colors (hues) to known filetypes
		my ($ext) = ($file =~ /\.(\w+)$/);
		$ext //= $file;
		$self->{filetypes}{$ext}{H} //= 320 * rand();

		# assign a color to this file and use it on all plots in the future
		$self->{files}{$file}{rgb} = hsv2rgb(
				36 * rand() + $self->{filetypes}{$ext}{H},
				0.4+0.2*rand(),
				0.7+0.2*rand(),
			);
	}

	# cautiously mark it as invalid/not present for now
	$self->{files}{$file}{status} = 0;

	my ($success, $coord_list, $extent);
	if (0 and $self->{relative_anal}) { # TODO
		# in relative analysis mode we need to do different things with
		# added, modified, removed or unchanged files.
		# - for a modified file we want to process the full blame output
		# - for an added file, we know that all lines were added in this rev,
		#   so we don't run the blame command, just generate the list of 
		#   x/y/id/file/user structs from the line count range.
		# - for an unchanged file we update the coordinates 
		#   but keep the rest of the data
		# - removed files we mark as invalid, drop from processing
		my $s = $file_data->{status};
		if ($s eq 'M') {
			($success, $coord_list, $extent) = $self->process_modified_file($file, $rev);
		}
		elsif ($s eq 'A') {
			($success, $coord_list, $extent) = $self->process_added_file($file, $rev);

		}
		elsif ($s eq 'C') {
			($success, $coord_list, $extent) = $self->process_changed_file($file, $rev);
		}
		elsif ($s eq 'R') {
			return;
		}
		else {
			croak "error: unknown status '$s' while processing file $file in rev $rev";
		}
	}
	else {
		# in full analysis mode, when we can't rely on results of 
		# previous scans, we don't care about removed files because 
		# for our purposes they are simply not present in this revision,
		# but we want to get full blame output on 
		# added, modified or unchanged files.
		return if $file_data->{status} eq 'R';

		($success, $coord_list, $extent) = $self->process_modified_file($file, $rev);
	}
	return unless $success;
	
	# calculate center of the region occupied by this file, for the name label
	my ($xmean, $ymean) = (0, 0);
	for my $pt (@$coord_list) {
		$xmean += $pt->{X};
		$ymean += $pt->{Y};
	}
	
	# save data
	my $length = $self->{files}{$file}{end_lcnt} - $self->{files}{$file}{start_lcnt};
	$xmean /= $length;
	$ymean /= $length;
	$self->{files}{$file}{coords} = $coord_list;
	$self->{files}{$file}{center} = [$xmean, $ymean];
	$self->{files}{$file}{extent} = $extent;
	$self->{files}{$file}{status} = 1;
}

sub process_modified_file {
	my ($self, $file, $rev) = @_;

	my $blame = $self->{repo}->blame(file => $file, rev => $rev);
	return (0, undef, undef) if @$blame == 0 or $blame->[0] =~ /binary file/;

	my ($max_x, $max_y, $min_x, $min_y) = (-1000000, -1000000, 1000000, 1000000);

	$self->{files}{$file}{start_lcnt} = $self->{lcnt};

	my @coord_list;
	for my $line (@$blame) {
		if (my ($user, $id, $crev) = ($line =~ / \s* (.*?) \s+ (\d+) \s+ ([\da-f]+): /x)) {
			$self->{users}{$user} //= {
				H => 360*rand(),
			};

			$self->{cached_n_to_xy}->[$self->{lcnt}] //= [ $self->{curve}->n_to_xy($self->{lcnt}) ];
			my ($x, $y) = @{ $self->{cached_n_to_xy}->[$self->{lcnt}] };
			$max_x = $max_x > $x ? $max_x : $x;
			$max_y = $max_y > $y ? $max_y : $y;
			$min_x = $min_x < $x ? $min_x : $x;
			$min_y = $min_y < $y ? $min_y : $y;

			push @coord_list, {
								X => $x,
								Y => $y,
								i => $id,
								u => $user,
								f => $file,
							};

			$self->{lcnt}++;
		}
	}

	$self->{files}{$file}{end_lcnt} = $self->{lcnt}; # start_lcnt <= lcnt < end_lcnt

	my $extent = {
		   max_x => $max_x,
		   max_y => $max_y,
		   min_x => $min_x,
		   min_y => $min_y,
	};
	return (1, \@coord_list, $extent);
}

sub process_unchanged_file {
	my ($self, $file, $rev) = @_;

}

sub process_added_file {
	my ($self, $file, $rev) = @_;

}

sub grids_from_coords {
	my ($self, $min_x, $min_y) = @_;

	$self->{grid}  = [];

	for my $file (keys %{$self->{files}}) {
		next if $self->{files}{$file}{status} == 0;
		for my $pt (@{$self->{files}{$file}{coords}}) {
			my $x = $pt->{X};
			my $y = $pt->{Y};
			$self->{grid}[ $x - $min_x + 1 ][ $y - $min_y + 1 ] = $pt;
		}
	}
}

sub trace_borders {
	my ($self) = @_;
	
	my @border;
	for my $y (0..($self->{ys}+1)) {
		for my $x (0..($self->{xs}+1)) {
			my $v = exists $self->{grid}[$x  ][$y  ] ? $self->{grid}[$x  ][$y  ]{f} : '';
			my $r = exists $self->{grid}[$x+1][$y  ] ? $self->{grid}[$x+1][$y  ]{f} : '';
			my $d = exists $self->{grid}[$x  ][$y+1] ? $self->{grid}[$x  ][$y+1]{f} : '';
			push @border, [$x-0.5, $y-1.5, 0, 1]  if ($v ne $r);
			push @border, [$x-1.5, $y-0.5, 1, 0]  if ($v ne $d);
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

	my $old_wd = getcwd();
	chdir($self->{cache_dir}) or croak "error: can't chdir to cache dir $self->{cache_dir}";
	
	my $id = sprintf("%05d", $self->{repo}->numeric_id(rev => $rev));

	$self->print_binary_matrix($id.'_f.dat', FILE_GRID);
	$self->print_binary_matrix($id.'_b.dat', BLAME_GRID);
	$self->print_files($id.'_l.dat');
	$self->print_borders($id.'_c.dat');
	
	chdir($old_wd) or croak "error: can't chdir back to $old_wd";
}

# gnuplot recognizes this format as AVS
sub print_binary_matrix {
	my ($self, $fn, $which_grid) = @_;

	# cargo cult code to pre-allocate buffer
	my $outbuffer = "";
	my $length = ($self->{xs} + 1) * ($self->{ys} + 1) + 8;
	vec($outbuffer, $length, 8)=0;
	$outbuffer = "";
	
	open (my $fh, '>', $fn) or carp "can't open $fn";
	binmode($fh);

	print {$fh} pack 'L> L>', ($self->{xs}+1), ($self->{ys}+1);

	for my $y (1..$self->{ys}+1) {
		for my $x (1..$self->{xs}+1) {
			my $rgb = 0x00ffffff;
			if ( exists $self->{grid}[$x][$y] ) {
				my ($id, $user, $file) = map { $self->{grid}[$x][$y]{$_} } qw/i u f/;
				if ($which_grid == FILE_GRID) {
					$rgb = $id == $self->{max_numeric_id} ?
							$self->{commit_rgb} :
							$self->{files}{$file}{rgb};
				}
				else {
					$rgb = hsv2rgb(
						$self->{users}{$user}{H},
						0.03+0.93*$id/($self->{max_numeric_id}||1),
						1
					);
				}
				$rgb |= 0xff000000;
			}
			$outbuffer .= pack 'L>', $rgb;
		}
	}

	print {$fh} $outbuffer;
	close $fh;
}

sub print_files {
	my ($self, $fn) = @_;

	open (my $fh, '>', $fn) or carp "can't open $fn";
	for my $file (sort keys %{$self->{files}}) {
		next if $self->{files}{$file}{status} == 0;
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
