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
	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(
		qw/hg log --cwd/, $self->{root_dir}, qw/--follow -l 1 --template {node}/);
	return join "", @$out;
}

sub numeric_id {
	my ($self, %args) = @_;
	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(
		qw/hg id -n --cwd/, $self->{root_dir}, '--rev', $args{rev});
	return join "", @$out;
}

sub get_all_revs {
	my ($self) = @_;
	# \x1f is the ASCII field separator character
	# also, it would be nice to use the {children} template, but it's really slow
	# p1node, p2node and date formatting is hg 2.4+
	my $template =  join "\x1f", map { "{$_}" }
		qw/ node|short rev author|user author/, 
		'date(date|localdate, "%s")', 
		qw/ desc branch p1node|short p2node|short p1rev p2rev/;
	$template .= "\\n";
	my @command = (
		qw/hg log/,
		'--cwd', $self->{root_dir}, 
		qw/--follow --template/, $template,
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	warn $err if $err;

	my @revs;
	for my $line (@$out) {
		my (@fields) = split /\x1f/, $line;
		my $rev = {};
		# renaming fields here
		for (qw/ node localrev user user_longname date desc branch p1node p2node p1rev p2rev/) {
			$rev->{$_} = shift @fields;
		}

		$rev->{parents}[0]  = $rev->{p1node};
		$rev->{parents}[1]  = $rev->{p2node} if $rev->{p2rev} > -1;
		delete $rev->{$_} for qw/p1rev p2rev p1node p2node/;

		push @revs, $rev;
	}
	# sorting by date is unreliable (different timezones, rebases etc.)
	@revs = sort { $a->{localrev} <=> $b->{localrev} } @revs;
	return \@revs;
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
	for my $line (@$out) {
		my ($status, $name) = split / /, $line, 2;
		push @files, { name => $name, status => $status}; # TODO get earliest rev, split path here?
	}
	@files = sort { $a->{name} cmp $b->{name} } @files;
	return \@files;
}

# get the number of lines in a file in a specific revision
sub line_count {
	my ($self, %args) = @_;
	my $rev = $args{rev} // $self->{orig_rev};
	my @command = (
		qw/hg cat/,
		'--rev', $rev,
		'--cwd', $self->{root_dir},
		$args{file}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);

	return 0 if scalar @$out == 0;
	my $count;
	for (@$out) {
		return -1 if -1 != index $_, "\0"; # heuristic used by HG to check for binary files

		# Complication: one of the reasons why hg cat is fast 
		# is that it actually sends the file's content back in one chunk
		# (on the versions tested so far).
		# This means that CmdServer will also return it in one element, 
		# so we have to count the newlines ourselves.
		# Note that runcommand chomps the buffer, so we have to add the last newline back.
		$count += tr/\n// + 1;
	}
	return $count;
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
	warn $err if $err;
	return $out;
}

sub diff {
	my ($self, %args) = @_;
	my $rev = $args{rev} // $self->{orig_rev};
	my @command = (
		qw/hg diff -U 0/,
		'--cwd', $self->{root_dir},
		'--change', $rev,
		$args{file}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	warn $err if $err;
	return $out;
}

sub DESTROY {
	
}

1;
