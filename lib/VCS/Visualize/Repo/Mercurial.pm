package VCS::Visualize::Repo::Mercurial;

use 5.010001;
use strict;
use warnings;

use VCS::Visualize::Repo::Mercurial::CmdServer;
use VCS::Visualize::Constants qw/:file_status :diff_flag/;
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
		qw/hg log --cwd/, $self->{root_dir}, qw/--follow -l 1 --template {node|short}/);
	return join "", @$out;
}

sub revlist {
	my ($self, $revspec) = @_;
	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(
		qw/hg log/,
		'--cwd', $self->{root_dir},
		'--rev', $revspec,
		qw/ --template {node|short}\n/);
	warn $err if $err;
	return $out;
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
		'--template', $template,
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
		qw/hg stat -marcC/,
		'--change', $rev,
		@exclude, @include,
		'--cwd', $self->{root_dir},
		@{$self->{dirs}}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);

	# use numeric constants instead of single letters to avoid confusion with git
	my %mapping = (
		M => FILE_STATUS_MODIFIED,
		A => FILE_STATUS_ADDED,
		R => FILE_STATUS_DELETED,
		C => FILE_STATUS_UNCHANGED,
	);

	my (@files, %copied_index);
	for my $line (@$out) {
		my $status_char = substr($line, 0, 1);
		my $name        = substr($line, 2);

		# rely on the fact that hg stat returns Added files first,
		# and with --copies, prints the source file for copied or renamed
		# files immediately after the "new" file (reported as Added).
		if ($status_char eq ' ') {
			$files[-1]{source} = $name;
			# mark it as copied, but we may have to correct this to renamed
			# if the same file is found among the removed ones
			$files[-1]{status} = FILE_STATUS_COPIED;
			$copied_index{$name} = $#files;
		}
		elsif ($status_char eq 'R' and exists $copied_index{$name}) {
			# again, we rely on Removed files being reported after Added ones
			# all this awkwardness wouldn't be necessary if hg reported
			# renamed and copied files in a more sensible way.
			$files[ $copied_index{$name} ]{status} = FILE_STATUS_RENAMED;
		}
		else {
			push @files, { name => $name, status => $mapping{$status_char} };
		}
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
	my $flag = 0;
	if (@$out and $out->[0] =~ /binary file$/) {
		$flag |= DIFF_FLAG_BINARY;
		$out->[0] = $flag;
	}
	else {
		unshift @$out, $flag;
	}
	return $out;
}

sub diff {
	my ($self, %args) = @_;
	my $rev = $args{rev} // $self->{orig_rev};
	my @command = (
		qw/hg diff --git -U 0/,
		'--cwd', $self->{root_dir},
		'--change', $rev,
		$args{file}
	);

	my ($ret, $out, $err) = $self->{cmdsrv}->runcommand(@command);
	warn $err if $err;

	# mangle output: throw away header lines up to the first @@ block,
	# but try to find rename and binary indications and return those first
	my $flags = 0;
	while ($out->[0] and substr($out->[0], 0, 1) ne '@') {
		my $line = shift @$out;
		$flags |= DIFF_FLAG_BINARY  if $line =~ /binary/i;
		$flags |= DIFF_FLAG_RENAMED if $line =~ /rename/i;
		$flags |= DIFF_FLAG_COPIED  if $line =~ /copied/i;
		last if $flags & DIFF_FLAG_BINARY;
	}
	unshift @$out, $flags;
	return $out;
}

sub DESTROY {
	
}

1;
