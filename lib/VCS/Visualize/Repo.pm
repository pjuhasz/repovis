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
	
	my $dir = $args{dir} // '.';
	
	for my $module (@modules) {
		my $class = 'VCS::Visualize::Repo::'.$module;
		my $find_root = $class.'::find_root';
		my $root_dir = $find_root->($dir);
		if (defined $root_dir) {
			load $class;
			return $class->new(%args, root_dir => $root_dir);
		}
	}
	croak "abort: no repository found in $dir\n";
}


1;
