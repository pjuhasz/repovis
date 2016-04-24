package VCS::Visualize::Repo;

use 5.010001;
use strict;
use warnings;
use Carp;


sub new {
	my %args = @_;
	my @modules = qw/Mercurial/;
	
	my $dir = $self->{dir} // '.';
	
	for my $module (@modules) {
		no strict 'ref';
		my $class = 'VCS::Visualize::Repo::'.$module;
		my $identify = $class.'::identify';
		my ($node, $numeric) = $identify->($dir);
		if (defined $node) {
			return $class->new(%args, orig_node => $node, orig_id => $numeric);
		}
	}
	croak "abort: no repository found in $dir\n";
}


1;
