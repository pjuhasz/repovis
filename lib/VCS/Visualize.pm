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
use FindBin;
use File::Copy;
use Storable qw/dclone/;

use VCS::Visualize::Repo;
use VCS::Visualize::BoundingRectangle;

use constant {
	FILE_PROCESSING_FAILED     => 0,
	FILE_PROCESSING_SUCCESSFUL => 1,
	FILE_PROCESSING_UNCHANGED  => 2,
	PT_X    => 0,
	PT_Y    => 1,
	PT_REV  => 2,
	PT_USER => 3,
	PT_FILE => 4,
	PT_N    => 5,
};

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

sub new {
	my $class = shift;
	my %args = @_;

	my $curve_module = $args{curve_module} // 'KochelCurve';
	croak "error: '$curve_module' is not a valid Math::PlanePath module, it must be one of the following:\n" .
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
		commit_rgb => 0xffff0000, # fully opaque red
		cached_n_to_xy => [],
		relative_anal => 0,
		verbose => $args{verbose},
		init_done => 0,
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

sub init {
	my ($self) = @_;

	print "processing revision graph\n" if $self->{verbose} > 0;

	$self->get_and_save_full_log();

	# TODO also read and check cached data to avoid redoing revs that are still valid
	$self->print_revs('revs.dat');
	$self->print_inc_file('params.inc');
	$self->copy_static_files();

	$self->{init_done} = 1;
}

sub analyze_all {
	my ($self) = @_;

	$self->init() if not $self->{init_done};

	$self->{relative_anal} = 1;

	for my $rev (@{$self->{revs}}) {
		$self->analyze_one_rev($rev->{node});
	}
}

sub analyze_one_rev {
	my ($self, $rev) = @_;

	$self->init() if not $self->{init_done};

	$rev //= $self->{repo}->current_rev();

	my $localrev = $self->{revs_by_node}{$rev}{localrev};
	print "processing revision $localrev:$rev\n" if $self->{verbose} > 0;
	$self->{max_numeric_id} = $localrev;

	# check if we have to use a different saved files data
	# we must use dclone here, because more than one children might depend on this data
	if ($self->{relative_anal} and defined $self->{revs_by_node}{$rev}{use_saved_data}) {
		my $which = $self->{revs_by_node}{$rev}{use_saved_data};
		$self->{files} = dclone $self->{revs_by_node}{$which}{saved_files};
	}

	# keep previously collected file data, but mark them invalid
	for my $file (keys %{$self->{files}}) {
		$self->{files}{$file}{status} = 0;
	}

	my $files = $self->{repo}->files(rev => $rev);

	$self->{lcnt} = 0;
	$self->{fcnt} = 0;

	my $global_extent = VCS::Visualize::BoundingRectangle->new;

	for my $file (@$files) {
		my $name = $file->{name};
		$self->do_one_file($file, $rev);
		my $ex = $self->{files}{$name}{extent};
		if (defined $ex) {
			$global_extent->update($ex);
			$self->{fcnt}++;
		}
	}
	
	$self->{xs} = $global_extent->xs();
	$self->{ys} = $global_extent->ys();

	$self->grids_from_coords($global_extent->{min_x}, $global_extent->{min_y});

	$self->trace_borders();
	
	$self->to_disk($rev);

	# check if we have to save the files data we've collected
	# we have to use deep cloning here!
	if ($self->{relative_anal} and $self->{revs_by_node}{$rev}{must_save_data}) {
		$self->{revs_by_node}{$rev}{saved_files} = dclone $self->{files};
	}
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
		my $H = 36 * rand() + $self->{filetypes}{$ext}{H};
		my $S = 0.4+0.2*rand();
		my $V = 0.7+0.2*rand();
		$self->{files}{$file}{H} = $H;
		$self->{files}{$file}{S} = $S;
		$self->{files}{$file}{V} = $V;
	}

	# cautiously mark it as invalid/not present for now
	$self->{files}{$file}{status} = 0;

	my ($success, $coord_list, $extent);
	if ($self->{relative_anal}) { # TODO
		print " processing $file_data->{status}   file $file\n" if $self->{verbose} > 1;

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
		if ($s eq 'modified') {
			($success, $coord_list, $extent) = $self->process_modified_file($file, $rev);
		}
		elsif ($s eq 'added') {
			($success, $coord_list, $extent) = $self->process_added_file($file, $rev);
		}
		elsif ($s eq 'unchanged') {
			($success, $coord_list, $extent) = $self->process_unchanged_file($file, $rev);
		}
		elsif ($s eq 'deleted') {
			return;
		}
		elsif ($s eq 'copied') { # TODO mark file label somehow
			$self->{files}{$file} = dclone $self->{files}{ $file_data->{source} };
			($success, $coord_list, $extent) = $self->process_modified_file($file, $rev, renamed => 1);
		}
		elsif ($s eq 'renamed') { # TODO mark file label somehow
			$self->{files}{$file} = $self->{files}{ $file_data->{source} };
			delete $self->{files}{ $file_data->{source} };
			($success, $coord_list, $extent) = $self->process_modified_file($file, $rev, renamed => 1);
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
		return if $file_data->{status} eq 'deleted';

		print " processing new file $file\n" if $self->{verbose} > 1;

		($success, $coord_list, $extent) = $self->process_file_blame($file, $rev);
	}
	return if $success == FILE_PROCESSING_FAILED;

	$self->{files}{$file}{status} = 1;
	return if $success == FILE_PROCESSING_UNCHANGED;

	# calculate center of the region occupied by this file, for the name label
	my ($xmean, $ymean) = (0, 0);
	for my $pt (@$coord_list) {
		$xmean += $pt->[PT_X];
		$ymean += $pt->[PT_Y];
	}

	# save data
	my $length = $self->{files}{$file}{length};
	$xmean /= $length;
	$ymean /= $length;
	$self->{files}{$file}{coords} = $coord_list;
	$self->{files}{$file}{center} = [$xmean, $ymean];
	$self->{files}{$file}{extent} = $extent;
}

sub process_file_blame {
	my ($self, $file, $rev) = @_;

	my $file_record = $self->{files}{$file};
	my $blame = $self->{repo}->blame(file => $file, rev => $rev);
	if (@$blame == 0) {
		return (FILE_PROCESSING_FAILED, undef, undef); # empty file, skip it
	}
	elsif ($blame->[0] =~ /binary file/) {
		$file_record->{binary} = 1; # skip it, but mark as binary for future use
		return (FILE_PROCESSING_FAILED, undef, undef);
	}
	else {
		# not binary (anymore? the old binary file might have been
		# replaced by a text file of the same name), clear the taint
		$file_record->{binary} = 0;
	}

	my $extent = VCS::Visualize::BoundingRectangle->new;

	$self->{files}{$file}{start_lcnt} = $self->{lcnt};

	my @coord_list;
	for my $line (@$blame) {
		if (my ($user, $id, $crev) = ($line =~ / \s* (.*?) \s+ (\d+) \s+ ([\da-f]+): /x)) {
			$self->{cached_n_to_xy}->[$self->{lcnt}] //= [ $self->{curve}->n_to_xy($self->{lcnt}) ];
			my ($x, $y) = @{ $self->{cached_n_to_xy}->[$self->{lcnt}] };

			$extent->update_xy($x, $y);

			push @coord_list, {
								X => $x,
								Y => $y,
								i => $id,
								u => $self->{users}{$user},
								f => $file_record,
								n => $self->{lcnt} - $file_record->{start_lcnt},
							};

			$self->{lcnt}++;
		}
	}

	$file_record->{end_lcnt} = $self->{lcnt}; # start_lcnt <= lcnt < end_lcnt
	$file_record->{length} = $file_record->{end_lcnt} - $file_record->{start_lcnt};

	return (FILE_PROCESSING_SUCCESSFUL, \@coord_list, $extent);
}

# TODO write this DRYer
sub process_modified_file {
	my ($self, $file, $rev, %args) = @_;

	my $file_record = $self->{files}{$file};
	my $diff = $self->{repo}->diff(file => $file, rev => $rev);

	if (@$diff == 0) {
		return $self->process_unchanged_file($file, $rev); # empty diff means no change
	}
	elsif ($diff->[0] =~ /binary/) {
		$file_record->{binary} = 1; # skip it, but mark as binary for future use
		return (FILE_PROCESSING_FAILED, undef, undef);
	}
	else {
		# not binary (anymore? the old binary file might have been
		# replaced by a text file of the same name), clear the taint
		$file_record->{binary} = 0;
	}

	my $extent = VCS::Visualize::BoundingRectangle->new;

	my $old_coord_list = $file_record->{coords};
	my $coord_list = [];

	my $old_length = $file_record->{end_lcnt} - $file_record->{start_lcnt};

	my $lcnt = $self->{lcnt};
	$file_record->{start_lcnt} = $lcnt;

	my $rev_data = $self->{revs_by_node}{$rev};
	my $user = $rev_data->{user};
	my $user_record = $self->{users}{$user};

	my $oldc = 0; my $newc = 0;

	for my $line (@$diff) {
		if (my ($l1, $s1, $l2, $s2) = ($line =~ /^\@\@ \s - (\d+),?(\d*) \s \+ (\d+),?(\d*) \s \@\@/x)) {
			$s1 = 1 if $s1 eq '';
			$s2 = 1 if $s2 eq '';

			# Update the coordinates for the lines before this hunk,
			# keep revision and user data.
			# According to diff's docs, "an empty hunk is considered to
			# start at the line that follows the hunk", so we have to 
			# special-case $s1 == 0 here.
			my $from = $oldc;
			my $to = $l1 - 1 - ($s1 > 0);
			for my $i ($from .. $to) {
				$self->{cached_n_to_xy}->[$lcnt] //= [ $self->{curve}->n_to_xy($lcnt) ];
				my ($x, $y) = @{ $self->{cached_n_to_xy}->[$lcnt] };

				$extent->update_xy($x, $y);

				$coord_list->[$newc] = $old_coord_list->[$oldc];
				$coord_list->[$newc][PT_X] = $x;
				$coord_list->[$newc][PT_Y] = $y;
				$coord_list->[$newc][PT_N] = $newc;
				$coord_list->[$newc][PT_FILE] = $file_record if $args{renamed};
				# keep the rest

				$newc++;
				$oldc++;
				$lcnt++;
			}

			# apply the hunk, drop $s1 lines, add $s2 lines with current rev and user
			for my $i (1..$s2) {
				$self->{cached_n_to_xy}->[$lcnt] //= [ $self->{curve}->n_to_xy($lcnt) ];
				my ($x, $y) = @{ $self->{cached_n_to_xy}->[$lcnt] };

				$extent->update_xy($x, $y);

				push @$coord_list, [
									$x,
									$y,
									$self->{max_numeric_id},
									$user_record,
									$file_record,
									$newc,
								];
				$newc++;
				$lcnt++;
			}
			$oldc += $s1;
		}
	}

	for my $i ($oldc .. $old_length-1) {
		$self->{cached_n_to_xy}->[$lcnt] //= [ $self->{curve}->n_to_xy($lcnt) ];
		my ($x, $y) = @{ $self->{cached_n_to_xy}->[$lcnt] };

		$extent->update_xy($x, $y);

		$coord_list->[$newc] = $old_coord_list->[$oldc];
		$coord_list->[$newc][PT_X] = $x;
		$coord_list->[$newc][PT_Y] = $y;
		$coord_list->[$newc][PT_N] = $newc;
		$coord_list->[$newc][PT_FILE] = $file_record if $args{renamed};

		# keep the rest

		$newc++;
		$oldc++;
		$lcnt++;
	}

	$self->{lcnt} = $lcnt;
	$file_record->{end_lcnt} = $lcnt; # start_lcnt <= lcnt < end_lcnt
	$file_record->{length} = $file_record->{end_lcnt} - $file_record->{start_lcnt};


	return (FILE_PROCESSING_SUCCESSFUL, $coord_list, $extent);
}

sub process_unchanged_file {
	my ($self, $file, $rev, %args) = @_;

	my $file_record = $self->{files}{$file};
	return (FILE_PROCESSING_FAILED, undef, undef) if $file_record->{binary};
	my $length = $file_record->{end_lcnt} - $file_record->{start_lcnt};
	return (FILE_PROCESSING_FAILED, undef, undef) if $length == 0;

	my $coord_list = $file_record->{coords};

	my $start = $self->{lcnt};
	$self->{lcnt} += $length;
	my $end = $self->{lcnt};

	# if the cached starting position of the file is the same as the current line count,
	# then the coordinate mapping has not changed so far in this rev,
	# so we don't have to recalculate coordinates for this file either,
	# we can happily bail out. We return a special flag so that the 
	# coords, extent, center etc. data don't have to be recalculated.
	# However, we do recalculate in case of moved/renamed files 
	# (TODO perhaps not necessary if the file was moved within the same dir?)
	if ($file_record->{start_lcnt} == $start and not $args{renamed}) {
		return (FILE_PROCESSING_UNCHANGED, $coord_list, $file_record->{extent});
	}

	my $extent = VCS::Visualize::BoundingRectangle->new;

	for my $lcnt ($start..$end-1) {
			$self->{cached_n_to_xy}->[$lcnt] //= [ $self->{curve}->n_to_xy($lcnt) ];
			my ($x, $y) = @{ $self->{cached_n_to_xy}->[$lcnt] };

			$extent->update_xy($x, $y);

			my $i = $lcnt - $start;
			$coord_list->[$i][PT_X] = $x;
			$coord_list->[$i][PT_Y] = $y;
			$coord_list->[$i][PT_FILE] = $file_record if $args{renamed};
			# keep the rest
	}

	$file_record->{start_lcnt} = $start;
	$file_record->{end_lcnt}   = $end; # start_lcnt <= lcnt < end_lcnt
	$file_record->{length} = $end - $start;

	return (FILE_PROCESSING_SUCCESSFUL, $coord_list, $extent);
}

sub process_added_file {
	my ($self, $file, $rev) = @_;

	my $file_record = $self->{files}{$file};
	my $line_count = $self->{repo}->line_count(rev => $rev, file => $file);
	if ($line_count == 0) {
		return (FILE_PROCESSING_FAILED, undef, undef); # empty file, skip it
	}
	elsif ($line_count == -1) {
		$file_record->{binary} = 1; # skip it, but mark as binary for future use
		return (FILE_PROCESSING_FAILED, undef, undef);
	}
	else {
		$file_record->{binary} = 0;
	}
	
	return (FILE_PROCESSING_FAILED, undef, undef) if $line_count == 0;

	my $rev_data = $self->{revs_by_node}{$rev};
	my $user = $rev_data->{user};

	# work around merges?
	if (defined $file_record and exists $file_record->{coords}) {
		my $olduser = $file_record->{coords}[0][PT_USER];
		if (defined $olduser and $olduser ne $user) {
			carp "file $file preserving old author $olduser over $user\n" if $self->{verbose} > 1;
			$user = $olduser;
		}
	}

	my $user_record = $self->{users}{$user};
	my $extent = VCS::Visualize::BoundingRectangle->new;

	my $start = $self->{lcnt};
	$self->{lcnt} += $line_count;
	my $end = $self->{lcnt};

	my @coord_list;
	for my $lcnt ($start..$end-1) {
			$self->{cached_n_to_xy}->[$lcnt] //= [ $self->{curve}->n_to_xy($lcnt) ];
			my ($x, $y) = @{ $self->{cached_n_to_xy}->[$lcnt] };

			$extent->update_xy($x, $y);

			push @coord_list, [
								$x,
								$y,
								$self->{max_numeric_id},
								$user_record,
								$file_record,
								$lcnt - $start,
							];
	}

	$file_record->{start_lcnt} = $start;
	$file_record->{end_lcnt} = $end; # start_lcnt <= lcnt < end_lcnt
	$file_record->{length} = $end - $start;

	return (FILE_PROCESSING_SUCCESSFUL, \@coord_list, $extent);
}

sub grids_from_coords {
	my ($self, $min_x, $min_y) = @_;

	$self->{grid}  = [];

	for my $file (keys %{$self->{files}}) {
		next if $self->{files}{$file}{status} == 0;
		for my $pt (@{$self->{files}{$file}{coords}}) {
			my $x = $pt->[PT_X];
			my $y = $pt->[PT_Y];
			$self->{grid}[ $y - $min_y + 1 ][ $x - $min_x + 1 ] = $pt;
		}
	}
}

sub trace_borders {
	my ($self) = @_;
	
	my @border;
	for my $y (0..($self->{ys}+1)) {
		for my $x (0..($self->{xs}+1)) {
			my $v = exists $self->{grid}[$y  ][$x  ] ? $self->{grid}[$y  ][$x  ][PT_FILE] : 0;
			my $r = exists $self->{grid}[$y  ][$x+1] ? $self->{grid}[$y  ][$x+1][PT_FILE] : 0;
			my $d = exists $self->{grid}[$y+1][$x  ] ? $self->{grid}[$y+1][$x  ][PT_FILE] : 0;
			push @border, [$x-0.5, $y-1.5, 0, 1]  if ($v != $r);
			push @border, [$x-1.5, $y-0.5, 1, 0]  if ($v != $d);
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

	my $numeric_id = $self->{revs_by_node}{$rev}{localrev};
	my $id = sprintf("%05d", $numeric_id);

	$self->print_binary_matrices('file_grid' => $id.'_f.dat', 'blame_grid' => $id.'_b.dat');
	$self->print_files($id.'_l.dat');
	$self->print_borders($id.'_c.dat');
	
	chdir($old_wd) or croak "error: can't chdir back to $old_wd";
}

# gnuplot recognizes this format as AVS
sub print_binary_matrices {
	my ($self, %args) = @_;

	# cargo cult code to pre-allocate buffers
	my $length = 4 * ($self->{xs} + 1) * ($self->{ys} + 1) + 8;
	
	my $outbuffer_f = "";
	vec($outbuffer_f, $length, 8)=0;
	$outbuffer_f = "";

	my $outbuffer_b = "";
	vec($outbuffer_b, $length, 8)=0;
	$outbuffer_b = "";

	my $transparent_white = pack 'L>', 0x00ffffff;
	my $commit_red = pack 'L>', $self->{commit_rgb};
	my $max_numeric_id = $self->{max_numeric_id};
	my @yrange = (1..$self->{ys}+1);
	my @xrange = (1..$self->{xs}+1);

	for my $y (@yrange) {
		my $row = $self->{grid}[$y];
		for my $x (@xrange) {
			if ( exists $row->[$x] ) {
				my $pt = $row->[$x];
				my $id = $pt->[PT_REV];
				my $fc = $pt->[PT_FILE];
				$outbuffer_f .= ($id == $max_numeric_id) ?
					$commit_red :
					pack 'C4', 0xff, hsv2rgb(
						$fc->{H},
						$fc->{S},
						$fc->{V} - 0.25*($pt->[PT_N]/$fc->{length})
					);

				$outbuffer_b .= pack 'C4', 0xff, hsv2rgb(
					$pt->[PT_USER]{H},
					0.03+0.93*$id/($max_numeric_id||1),
					1
				);
			}
			else {
				$outbuffer_f .= $transparent_white;
				$outbuffer_b .= $transparent_white;
			}
		}
	}

	open (my $fh_f, '>', $args{file_grid}) or croak "can't open $args{file_grid}";
	binmode($fh_f);
	print {$fh_f} pack 'L> L>', ($self->{xs}+1), ($self->{ys}+1);
	print {$fh_f} $outbuffer_f;
	close $fh_f;

	open (my $fh_b, '>', $args{blame_grid}) or croak "can't open $args{blame_grid}";
	binmode($fh_b);
	print {$fh_b} pack 'L> L>', ($self->{xs}+1), ($self->{ys}+1);
	print {$fh_b} $outbuffer_b;
	close $fh_b;
}

sub print_files {
	my ($self, $fn) = @_;

	open (my $fh, '>', $fn) or croak "can't open $fn";
	for my $file (sort keys %{$self->{files}}) {
		next if $self->{files}{$file}{status} == 0;
		my $basename = basename($file);
		say {$fh} join "\t", qq{"$basename"}, @{$self->{files}{$file}{center}}, $self->{files}{$file}{start_lcnt}, $self->{files}{$file}{end_lcnt};
	}
	close $fh;
}

sub print_borders {
	my ($self, $fn) = @_;

	open (my $fh, '>', $fn) or croak "can't open $fn";
	say {$fh} join "\t", @$_ for @{$self->{borders}};
	close $fh;
}

sub get_and_save_full_log {
	my ($self) = @_;

	my $revs = $self->{repo}->get_all_revs();

	# create a by node hash lookup too
	my %by_node = map { $_->{node} => $_ } @$revs; 

	# TODO perhaps this should go in the repo-specific module?
	# walking the graph to get merge nodes, nodes with more than one children etc.
	for my $this (@$revs) {
		# collect users who ever touched the repo
		$self->{users}{$this->{user}} //= {
			n => scalar keys %{$self->{users}},
			user_longname => $this->{user_longname},
		};
		
		# calculate which nodes this node is a child of
		$this->{children} //= [];
		for my $parent_node (@{$this->{parents}}) {
			my $parent = $by_node{$parent_node};
			push @{$parent->{children}}, $this->{node};
		}
	}

	# Set flags for relative analysis mode:
	# Normally we'd use the data in $self->{files} gathered during processing the 
	# previous rev as a base for processing unchanged files,
	# however, this doesn't work if the parent of the current rev is not the previous one.
	# Therefore for every node that has a child that is not the next one, we have to save
	# the files hashref, and when we process those children, we have to use the saved data 
	# instead of the usual files hashref (that contains data from the chronologically previous,
	# but topologically unrelated revision).
	# Here we mark those revisions that need to save their data after being processed,
	# and those that need to use saved data before starting processing.
	for my $i (1..$#$revs) {
		my $this   = $revs->[$i];
		my $prev   = $revs->[$i-1];
		my $parent = $by_node{ $this->{parents}[0] };

		# changeset data we get from the VCS is calculated relative to the first parent
		# FIXME is this true in git?
		if ($parent->{node} ne $prev->{node}) {
			$this->{use_saved_data} = $parent->{node};
			$parent->{must_save_data} = 1;
		}
		else {
			$this->{use_saved_data} = undef;
			$parent->{must_save_data} = 0;
		}
	}

	# assign pre-determined colors to users
	my $n_users = scalar keys %{$self->{users}};
	for my $u (sort { $self->{users}{$a}{n} <=> $self->{users}{$b}{n} } keys %{$self->{users}}) {
		$self->{users}{$u}{H} = 10 + 340 * $self->{users}{$u}{n}/$n_users;
	}

	$self->{revs} = $revs;

	$self->{revs_by_node} = \%by_node;
}

sub print_revs {
	my ($self, $fn) = @_;

	my $old_wd = getcwd();
	chdir($self->{cache_dir}) or croak "error: can't chdir to cache dir $self->{cache_dir}";

	open (my $fh, '>', $fn) or croak "can't open $fn";
	say {$fh} '#' . join "\t", qw/user_idx user_name rgb date localrev child_date child_localrev child_idx/;
	for my $rev (@{$self->{revs}}) {
		my $child_idx = 0;
		my $user_idx = $self->{users}{ $rev->{user} }{n};
		my $H = $self->{users}{ $rev->{user} }{H};
		my $S = 0.03+0.93; # solid, max saturation colors for now

		my ($r, $g, $b) = hsv2rgb($H, $S, 1);
		my $rgb = ($r<<16) + ($g<<8) + $b;

		for my $child_node (@{$rev->{children}}) {
			my $child = $self->{revs_by_node}{$child_node};
			say {$fh} join "\t", 
				$user_idx, $rev->{user}, $rgb, 
				$rev->{date}, $rev->{localrev},
				$child->{date}, $child->{localrev}, $child_idx++;
		}
	}
	close $fh;

	chdir($old_wd) or croak "error: can't chdir back to $old_wd";
}

# gather, then print various information about the repo as a script gnuplot can include
sub  print_inc_file {
	my ($self, $fn) = @_;

	my $old_wd = getcwd();
	chdir($self->{cache_dir}) or croak "error: can't chdir to cache dir $self->{cache_dir}";

	my %counts;
	for my $r (@{$self->{revs}}) {
		$counts{$r->{user}}++;
	}

	my %str;
	
	$str{mindate} = $self->{revs}[ 0]{date};
	$str{maxdate} = $self->{revs}[-1]{date};
	$str{maxrev}  = $#{$self->{revs}};
	$str{n_users} = scalar keys %{$self->{users}};
	for my $u (sort { $self->{users}{$a}{n} <=> $self->{users}{$b}{n} } keys %{$self->{users}}) {
		$str{names} .= $u . ' ';
		$str{hues}  .= $self->{users}{ $u }{H} . ' ';
		$str{counts} .= $counts{$u} . ' ';
	}
	
	open (my $fh, '>', $fn) or croak "can't open $fn";
	for my $key (sort keys %str) {
		my $value = ($str{$key} =~ /\D/) ? qq{"$str{$key}"} : $str{$key}; 
		say {$fh} "$key = $value";
	}
	close $fh;
}

sub copy_static_files {
	my ($self) = @_;

	# TODO figure out location after install
	my $sharedir  = File::Spec->catfile($FindBin::Bin, '..', 'share');
	my $targetdir = $self->{cache_dir};
	for my $basename (qw/repovis.plt timeline.plt matrix.plt/) {
		my $oldpath = File::Spec->catfile($sharedir,  $basename);
		my $newpath = File::Spec->catfile($targetdir, $basename);
		copy $oldpath, $newpath;
	}
}


sub hsv2rgb {
	my ( $h, $s, $v ) = @_;

	if ( $s == 0 ) {
		my $r = int($v*255.9);
		return ($r, $r, $r);
	}

	$h = ($h % 360) / 60;
	my $i = int($h);
	my $f = $h - $i;
	$v *= 255.9;
	my $p = int( $v * ( 1 - $s ) );
	my $q = int( $v * ( 1 - $s * $f ) );
	my $t = int( $v * ( 1 - $s * ( 1 - $f ) ) );
	$v = int( $v );

	if ( $i == 0 ) {
		return ($v, $t, $p);
	}
	elsif ( $i == 1 ) {
		return ($q, $v, $p);
	}
	elsif ( $i == 2 ) {
		return ($p, $v, $t);
	}
	elsif ( $i == 3 ) {
		return ($p, $q, $v);
	}
	elsif ( $i == 4 ) {
		return ($t, $p, $v);
	}
	else {
		return ($v, $p, $q);
	}
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

Mercurial 2.4 or newer required

=head1 AUTHOR

Juhász Péter, E<lt>kikuchiyo@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Juhász Péter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
