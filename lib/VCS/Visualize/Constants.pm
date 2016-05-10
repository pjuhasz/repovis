package VCS::Visualize::Constants;

# modeled after http://www.perlmonks.org/?node_id=1072731

use 5.010001;
use strict;
use warnings;
use Scalar::Util qw/dualvar/;

my %constants;
BEGIN {
	%constants = (
		FILE_PROCESSING_FAILED     => 0,
		FILE_PROCESSING_SUCCESSFUL => 1,
		FILE_PROCESSING_UNCHANGED  => 2,

		PT_X    => 0,
		PT_Y    => 1,
		PT_REV  => 2,
		PT_USER => 3,
		PT_FILE => 4,
		PT_N    => 5,

		REV_PROCESSING_SKIP     => 0,
		REV_PROCESSING_FULL     => 1,
		REV_PROCESSING_RELATIVE => 2,

		FILE_STATUS_DELETED   => dualvar(0, 'deleted  '),
		FILE_STATUS_UNCHANGED => dualvar(1, 'unchanged'),
		FILE_STATUS_MODIFIED  => dualvar(2, 'modified '),
		FILE_STATUS_ADDED     => dualvar(3, 'added    '),
		FILE_STATUS_COPIED    => dualvar(4, 'copied   '),
		FILE_STATUS_RENAMED   => dualvar(5, 'renamed  '),

		DIFF_FLAG_BINARY  => 1,
		DIFF_FLAG_RENAMED => 2,
		DIFF_FLAG_COPIED  => 4,
	);
}

use constant \%constants;

use base 'Exporter';

our @EXPORT      = ();
our @EXPORT_OK   = keys(%constants);
our %EXPORT_TAGS = (
   all              => \@EXPORT_OK,
   default          => \@EXPORT,
   file_processing  => [ grep /^FILE_PROCESSING/, @EXPORT_OK ],
   pt               => [ grep /^PT/,              @EXPORT_OK ],
   rev_processing   => [ grep /^REV_PROCESSING/,  @EXPORT_OK ],
   file_status      => [ grep /^FILE_STATUS/,     @EXPORT_OK ],
   diff_flag        => [ grep /^DIFF_FLAG/,       @EXPORT_OK ],
);

1;
