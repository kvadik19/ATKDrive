package LOGGY;

use Cwd 'abs_path';
use strict;
use Time::HiRes;
use Fcntl qw(:flock SEEK_END);
use vars qw($AUTOLOAD);

our $VERSION = '0.01';

my @options = qw(
			filename
			loglevel
			max_size
			log_cycle
		);

sub new {
	my $class = shift;
	my %init = @_;
	my %hash = map(( "$_" => $init{$_} ), @options);
	my $self = bless \%hash, $class;

	if ( !$self->{'filename'} ) {
		undef $self;
		return undef;
	} 

	$self->{'loglevel'} = $self->{'loglevel'} || 1;
	$self->{'log_cycle'} = $self->{'log_cycle'} || 0;
	$self->{'lastlog'} = '';
	$self->{'max_size'} = $self->{'max_size'} || 64;
	open( my $fh, ">> $self->{'filename'}" ) || die "$! $self->{'filename'}";
	$self->{'handler'} = $fh;
	chmod( 0664, $self->{'filename'});

	return $self
};
#############################
sub DESTROY {					# Close service
#############################
my $self = shift;
	close $self->{'handler'};
	return undef $self;
};
#############################
sub AUTOLOAD {					# Close service/store log record
#############################
my ( $self, @params ) = @_;
	if ( $AUTOLOAD =~/end|stop|close|destroy/i ) {
		return $self->DESTROY();
	} elsif( $AUTOLOAD =~/log|say|trace|debug/i ) {
		return $self->dump( @params );
	}
};
#############################
sub dump {					#  Locked Output to file
####################
my ( $self, $record, $loglevel, $opt ) = @_;
	$loglevel = 0 unless $loglevel;
	return '' if $loglevel > $self->{'loglevel'};

# my $buffered_mode = $|;		# Save previous buffer state
#   $| = 1;					# Set unbuffered

	$self->{'lastlog'} = $record;		# Store for any

	unless ( -e( $self->{'filename'}) && $self->{'handler'} ) {		# Just check if logdir exists?
		unless ( -d( substr( $self->{'filename'}, 0, rindex($self->{'filename'}, '/') ) ) ) {
			mkdir( substr( $self->{'filename'}, 0, rindex($self->{'filename'}, '/') ), 0755 );
		}
		open( my $new_fh, ">> $self->{'filename'}" ) 
			if -d( substr( $self->{'filename'}, 0, rindex($self->{'filename'}, '/') ) );
		$self->{'handler'} = $new_fh;
		chmod( 0664, $self->{'handler'});
	}

	$record =~ s/[\n\r]*$//s;
	unless ($opt) {		# Can prevent skipping long message
		if ( length( $record ) > $self->{'max_size'}*16 ) {
		$record = (substr($record, 0, $self->{'max_size'}*4)).
				'...TOO...LONG...SKIPPED...'.
				( substr($record, 0 - $self->{'max_size'}*4 ));
		}
	}			# Skip long messages

	$record = ( $self->timestr() )."\t$$\t$record\n";

	my $fh = $self->{'handler'};
	flock( $fh, LOCK_EX );
	seek( $fh, 0, SEEK_END );
	print $fh $record;
	flock( $fh, LOCK_UN );

	#   $| = $buffered_mode;		# Restore buffer mode

	# Check log rotation
	if ( ( tell( $fh ) > ($self->{'max_size'}*1024) ) &&
								-e( $self->{'filename'} ) ) {
		close( $fh );
		$self->rotate_log( $self->{'filename'} );
		open( my $new_fh, ">> $self->{'filename'}" );
		$self->{'handler'} = $new_fh;
		chmod( 0664, $self->{'handler'});
	}
	return $record;
};
#####################
sub rotate_log {		# Rotate log files, recursive. Nothing if success
#####################
my ( $self, $logname ) = @_;
	my $ret = '';
	my $next_lognum = '0';
	my $logbase = $logname;

	if ( $logbase =~ s/([\.\w]+)\.(\d+)$/$1/ ) {
		$next_lognum = $2 + 1;
	}

	if ( -e("$logbase.$next_lognum") ) {
		if ( $next_lognum >= $self->{'log_cycle'} ) {
			unlink("$logbase.$next_lognum");
		} else {
			$ret .= $self->rotate_log("$logbase.$next_lognum");
		}
	}

	if ( rename( $logname, "$logbase.$next_lognum") == 0 ) {
		$ret .= "ERROR:mv $logname to $logbase.$next_lognum $!\n";
	};
	return $ret;
};
#################
sub timestr {			#  Make string from serial date number
#################
my $self = shift;
	my $datetime = Time::HiRes::time();
	$datetime = sprintf( '%.2f', $datetime );

	my @date = localtime( $datetime );		#  Further need
	$date[6] = substr($datetime, index($datetime, '.')+1) if $datetime =~ /\./;

	$date[5]+=1900;
	$date[4]++;
	map { $date[$_] = "0" x ( 2 - length( $date[$_] ) ) . $date[$_] } (0, 1, 2, 3, 4);
	
	return "$date[3]-$date[4]-$date[5] $date[2]:$date[1]:$date[0].$date[6]";
};
1;
###############

=pod
Construct:
	filename	- Log file name
	loglevel	- Maximum level for logging
	max_size	- Size of log file in Kb
	log_cycle	- QTY of rotate log file

Typically Loglevels:
	0	Start/stop/fatal errors of execution
	1	Errors of companion process
	2	I/O messages of companions
	3	Internal events of execution
	4	More informative like step-by-step

Methods:
	new()
	dump($message, $log_level)		- Write message if log_level less or equal to loglevel
	log = dump
	destroy,end,stop

Properties:
	handler		- Opened logfile handler
	lastlog		- Last recorded message w/o time and pid fields

Abstract:
  my $logger = LOGGY->new(
		filename => "/var/log/console.log",
		loglevel => 2,
		max_size => 64,
		log_cycle => 4
		)

=cut
