#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use List::Util qw/shuffle/;
use Math::PlanePath::PeanoCurve;

my $peano       = Math::PlanePath::PeanoCurve->new;

my @a;
my ($max_x, $max_y, $min_x, $min_y) = (-1000000, -1000000, 1000000, 1000000);

my $lcnt = 0;

for my $region (1..100) {
	my @coord_list;
	for my $n (0 .. int(rand(2000))) {
		my ($x, $y) = $peano->n_to_xy($lcnt++);
		$max_x = $max_x > $x ? $max_x : $x;
		$max_y = $max_y > $y ? $max_y : $y;
		$min_x = $min_x < $x ? $min_x : $x;
		$min_y = $min_y < $y ? $min_y : $y;

		push @coord_list, [$x, $y];
	}

	for my $pt (@coord_list) {
		$a[$pt->[0]-$min_x+1][$pt->[1]-$min_y+1] = $region;
	}
}

my ($xs, $ys) = ($max_x-$min_x, $max_y-$min_y);

for my $y (1..$ys+1) {
	for my $x (1..$xs+1) {
		$a[$x][$y] //= 0;
		print $a[$x][$y] . " ";
	}
	print "\n";
}

print "\n\n";

my @border;
for my $y (0..$ys+1) {
	for my $x (0..$xs+1) {
		my $v = $a[$x][$y]//0;
		push @border, [$x-0.5, $y-1.5, 0, 1]  if ($v != ($a[$x+1][$y]//0));
		push @border, [$x-1.5, $y-0.5, 1, 0]  if ($v != ($a[$x][$y+1]//0));
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

say join "\t", @$_ for @border;

