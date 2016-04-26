package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

use VCS::Visualize::Repo::Mercurial::CmdServer;

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
		dirs      => $args{dirs},
		exclude   => $args{exclude},
		include   => $args{include},
	};
	bless $self, $class;

	$self->{cmdsrv} = VCS::Visualize::Repo::Mercurial::CmdServer->new(root_dir => $self->{root_dir});

	$self->{orig_rev} = $self->current_rev;
	unless (ref $args{dirs} eq 'ARRAY' and scalar @{$args{dirs}} and defined $args{dirs}[0]) {
		$self->{dirs} = [$self->{root_dir}];
	}

	return $self;
}

sub current_rev {
	my ($self) = @_;
	my ($ret, $rev, $err) = $self->{cmdsrv}->runcommand(
		qw/hg log --cwd/, $self->{root_dir}, qw/--follow -l 1 --template {node}/);
	return $rev;
}

sub numeric_id {
	my ($self, $rev) = @_;
	my ($ret, $id, $err) = $self->{cmdsrv}->runcommand(
		qw/hg id -n --cwd/, $self->{root_dir}, '--rev', $rev);
	return $id;
}

sub files {
	my $self = shift;
	my @exclude = map { ('-X', $_) } @{$self->{exclude}};
	my @include = map { ('-I', $_) } @{$self->{include}};
	my @command = (qw/hg stat -madcn/, @exclude, @include, '--cwd', $self->{root_dir}, @{$self->{dirs}});
	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	return [ split /\n/, $out ];
}

sub blame {
	my ($self, $file) = @_;
	my @command = (qw/hg blame --cwd/, $self->{root_dir}, '-unc', $file);
	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	return [ split /\n/, $out ];
}

sub DESTROY {
	
}

1;
