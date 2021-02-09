package DATER;

use strict;
use utf8;
use vars qw($AUTOLOAD);
use XML::Simple;
# use Exporter qw(import);		#
use Encode;
use File::Copy;
use Fcntl qw(:flock SEEK_END);
use Date::Handler;

our $VERSION = '0.01';
our $date_names;
our $def_names = {'days'=>{ 'short'=>['Mo','Tu','We','Th','Fr','Sa','Su'],
					  'full'=>['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'],
					  },
			'months'=>{ 'short'=>['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'],
						'full'=>['January','February','March','April','May','June',
										'July','August','September','October','November','December']
					  },
			'relative' => {
						'today' => 'Today',
						'tomorrow' => 'Tomorrow',
						'yesterday' => 'Yesterday'
					  }
			};

our $our_timezone = `cat /etc/timezone` || 'Europe/Moscow';
$our_timezone =~ s/\s$//;

# our @EXPORT = qw( $date_names );

my @options = qw(
		lang
		logger
		config
		);
		
sub new {
  my $class = shift;
  my %init = @_;
  my %hash = map(( "$_" => $init{$_} ), @options);
  my $self = bless \%hash, $class;
  $self->select($self->{'lang'});
  return $self
};
#############################
sub DESTROY {					# Close service
#############################
my $self = shift;
  return undef $self;
};
#############################
sub AUTOLOAD {					# Make translated hash
#############################
my ($self, $lang) = @_;
  if ( $AUTOLOAD =~/end|stop|close|destroy/i ) {
	return $self->DESTROY();
  } else {			# Make some translation
	return $self->select($lang);
  }		# AUTOLOAD if
}
#############################
sub select {					# Read XML file
#############################
my ($self, $lang) = @_;
  $self->{'lang'} = $lang || 'en';
  if ( $self->{'define_update'} < (stat( $self->{'config'} ))[9] ) {
	$self->read();
  }
  $date_names = $self->{'dates'}->{$self->{'lang'}};
  $self->{'date_names'} = $date_names;
  $self->{'timezone'} = $our_timezone;
}
#############################
sub read {					# Read XML file
#############################
my ($self, ) = @_;

  if ( -e( $self->{'config'} ) ) {
	my $sig_die = $SIG{'__DIE__'};
	undef $SIG{'__DIE__'};
	  eval{ $self->{'dates'} = XMLin( $self->{'config'} ) };
	$SIG{'__DIE__'} = $sig_die;
	$self->{'define_update'} = (stat( $self->{'config'} ))[9];
	
	if ( exists($self->{'dates'}->{'en'}) ) {
	  unshift( @{$self->{'dates'}->{'en'}->{'days'}->{'short'}}, 
		$self->{'dates'}->{'en'}->{'days'}->{'short'}->[$#{$self->{'dates'}->{'en'}->{'days'}->{'short'}} ] );
	  unshift( @{$self->{'dates'}->{'en'}->{'days'}->{'full'}}, 
		$self->{'dates'}->{'en'}->{'days'}->{'full'}->[$#{$self->{'dates'}->{'en'}->{'days'}->{'full'}} ] );
	  pop( @{$self->{'dates'}->{'en'}->{'days'}->{'short'}} );
	  pop( @{$self->{'dates'}->{'en'}->{'days'}->{'full'}} );
			# Place Sunday first in English
	}
  }
  unless ( exists( $self->{'dates'}->{$self->{'lang'}} ) ) {
	if ( $self->{'lang'} =~ /^\w{2}$/ ) {
	  $self->{'dates'}->{$self->{'lang'}} = $def_names;
	  $self->write();
	}
  }
}
#############################
sub write {					# Store XML file
#############################
my ($self, ) = @_;
  if ( -e( $self->{'config'} ) ) {
	copy( $self->{'config'}, "$self->{'config'}.bkup" );
  }
  my $buffered = $|; $| = 1;					# Set unbuffered
  open( my $fh, "+>> $self->{'config'}" ) || warn "Open $!";
  flock( $fh, LOCK_EX ) || warn "Lock $!";
  truncate( $fh, 0 );				# Reset file contents
  print $fh '<?xml version="1.0" encoding="UTF-8"?>', "\n", XMLout( $self->{'dates'}, RootName=>'dates' );
  chmod( 0600, $fh);
  flock( $fh, LOCK_UN ) || warn "UNLock $!";
  close $fh;
  $| = $buffered;		# Restore buffer mode
  $self->{'define_update'} = time;
}
#############################
sub date_text {					# Backward <DD.MM.YYYY hh:mm:ss> date transformation
#############################
my ( $self, $time ) = @_;
$time = time unless $time;
my $date = Date::Handler->new( { date => $time, time_zone => $our_timezone } );
return encode_utf8(($date->Day())." ".
		  ($date_names->{'months'}->{'fullm'}->[$date->Month()-1])." ".
		  ($date->Year())
		  );
}
#############################
sub from_time {					# Backward <DD.MM.YYYY hh:mm:ss> date transformation
#############################
my ( $self, $rfc_string, $probe, $opts ) = @_;
my $str_date = [ split(/\s/, $rfc_string) ];
my $str_time = [ split(/\D/, $str_date->[1]) ];
$str_date = [ split(/\D/, $str_date->[0]) ];
my $date = Date::Handler->new( date => [ $str_date->[2], $str_date->[1] ,$str_date->[0], 
										  $str_time->[0], $str_time->[1], $str_time->[2]], time_zone => $our_timezone);
  return $date->$probe($opts) if $probe && $opts;
  return $date->$probe if $probe;
  return $date;
}
###############
1;

=pod
Serves multilanguage date names for months,days etc,(????)
Usage: use DATER		- Imports $date_names into procedure

$dater = DATER->new( lang => 'ln', config =>"/path/to/config/file.xml")

$dater->select('ln')			- Write desired language version into $date_names

=cut
