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
		my $identify = $class.'::identify';
		my ($node, $numeric) = $identify->($dir);
		if (defined $node) {
			load $class;
			return $class->new(%args, orig_node => $node, orig_id => $numeric);
		}
	}
	croak "abort: no repository found in $dir\n";
}


1;
