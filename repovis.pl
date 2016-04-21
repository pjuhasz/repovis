#!/usr/bin/perl

# TODO comment
# TODO track extent of graph and write matrix instead of one long line of data per source line
#  (probably will have to lose easy support for different curves)
# TODO outline of file blobs in blame mode
# TODO separate file and blame mode:
#  single hg blame -unf for blame, 
#  get number of lines per file, divine changed lines from changeset for file mode
#  ... but will have to hg up to target rev for that anyway
# TODO js+html output? (yuck)

use strict;
use warnings;
use feature qw/say/;
use Module::Load;
use List::Util qw/sum shuffle/;
use File::Basename;
use Data::Dumper;
use POSIX qw/floor/;
use Cwd;
use Getopt::Long;

$Data::Dumper::Indent = 0;

my @modules;

BEGIN {
	load $_ for @modules = map { 'Math::PlanePath::'.$_ } (
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
}

my $target_rev;
GetOptions(
	'rev=s' => \$target_rev,
) or die "Usage: repovis.pl [-r] DIR"; 
my $rev_opt = '';
$rev_opt = "-r $target_rev" if defined $target_rev;

my @curves = map { $_->new() } @modules;

my $dir = $ARGV[0] // '.';

my $cwd = getcwd();
chdir $dir or die "Can't chdir to $dir";
my ($current_version_hash, $current_version_id) = split /\s+/, `hg id -in`;
chdir $cwd;

my @files = split /\n/, `hg stat -madcn $rev_opt $dir`;

srand(1234);

my @file_color_idxs = shuffle (0..(-1+scalar @files));

my $lcnt = 0;
my $fcnt = 0;
my %users;
my %files;
my %filetypes;

for my $file (@files) {
	my @blame = split /\n/, `hg blame -fun $rev_opt "$file"`;
	next if $blame[0] =~ /binary file/ or @blame == 0;

	my ($ext) = ($file =~ /\.(\w+)$/);
	$ext //= $file;
	$filetypes{$ext}{hue} //= 280 * rand();
	$files{$file}{hue} = 72 * rand() + $filetypes{$ext}{hue};

	my (@x, @y);
	for my $line (@blame) {
		if (my ($user, $id, $filename) = ($line =~ / \s* (.*?) \s+ (\d+) \s+ (.*?): /x)) {
			$users{$user} //= { n => scalar keys %users, hue => 360*rand() };
			my @line_coords;
			for my $c (0..$#curves) {
				my ($x, $y) = $curves[$c]->n_to_xy($lcnt);
				push @{$x[$c]}, $x;
				push @{$y[$c]}, $y;
				push @line_coords, $x, $y;
			}
			my $blame_rgb = hsv2rgb($users{$user}{hue}, $id/$current_version_id, 1);
			my $file_rgb  = $id == $current_version_id ?
								hsv2rgb(360, 1, 1) : # red
								hsv2rgb($files{$file}{hue}, 0.5, 0.8);
			say join "\t", $user, $users{$user}{n}, $id, $fcnt, $file_rgb, $blame_rgb, @line_coords;
			$lcnt++;
		}
	}
	for my $c (0..$#curves) {
		my $xmean = (sum @{$x[$c]}) / (scalar @{$x[$c]});
		my $ymean = (sum @{$y[$c]}) / (scalar @{$y[$c]});
		push @{$files{$file}{coords}}, $xmean, $ymean;
	}
	$fcnt++;
}

print "\n\n";

for my $file (sort keys %files) {
	my $basename = basename($file);
	say join "\t", qq{"$basename"}, @{$files{$file}{coords}};
}

##############

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
