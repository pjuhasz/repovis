package VCS::Visualize::Repo::Mercurial::CmdServer;

use 5.010001;
use strict;
use warnings;
use POSIX qw/ WNOHANG WEXITSTATUS WIFEXITED WTERMSIG WIFSIGNALED WUNTRACED /;
use IPC::Open2 qw/open2/;
use Carp;

sub new {
	my $class = shift;
	my %args = @_;

	my $self = {};

	my $root_dir = $args{root_dir} // '.';
	my @command = (qw/hg serve --cmdserver pipe -R/, qq{"$root_dir"});

	$self->{root_dir} = $root_dir;
	
	bless $self, $class;

	$self->{pid} = open2($self->{readfh}, $self->{writefh}, @command) or croak "Can't open hg cmdserver";

	eval {
		$self->_get_hello();
		1;
	} or do {
		eval {
			my $e = $@;
			$self->close();
			die $e;
		} or do {
			croak "error in handshake with hg cmdserver: $@";
		};
	};

	return $self;
}

sub read {
	my $self = shift;

	# use aliased data in @_ to prevent copying
	return $self->{readfh}->sysread( @_ );
}
 
# always use aliased $_[0] as buffer to prevent copying
# call as get_chunk( $buf )
sub get_chunk {
	my $self = shift;

	# catch pipe errors from child
	local $SIG{'PIPE'} = sub { croak( "SIGPIPE on read from server\n" ) };

	my $nr = $self->read( $_[0], 5 );
	croak( "error reading chunk header from server: $!\n" )
		unless defined $nr;

	$nr > 0
		or croak( "unexpected end-of-file getting chunk header from server\n" );

	my ( $ch, $len ) = unpack( 'A[1] l>', $_[0] );

	if ( $ch =~ /IL/ ) {
		return $ch, $len;
	}

	else {
		$self->read( $_[0], $len ) == $len
			or croak(
				"unexpected end-of-file reading $len bytes from server channel $ch\n"
			);
		return $ch;
	}

}
 
sub close {
	my $self = shift;

	# if the command server was created, see if it's
	# still hanging around
	if ( $self->{pid} ) {
		 $self->{writefh}->close;
		 _check_on_child( $self->{pid}, status => 'exit', wait => 1 );
		 delete $self->{pid};
	}

	return;
}
 
sub _check_on_child {
	my $pid = shift;
	my %opt = @_;

	my $flags = WUNTRACED | ( $opt{wait} ? 0 : WNOHANG );
	my $status = waitpid( $pid, $flags );

	# if the child exited, it had better have been a clean death;
	# anything else is not ok.
	if ( $pid == $status ) {
		 die( "unexpected exit of child with status ",
			WEXITSTATUS( $? ), "\n" )
		  if WIFEXITED( $? ) && WEXITSTATUS( $? ) != 0;

		die( "unexpected exit of child with signal ",
			WTERMSIG( $? ), "\n" )
		  if WIFSIGNALED( $? );
	}

	if ( $opt{status} eq 'alive' ) {
		die( "unexpected exit of child\n" )
			if $pid == $status || -1 == $status;
	}

	elsif ( $opt{status} eq 'exit' ) {
		 # is the child still alive
		die( "child still alive\n" )
			 unless $pid == $status  || -1 == $status;
	}
	else {
		die( "internal error: unknown child status requested\n" );
	}
}

# call as $self->write( $buf, [ $len ] )
sub write {
	my $self = shift;
	my $len = @_ > 1 ? $_[1] : length( $_[0] );
	$self->{writefh}->syswrite( $_[0], $len ) == $len
		or croak( "error writing $len bytes to server\n" );
}
 
sub writeblock {
	my $self = shift;

	$self->write( pack( "N/a*", $_[0] ) );
}
 
sub _get_hello {
	my $self = shift;

	my $buf;
	my $ch = $self->get_chunk( $buf );

	croak( "corrupt or incomplete hello message from server\n" )
		unless $ch eq 'o' && length $buf;

	my $requested_encoding = $self->{encoding} // undef;
	delete $self->{encoding};

	for my $item ( split( "\n", $buf ) ) {
		my ( $field, $value ) = $item =~ /([a-z0-9]+):\s*(.*)/;
		if ( $field eq 'capabilities' ) {
			$self->{capabilities} = { map { $_ => 1 } split( ' ', $value ) };
		}
		elsif ( $field eq 'encoding' ) {
			croak( sprintf "requested encoding of %s; got %s",
				$requested_encoding, $value )
			  if defined $requested_encoding && $requested_encoding ne $value;
			$self->{encoding} = $value;
		}

		# ignore anything else 'cause we don't know what it means
	}

	# make sure hello message meets minimum standards
	croak( "server did not provide capabilities?\n" )
		unless exists $self->{capabilities};

	croak( "server is missing runcommand capability\n" )
		unless exists $self->{capabilities}->{runcommand};

	croak( "server did not provide encoding?\n" )
		unless exists $self->{encoding};

	return;
}
 
sub getencoding {
	my $self = shift;

	$self->write( "getencoding\n" );

	my $buffer;
	my ( $ch, $len ) = $self->get_chunk( $buffer );

	croak( "unexpected return message for getencoding on channel $ch\n" )
		unless $ch eq 'r' && length( $buffer );

	return $buffer;

}
 
# $server->runcommand( $command, @args )
sub runcommand {
	my $self = shift;

	my $hgcommand = shift; # assuming 'hg'

	$self->write( "runcommand\n" );
	$self->writeblock( join( "\0", @_ ) );

	# read from server until a return channel is specified
	my $buffer;
	my ($error, $output);
	while ( 1 ) {
		my ( $ch, $len ) = $self->get_chunk( $buffer );
		if ( $ch eq 'e' ) {
			$error .= $buffer;
		}
		elsif( $ch eq 'o' ) {
			$output .= $buffer;
		}
		elsif ( $ch eq 'r' ) {
			state $length_exp = length( pack( 'l>', 0 ) );
			croak( sprintf "incorrect message length (got %d, expected %d)",
				length( $buffer ), $length_exp )
			  if length( $buffer ) != $length_exp;

			my $ret = unpack( 'l>', $buffer );
			return ($ret, $output, $error);
		}
		# TODO handle input, debug? provide callbacks for output for line-based processing?
		elsif ( $ch =~ /[[:upper:]]/ ) {

			croak( "unexpected data on required channel $ch\n" );
		}
	}

}

sub DESTROY {
	$_[0]->close();
}

1;
