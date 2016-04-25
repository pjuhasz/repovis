package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

sub find_root {
	my ($dir) = @_;
	return qx/hg --cwd "$dir" root/;
}

sub new {
	my $class = shift;
	my %args = @_;
	my $self = {
		root_dir  => $args{root_dir},
		dir       => $args{dir} // $args{root_dir},
		excluded  => $args{excluded}, 
		included  => $args{included},
	};
	bless $self, $class;
	$self->{orig_rev} = $self->current_rev;
	return $self;
}

sub current_rev {
	my ($self, $dir) = @_;
	return qx/hg log --cwd "$dir" --follow -l 1 --template '{node}'/;
}

sub files {
	my $self = shift;
	my $exclude = map { qq{-X "$_"} } @{$self->{excluded}};
	my $include = map { qq{-I "$_"} } @{$self->{included}};
	return [ split /\n/, qx/hg stat -madcn $exclude $include "$self->{dir}"/ ];
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
