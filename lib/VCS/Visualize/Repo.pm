package VCS::Visualize::Repo;

use 5.010001;
use strict;
use warnings;
use Carp;
use Module::Load;

sub new {
	my $class = shift;
	my %args = @_;
	my @modules = qw/Mercurial/;
	
	my $dir = '.';
	if (ref $args{dirs} eq 'ARRAY' and scalar @{$args{dirs}} and defined $args{dirs}[0]) {
		$dir = $args{dirs}[0];
	}
	
	for my $module (@modules) {
		my $class = 'VCS::Visualize::Repo::'.$module;
		load $class;
		my $find_root = $class->can('find_root');
		my $root_dir = $find_root->($dir);
		if (length $root_dir) {
			return $class->new(%args, root_dir => $root_dir);
		}
	}
	die "abort: no repository found in '$dir'\n";
}


1;
