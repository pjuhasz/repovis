#!/usr/bin/perl

# TODO comment
# TODO single hg blame -unf
# TODO unify user and blame mode, either with clever palette or hand-assigned colors
# TODO lines modified/added in current commit in file mode
# TODO outline of file blobs in blame mode

use strict;
use warnings;
use feature qw/say/;
use Module::Load;
use List::Util qw/sum/;
use File::Basename;
use Data::Dumper;

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

my @curves = map { $_->new() } @modules;

my $dir = $ARGV[0] // '.';

my @files = split /\n/, `hg stat -madcn $dir`;

my $lcnt = 0;
my $fcnt = 0;
my %users;
my %file_coords;

for my $file (@files) {
	my @blame = split /\n/, `hg blame -un "$file"`;
	next if $blame[0] =~ /binary file/ or @blame == 0;
	my (@x, @y);
	for my $line (@blame) {
		if (my ($user, $id) = ($line =~ / \s* (.*?) \s+ (\d+): /x)) {
			$users{$user} //= scalar keys %users;
			my @line_coords;
			for my $c (0..$#curves) {
				my ($x, $y) = $curves[$c]->n_to_xy($lcnt);
				push @{$x[$c]}, $x;
				push @{$y[$c]}, $y;
				push @line_coords, $x, $y;
			}
			say join "\t", $user, $users{$user}, $id, $fcnt, @line_coords;
			$lcnt++;
		}
	}
	for my $c (0..$#curves) {
		my $xmean = (sum @{$x[$c]}) / (scalar @{$x[$c]});
		my $ymean = (sum @{$y[$c]}) / (scalar @{$y[$c]});
		push @{$file_coords{$file}}, $xmean, $ymean;
	}
	$fcnt++;
}

print "\n\n";

for my $file (sort keys %file_coords) {
	my $basename = basename($file);
	say join "\t", qq{"$basename"}, @{$file_coords{$file}};
}
