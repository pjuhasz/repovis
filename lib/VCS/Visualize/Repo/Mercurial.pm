package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

use VCS::Visualize::Repo::Mercurial::CmdServer;
use Carp;

sub find_root {
	my ($dir) = @_;
	my $root_dir = qx|hg --cwd "$dir" root 2> /dev/null|;
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
	my ($self, %args) = @_;
	my ($ret, $id, $err) = $self->{cmdsrv}->runcommand(
		qw/hg id -n --cwd/, $self->{root_dir}, '--rev', $args{rev});
	return $id;
}

# TODO template with more info
sub get_log {
	my ($self) = @_;
	my @command = (
		qw/hg log/,
		'--cwd', $self->{root_dir}, 
		qw/--follow --template/, "{rev}\n"
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	return [] unless defined $out;
	return [ split /\n/, $out ];
}

sub files {
	my ($self, %args) = @_;
	my @exclude = map { ('-X', $_) } @{$self->{exclude}};
	my @include = map { ('-I', $_) } @{$self->{include}};
	my $rev = $args{rev} // $self->{orig_rev};
	my @command = (
		qw/hg stat -marc/,
		'--change', $rev,
		@exclude, @include,
		'--cwd', $self->{root_dir},
		@{$self->{dirs}}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);

	my (@files);
	for my $line (split /\n/, $out) {
		my ($status, $name) = split / /, $line, 2;
		push @files, { name => $name, status => $status}; # TODO get earliest rev, split path here?
	}
	@files = sort { $a->{name} cmp $b->{name} } @files;
	return \@files;
}

sub blame {
	my ($self, %args) = @_;
	my $rev = $args{rev} // $self->{orig_rev};
	my @command = (
		qw/hg blame -unc/,
		'--cwd', $self->{root_dir}, 
		'--rev', $rev,
		$args{file}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	return [] unless defined $out;
	return [ split /\n/, $out ];
}

sub DESTROY {
	
}

1;
