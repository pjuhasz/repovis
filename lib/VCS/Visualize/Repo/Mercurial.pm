package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

sub identify {
	my ($dir) = @_;
	my $res = qx/hg --cwd "$dir" --follow -l 1 --template {node}\x1f{rev}/; # \x1f{tags}\x1f{branches}\x1f{bookmarks}
	return unless $res;
	return split /\x1f/, $res;
}

sub new {
	my $class = shift;
	my %args = @_;
	my $self = {
		dir       => $args{dir},
		excluded  => $args{excluded}, 
		included  => $args{included},
		orig_node => $args{orig_node},
	};
	bless $self, $class;
}

sub files {
	my $self = shift;
	return [ split /\n/, qx/hg stat -madcn "$self->{dir}"/ ];
}

sub blame {
	my ($self, $file) = @_;
	return [ split /\n/, qx/hg blame -fun "$file"/ ];
}

sub update {
	my ($self, $rev) = @_;
	qx/hg up --cwd "$self->{dir}" -r $rev/;
}

sub DESTROY {
	
}

1;
