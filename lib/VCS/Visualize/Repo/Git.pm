package VCS::Visualize::Repo::Git;

# Git 1.8.5+ because of -C
# TODO system with list instead of qx

use 5.010001;
use strict;
use warnings;

use Carp;

sub find_root {
	my ($dir) = @_;
	my $root_dir = qx|git -C "$dir" parse-rev --show-toplevel 2> /dev/null|;
	chomp $root_dir;
	return $root_dir;
}

sub new {
	my ($class, %args) = @_;
	my $self = {
		root_dir  => $args{root_dir},
		dirs      => $args{dirs},
		exclude   => $args{exclude},
		include   => $args{include},
	};
	bless $self, $class;

	$self->{orig_rev} = $self->current_rev;
	unless (ref $args{dirs} eq 'ARRAY' and scalar @{$args{dirs}} and defined $args{dirs}[0]) {
		$self->{dirs} = [$self->{root_dir}];
	}

	return $self;
}

sub current_rev {
	my ($self) = @_;
	my $rev = qx|git -C "$self->{root_dir}" rev-parse --short=12 HEAD|;
	chomp $rev;
	return $rev;
}

# TODO  node localrev user user_longname date desc branch p1node p2node p1rev p2rev
# git log ...
sub get_all_revs {
	my ($self) = @_;

	croak 'unimplemented';
}

# TODO
# git status ...
sub files {
	my ($self, %args) = @_;

	croak 'unimplemented';
}

# get the number of lines in a file in a specific revision
# git diff --stat ... ?
sub line_count {
	my ($self, %args) = @_;

	croak 'unimplemented';
}

# TODO git blame --porcelain, but needs heavy processing
sub blame {
	my ($self, %args) = @_;

	croak 'unimplemented';
}

# TODO 
# git diff ...
sub diff {
	my ($self, %args) = @_;

	croak 'unimplemented';
}


1;
