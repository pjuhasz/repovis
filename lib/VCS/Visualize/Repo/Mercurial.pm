package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

sub find_root {
	my ($dir) = @_;
	my $root_dir = qx|hg --cwd "$dir" root 2> /dev/null|;
	chomp $root_dir;
	return $root_dir;
}

sub new {
	my $class = shift;
	my %args = @_;
	my $self = {
		root_dir  => $args{root_dir},
		dir       => $args{dir} // $args{root_dir},
		exclude   => $args{exclude},
		include   => $args{include},
	};
	bless $self, $class;
	$self->{orig_rev} = $self->current_rev;
	return $self;
}

sub current_rev {
	my ($self) = @_;
	my $rev = qx/hg log --cwd "$self->{root_dir}" --follow -l 1 --template '{node}'/;
	chomp $rev;
	return $rev;
}

sub numeric_id {
	my ($self, $rev) = @_;
	my $id = qx|hg id -n --cwd "$self->{root_dir}" --rev $rev|;
	chomp $id;
	return $id;
}

sub files {
	my $self = shift;
	my $exclude = join " ", map { qq{-X "$_"} } @{$self->{exclude}};
	my $include = join " ", map { qq{-I "$_"} } @{$self->{include}};
	my $command = qq{hg stat -madcn $exclude $include --cwd "$self->{root_dir}" "$self->{dir}"};
	return [ split /\n/, qx/$command/ ];
}

sub blame {
	my ($self, $file) = @_;
	my $command = qq{hg blame --cwd "$self->{root_dir}" -unc "$file"};
	return [ split /\n/, qx/$command/ ];
}

sub update {
	my ($self, $rev) = @_;
	qx/hg up --cwd "$self->{dir}" -r $rev/;
}

sub DESTROY {
	
}

1;
