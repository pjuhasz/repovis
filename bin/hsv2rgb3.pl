#!/usr/bin/perl

use Modern::Perl;
use POSIX qw/floor/;
use Benchmark qw(:all);
use Inline C => 'DATA';
use Inline C => Config => CCFLAGS => '-O3 -msse3 -mfpmath=sse -march=core2 -ffast-math';

sub hsv2rgb_1 {
	my ( $h, $s, $v ) = @_;

	if ( $s == 0 ) {
		my $r = int($v*255);
		return ($r, $r, $r);
	}

	$h = ($h % 360) / 60;
	my $i = int($h);
	my $f = $h - $i;
	$v *= 255;
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

sub hsv2rgb_2 {
	my ( $h, $s, $v ) = @_;
	my ($r, $g, $b);

	if ( $s == 0 ) {
		$r = int($v*255);
		return ($r, $r, $r);
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
	return int($r*255), int($g*255), int($b*255);
}


sub hsv2rgb_3 {
	my ( $h, $s, $v ) = @_;

	if ( $s == 0 ) {
		my $r = int($v*255);
		return ($r, $r, $r);
	}

	$h = ($h % 360) / 60;
	my $i = int($h);
	my $f = $h - $i;
	$v *= 255;
	my $p = int( $v * ( 1 - $s ) );
	my $q = int( $v * ( 1 - $s * $f ) );
	my $t = int( $v * ( 1 - $s * ( 1 - $f ) ) );
	$v = int( $v );

	my @o = (
		$t, $p, $v, $t, $p, 0, 0, 0,
		$v, $p, $q, $v, $p
	);
	my $index = (($i & 1) << 3) + 2 - ($i >> 1);

	return @o[$index, $index+1, $index+2];
}


sub getrand {
	my $scale = shift // 1;
	my $decision = rand();
	if   ($decision > 0.9) { return $scale        }
	elsif($decision < 0.1) { return 0             }
	else                   { return $scale*rand() }
}


my $N = 2000000;
my @rand;
for (1..$N) {
	push @rand, [getrand(360), getrand(), getrand()];
}

if (0) {
for my $i (0..$N-1) {
	my $packed1 = pack 'C4', 0xff, hsv2rgb_1(@{$rand[$i]});
	#my $packed2 = pack 'C4', 0xff, hsv2rgb_2(@{$rand[$i]});
	#my $packed3 = pack 'C4', 0xff, hsv2rgb_3(@{$rand[$i]});
	my $packed2 = pack 'L>', hsv2rgb_c2(@{$rand[$i]});
	my $packed3 = pack 'L>', hsv2rgb_c(@{$rand[$i]});
	say join " ", $i, @{$rand[$i]}, map { unpack "H*", $_ } $packed1, $packed2, $packed3 if $packed1 ne $packed2 or $packed2 ne $packed3;
}
}

#exit;
cmpthese($N, {
	'1' => sub {
		state $i = 0;
		my $packed = pack 'C4', 0xff, hsv2rgb_1(@{$rand[$i]});
		$i++;
	},
	'2' => sub {
		state $i = 0;
		my $packed = pack 'C4', 0xff, hsv2rgb_2(@{$rand[$i]});
		$i++;
	},
	'c' => sub {
		state $i = 0;
		my $packed = pack 'L>', hsv2rgb_c(@{$rand[$i]});
		$i++;
	},
	'c2' => sub {
		state $i = 0;
		my $packed = pack 'L>', hsv2rgb_c2(@{$rand[$i]});
		$i++;
	},
	#'3' => sub {
	#	state $i = 0;
	#	my $packed = pack 'C4', 0xff, hsv2rgb_3(@{$rand[$i]});
	#	$i++;
	#}
});
__DATA__
__C__

static unsigned int rgb2int (unsigned char r, unsigned char g, unsigned char b) {
	return (0xff000000 | (r<<16) | (g<<8) | b);
}

unsigned int hsv2rgb_c (double h, double s, double v) {
	unsigned char p, q, t, iv;
	int i;
	double f, id;
	if ( s == 0.0 ) {
		iv = ((unsigned char) (v * 255)) & 0xff;
		return rgb2int(iv, iv, iv);
	}

	h = fmod(h, 360.0) / 60.0;
	id = floor(h);
	f = h - id;
	v *= 255;
	p = (unsigned char) (v * ( 1.0 - s ) );
	q = (unsigned char) (v * ( 1.0 - s * f ) );
	t = (unsigned char) (v * ( 1.0 - s * ( 1.0 - f ) ) );
	iv = (unsigned char) v;

	i = (int) id;
	switch (i) {
		case 0: return rgb2int(iv, t, p);
		case 1: return rgb2int(q, iv, p);
		case 2: return rgb2int(p, iv, t);
		case 3: return rgb2int(p, q, iv);
		case 4: return rgb2int(t, p, iv);
		case 5: return rgb2int(iv, p, q);
		default: return rgb2int(0, 0, 0);
	}
}

unsigned int hsv2rgb_c2 (double h, double s, double v) {
	unsigned char ret[13];
	int i, off;
	double f, id;
	if ( s == 0.0 ) {
		unsigned char iv = ((unsigned char) (v * 255)) & 0xff;
		return rgb2int(iv, iv, iv);
	}

	h = fmod(h, 360.0) / 60.0;
	id = floor(h);
	f = h - id;
	v *= 255;
	ret[1] = ret[4] = ret[9] = ret[12] = (unsigned char) (v * ( 1.0 - s ) );
	ret[10]                            = (unsigned char) (v * ( 1.0 - s * f ) );
	ret[0] = ret[3]                    = (unsigned char) (v * ( 1.0 - s * ( 1.0 - f ) ) );
	ret[2] = ret[8] = ret[11]          = (unsigned char) v;

	i = (int) id;

	off = ((i & 1) << 3) + 2 - (i >> 1);

	return rgb2int(ret[off], ret[off+1], ret[off+2]);
}
