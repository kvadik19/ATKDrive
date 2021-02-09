# UNIX socket communication package
# For use with webdrive

package TALKS;

use Cwd 'abs_path';
use strict;
use IO::Socket;
use IO::Select;
use POSIX;
use IPC::Open2;
use Mojo::JSON qw(decode_json encode_json);
use vars qw($AUTOLOAD);

# use Data::Dumper;

our $use_zlib = 1;
eval( 'use Compress::Zlib' );
$use_zlib = 0 if $@;
our $use_zlib = 0;

our $VERSION = '0.03';
our $HEADER_LEN = 40;

my @options = qw(
		name
		socket
		location
		listen
		try
		timeout
		logger
		buffsize
		master
		parent
		parent_sock
		);

my $master = abs_path( $0 );
my $script_location = substr( $master, 0, rindex( $master, '/') );

sub new {
	my $class = shift;
	my %init = @_;
	my %hash = map(( "$_" => $init{$_} ), @options);
	my $self = bless \%hash, $class;

	if ( !$self->{'socket'} ) {
		undef $self;
		return undef;
	} 

	$self->{'socket'} = abs_path( $self->{'socket'} );
	$self->{'listen'} = $self->{'listen'} || 5;
	$self->{'try'} = $self->{'try'} || 3;
	$self->{'from'} = '';
	$self->{'timeout'} = $self->{'timeout'} || 3;
	$self->{'socks_path'} = substr( $self->{'socket'}, 0, rindex( $self->{'socket'}, '/') );
	$self->{'logger'} = $self->{'logger'} || bless { 'dump' => sub {}, 'debug' => sub {} };		# ????
	$self->{'buffsize'} = 128*1024;		# Equals to FcgidMaxRequestLen - obsolete. Now based on UNIX size 64K
	$script_location = $self->{'location'} || $script_location;

	$self->restart();

	$self->{'self_socks'} = [];
	$self->{'known_socks'} = [];
	$self->rescan_daemon();			#  if $self->{'master'};

	$self->{'parent_sock'} = $self->{'parent_sock'} || $self->{'parent'} || [];
	$self->{'delayed'} = [];			# Obsolete?
	
	return undef unless -d($self->{'socks_path'}) && -w($self->{'socks_path'});
	$self->cleanup();			# Remove unused socket files
	return $self;
};
#############################
sub restart {					# Cleanup connections alias
#############################
my $self = shift;
	$self->sock_close();
	$self->sock_open()
};
#############################
sub sock_close {					# Close socket
#############################
my $self = shift;
	if ( $self->{'server'} ) {
		$self->{'logger'}->debug("Kill socket $self->{'socket'}", 3);
		$self->{'server'}->shutdown(0);
		$self->{'server'}->close();
		unlink( $self->{'socket'} ) if -e( $self->{'socket'} );
		undef $self->{'server'};
	}
}
#############################
sub sock_open {					# Open socket
#############################
my $self = shift;
	unless ( $self->{'server'} ) {
		$@ = '';		# Reset errors
		$self->{'socket'} = "$self->{'socks_path'}/$$";
		$self->{'logger'}->debug("Fire socket $self->{'socket'}", 3);
		$self->{'server'} = IO::Socket::UNIX->new(
			Local=>$self->{'socket'}, 
			Proto=>0, 
			Type=>SOCK_DGRAM, 
			Listen=>$self->{'listen'});		# Create socket
		if ( $@ ) {			# Check if SERVER socket success
		$self->{'logger'}->debug("Create IN socket:$@", 1);
		undef $self;
		} else {
		$self->{'ready'} = IO::Select->new( $self->{'server'} );
		}			# Check if IN socket success
	}
}
#############################
sub DESTROY {					# Cleanup connections alias
#############################
my $self = shift;
	$self->sock_close();
	return undef $self;
};
#############################
sub AUTOLOAD {					# Close service
#############################
my $self = shift;
	if ( $AUTOLOAD =~ /end|stop|close|destroy|terminate/i ) {
		return $self->DESTROY();
	}
};
#############################
sub from {					# Last received message sender
#############################
my $self = shift;
	return $self->{'from'}
};

#############################
sub listen {				# Listen socket
#############################
my ($self, $timeout) = @_;
$timeout = $self->{'timeout'} unless $timeout;

my $msg_recv;
my $try = $self->{'try'}+1;		# Just decrement before operation
my $msg_out;
my $log_msg = '';
my $message = {};

LISTEN: {
$msg_recv = '';			# Reset buffer
$self->{'from'} = '';		# Reset
	my ($ready, ) = $self->{'ready'}->can_read( $timeout );
	if ( $ready ) {
		$ready->recv($msg_recv, $self->{'buffsize'});
		$msg_recv =~ s/\n$//;


		my $header = substr( $msg_recv, 0, $HEADER_LEN );
		my $got_msg = substr( $msg_recv, $HEADER_LEN+1 );
		my @parts = split( /;/, $header );			# Decode header

		my $receiver = shift( @parts );
		my $sender_combo = shift( @parts );
		my $zlib = shift( @parts );
		my $msg_len = shift( @parts );

		$message->{$sender_combo} .= ($zlib && $use_zlib) ? uncompress( $got_msg ) : $got_msg;

		redo LISTEN if length($message->{$sender_combo}) < $msg_len;

		my ( $sender_name, $sender_pid, $wait_for ) = split( /\//, $sender_combo );
		unless ($sender_name) {
			$self->{'logger'}->debug("Wrong sender msg '$msg_recv'", 3, 1);
			return '';
		}
		$self->{'from'} = $sender_combo;		# That must  be enough
		$self->{'wait_for'} = $wait_for;		# Is sender is waiting for answer (ask_daemon used)?

		$log_msg = "$sender_combo => $receiver (".(length($msg_recv)).") ";
		$self->{'logger'}->debug("$log_msg", 2);

		if ( $sender_name eq $self->{'name'} ) {		# Undelivered msg returned
			$msg_out = '';
			$self->{'logger'}->debug("Message to $receiver returned!", 2);
		} elsif ( $receiver eq $self->{'name'} ) {		# Message to me?
			if ( !$self->{'parent_sock'}->[1] ) {		# Store parent socket if not have yet
				$self->{'parent_sock'} = [$sender_name, $sender_pid];
				$self->{'logger'}->debug("Register opener $sender_name/$sender_pid", 2) unless $self->{'master'};
			} elsif( ($self->{'parent_sock'}->[0] eq $sender_name) 
						&& ($self->{'parent_sock'}->[1] ne $sender_pid) && $wait_for ) {		# Renew parent PID
				$self->{'logger'}->debug("Renew opener PID $self->{'parent_sock'}->[0]/$self->{'parent_sock'}->[1] to $sender_pid", 2) unless $self->{'master'};
				$self->{'parent_sock'} = [$sender_name, $sender_pid];
			}
			
			unshift ( @{$self->{'known_socks'}}, 
					[$sender_name, $sender_pid] ) 
					unless grep { "$$_[0]$$_[1]" eq "$sender_name$sender_pid" } @{$self->{'known_socks'}};
						# That's live new socket, adding to front of list (FIFO)
			my $sig_die = $SIG{'__DIE__'};
			undef $SIG{'__DIE__'};
			undef $@;
			eval { $msg_out = decode_json( $message->{$sender_combo} ) };			# Parse to return /from_json
			$SIG{'__DIE__'} = $sig_die;
			
			return $msg_out;
				# Success state
		} elsif ( $try-- ) {		# Transmit stranger message
			$self->{'logger'}->debug("Strange message from $sender_name to $receiver", 2); 
			if ($self->send_msg( $receiver, $message->{$sender_combo}, $sender_combo )) {
				push ( @{$self->{'known_socks'}}, 
					[$sender_name, $sender_pid] ) 
					unless grep { "$$_[0]$$_[1]" eq "$sender_name$sender_pid" } @{$self->{'known_socks'}};
						# That's live new socket, adding to back of list (FILO)
				delete( $message->{$sender_combo});		# Reset collector buffer
				redo LISTEN;
			}			# Success transmitted to other
		}			# Received packet is mine?

	}		# Some got
}		# Wait LISTEN for input
	return $msg_out;
};
##############################
sub ask_daemon {		# Transfer query to some daemon
##############################
my ( $self, $receiver, $query ) = @_;
my $sender_name = $self->{'name'};
my $dmn_answer = "";		# Daemon answer
my $command = '';
my $try = $self->{'try'};

	$self->purge();
	TALK: {
		$dmn_answer = {'fail'=>"FAIL: connect $script_location/$receiver (send)"};	# Failure message assumed by default
		$try--;
		if ( $self->send_msg($receiver, $query) ) {
			$dmn_answer = $self->listen( $self->{'timeout'} ) || $dmn_answer;
			if ( $self->{'from'} !~ /$receiver/ && $try ) {
				redo TALK;
			}
		} elsif( $try ) {
			$self->{'logger'}->debug("No answer from $receiver. Try again...", 2);
			redo TALK;
		}				# Message sent?
	}			# Try to talk with daemon

  return $dmn_answer;
};
#####################
sub send_msg {		#		Send to any live daemon, then close OUT socket
#####################
my ($self, $receiver_combo, $query, $sender_combo) = @_;
	my ( $receiver_name, $receiver_sock, ) = split( /\//, $receiver_combo );		# Omit wait_for!
	my ( $receiver, $sender_name, $sender_pid, $wait_for);

	return 0 if $receiver_name eq $self->{'name'};

	unless ( $sender_combo ) {
		( $sender_name, $sender_pid, $wait_for ) = ( $self->{'name'}, $$, ( (caller(1))[3] =~ /ask_daemon/ ) );		# It's me!
	} else {
		( $sender_name, $sender_pid, $wait_for ) = split( /\//, $sender_combo );
	}

	$sender_combo = "$sender_name/$sender_pid/$wait_for" ;		# Reassemble combo

	my $message = $query;
	unless ( ref(\$query) eq 'SCALAR') {		# to_json( $query, {utf8=>0})
		my $sig_die = $SIG{'__DIE__'};
		undef $SIG{'__DIE__'};
		eval { $message = encode_json( $query ) };			# Parse to return /from_json
		$SIG{'__DIE__'} = $sig_die;
	}
	my $header = "$receiver_name;$sender_combo";


	$self->{'known_socks'} = [ grep { $_->[1] && -e( "$self->{'socks_path'}/$_->[1]" ) } 
					@{$self->{'known_socks'}} ];		# Cleanup known list, delete dead
	$self->rescan_daemon( $receiver_name ) unless scalar( @{$self->{'known_socks'}});
# $self->{'logger'}->debug("Send to $receiver_combo as '$receiver_name', known ".Dumper($self->{'known_socks'}), 3, 1);


	unless ( $receiver_sock ) {
		my $find_sock = [ grep { $_->[1] && $_->[0] eq $receiver_name } @{$self->{'known_socks'}} ];
		$receiver_sock = $find_sock->[0]->[1] if scalar(@$find_sock); 
	}		# Search for daemon stored with pid

	my $sock_send = $self->check_socket( $receiver_name, $receiver_sock );		# First try 
	if ( $sock_send ) {			# Succes connection
		$receiver_sock = $receiver_sock || $self->{'launched'};
		return $message if $self->transfer( $sock_send, $header, $message, "$receiver_name/$receiver_sock" );
	}			# Succes first connection
	
	if ( $self->{'master'} ) {		# Only if I can to launch daemon
		$self->{'known_socks'} = [ sort { ($b->[0] eq $receiver_name ) } @{$self->{'known_socks'}} ];
			# Place receiver's name first
	} elsif( $self->{'known_socks'}->[0]->[1] ne $self->{'parent_sock'}->[1] ) {			# Place opener socket to list
# 	$self->{'known_socks'} = [ grep{ "$$_[0]$$_[1]" ne "$self->{'parent_sock'}->[0]$self->{'parent_sock'}->[1]" }
# 				@{$self->{'known_socks'}} ];		# Remove early stored parent entry
		$self->{'known_socks'} = [ grep{ $_->[0] ne $self->{'parent_sock'}->[0] }
					@{$self->{'known_socks'}} ];		# Remove early stored ALL OF PARENT ENTRY
		splice( @{$self->{'known_socks'}}, 0, 0, \@{$self->{'parent_sock'}} );	# Place opener first
	}			# Optimize socket's list

	my $cnt = 0;
	while (my $receiver = $self->{'known_socks'}->[$cnt] ) {
		if ( $$receiver[1] && ($$receiver[0] ne $self->{'name'}) ) {
			$self->{'logger'}->debug("$self->{'name'} Try to connect to $$receiver[0]/$$receiver[1]", 2);
			my $sock_send = $self->check_socket( $$receiver[0], $$receiver[1] );		# Create socket for response
			if ( $sock_send ) {			# Succes connection
				$$receiver[1] = $$receiver[1] || $self->{'launched'};
				return $self->transfer( $sock_send, $header, $message, "$$receiver[0]/$$receiver[1]" );
			} else {
				$self->{'logger'}->debug("Delivery to $$receiver[0] failed!", 2);
				splice( @{$self->{'known_socks'}}, $cnt, 1);		# Forget receiver
				$self->rescan_daemon( $receiver ) if $#{$self->{'known_socks'}} < 0;		# Update list of daemons
				unless ( $self->{'master'} ) {
					next;		# Don't increase counter
				} else {
					last;		# Don't try to send to other
				}
			}
		}			# Receiver is'nt me?
		$cnt++;
	}			# Try to deliver to any daemon from list
	return 0;
};
###############
sub transfer {			# Split long messages to 64K packets  and send
###############
my ($self, $sock_send, $msg_header, $msg_sent, $receiver_combo) = @_;
my ($quant_qty, $zlib) = (1, 0);

	if ( length($msg_sent) > $self->{'buffsize'} ) {
		my $zip_size = length($msg_sent);
		$zip_size = length( compress($msg_sent) ) if $use_zlib;
		$quant_qty = int( $zip_size/$self->{'buffsize'} );
		$quant_qty += 1 if $quant_qty < $zip_size/$self->{'buffsize'};
		$zlib = $use_zlib;
	}
	my $portion_size = int(length( $msg_sent ) / $quant_qty);

	$msg_header .= ";$zlib;".length( $msg_sent );
	$msg_header .= ' ' x ( $HEADER_LEN - length( $msg_header ));
	my $cnt = 0;		# For logging needs
	my $start = 0;

	while ( $start < length($msg_sent) ) {
		$cnt++;
		my $portion = substr( $msg_sent, $start, $portion_size );
		$start += length( $portion );
		my $to_write = IO::Select->new( $sock_send );
		if ( $to_write->can_write($self->{'timeout'}) ) {
			$portion = compress( $portion ) if $zlib;

			my $sig_die = $SIG{'__DIE__'};
			undef $SIG{'__DIE__'};
			eval { $sock_send->send("$msg_header;$portion\n", 0 ) };
			$SIG{'__DIE__'} = $sig_die;
			if ( $@ ) {
				$self->{'logger'}->debug("ERROR: $receiver_combo : $@ ", 1);
				$sock_send->shutdown(2);		# Stop just using this socket 
				return '';
			}
		}
	}

	$self->{'logger'}->debug("Delivered to $receiver_combo (".(length($msg_sent))." bytes ) in $cnt block(s) (zlib:$zlib)", 2);
	$sock_send->shutdown( 1 );		# We are stop writing data
	$sock_send->close();
	return $msg_sent;			# Return delivered message
}
#####################
sub check_socket {	# Check, if connection to remote daemon in place
#####################
my ( $self, $daemon_name, $daemon_sockf ) = @_;
my $sock_daemon = 0;
my $try = $self->{'try'};

return $sock_daemon unless $daemon_name;

CONNECT: {
	undef $@;
	$sock_daemon = IO::Socket::UNIX->new(
		Peer => "$self->{'socks_path'}/$daemon_sockf", 
		Proto => 0, 
		Type => SOCK_DGRAM,
		Timeout => $self->{'timeout'});		# Create socket 
	if ( $@ ) {			# connection refused?
		$self->{'logger'}->debug("Connect to $daemon_name/$daemon_sockf : $@", 1);
		if ( $try > 0 && $self->{'master'} ) {			# If we can do it
			$try--;			# Normal tries decrement
			my $opcode = $self->start_daemon($daemon_name);	# 
			if ( $opcode > 0  ){
				$daemon_sockf = $self->{'launched'};
				redo CONNECT;
			} elsif( $opcode < 0 ) {
				return undef;
			}
			$self->{'logger'}->debug("$daemon_name/$daemon_sockf Try again...", 1);
			redo CONNECT;
		} else {
			$self->{'logger'}->debug("$daemon_name/$daemon_sockf $@ No more tries!", 1);
			return undef;
		}
	} else {
		push( @{$self->{'known_socks'}}, [$daemon_name, $daemon_sockf]) 
			unless grep{ "$$_[0]$$_[1]" eq "$daemon_name$daemon_sockf" } @{$self->{'known_socks'}};		# Add NEW live to end of list socket
	}
}		# Start process
  return $sock_daemon;
};

###############
sub start_daemon {
###############
my ( $self, $daemon_name ) = @_;
my $start_code = '';

	if ( -e( "$script_location/$daemon_name" ) && 
			-x( "$script_location/$daemon_name" ) && 
			!-d("$script_location/$daemon_name") ) {
		
		my $pid = open2( my $fh_daemon, my $fh_out, "$script_location/$daemon_name $self->{'name'}/$$" );
		do { $pid = waitpid( $pid, 0) } while $pid > 0;

		my ( $ready, ) = IO::Select->new( $fh_daemon )->can_read( $self->{'timeout'} );
		if ( $ready ) {
			$start_code = <$fh_daemon>;	# if $ready;
		}
		if ( $start_code =~ /^\d+/ ) {		# PID returned?
			push( @{$self->{'known_socks'}}, [$daemon_name, $start_code] );		# Add new socket
			$self->{'master'} = 1;
			$self->{'launched'} = $start_code;
			$self->{'logger'}->debug("Launched $daemon_name daemon : $start_code", 2);
			close( $fh_daemon );
			close( $fh_out );
			return 1;
		}
		$self->{'logger'}->debug("Opening $script_location/$daemon_name:$start_code Failed", 1);
		close( $fh_daemon );
		close( $fh_out );
		return 0;
	} else {
		$self->{'logger'}->debug("Can't execute $daemon_name (-e/x)", 1);
		return -1;
	}		# Absolute decrease tries count unless -e/x
};
###############
sub purge {			# Purge message stack
###############
my $self = shift;
  while ( my ( $ready, ) = $self->{'ready'}->can_read( 0 )) {
	$self->{'logger'}->debug("Purge input stack (".(length(<$ready>)-1).")", 2);
	last if length(<$ready>) < 1;
  }		# Emptying buffer before talking
  return
}
###############
sub cleanup {			# Cleanup socket directory
###############
my $self = shift;
my $sock_daemon;
  opendir( my $socks, $self->{'socks_path'} );		# Need to cleanup sockets directory
  my @socks = grep{ -S( "$self->{'socks_path'}/$_" ) } readdir( $socks );		# Get listing of socket directory
  closedir($socks);		#  (cleanup)
  foreach my $file ( @socks ) {		# Kill forgotten sockets (cleanup)
	next if $file eq $$;
	$@ = '';
	$sock_daemon = IO::Socket::UNIX->new(
	  Peer => "$self->{'socks_path'}/$file", 
	  Proto => 0, 
	  Type => SOCK_DGRAM, 
	  Timeout => 0);		# Create socket 
	  if ( $@ =~ /refused/ ) {
		unlink( $self->{'socks_path'}."/$file" );
		$self->{'logger'}->debug("Delete forgotten $file socket", 2);
	  }
	$sock_daemon->shutdown(0) if $sock_daemon;
	$sock_daemon->close() if $sock_daemon;
  }			# Kill forgotten sockets
}
###############
sub rescan_daemon {			# Update live sockets list
###############
my ($self, $receiver) = @_;
	my $procs = qx[ps -u "$>" o pid,command];		# Read from ps
	my @procs = grep{ $_ !~ /^ps/ } (split(/\n/, $procs)); shift( @procs );		# Remove column headers
	$self->{'self_socks'} = [];
	foreach my $proc ( @procs ) {			# Look for neighborous at launched processed
		$proc =~ s/^\s*//;
		my @cmd = split( /\s+/, $proc );
		my $pid = shift( @cmd );
		my $name;
		do { $name = shift( @cmd ) } while $name =~ /^\-|perl$/;
		$name = (split(/\//, $name))[-1];
		unless ( $name =~ /\./ ) {		# Ignore .fcgi and others
			if ( -S( "$self->{'socks_path'}/$pid") ) {		# && $pid ne $$
				if ( $name =~ /\b$self->{'name'}\b/ ) {
					push( @{$self->{'self_socks'}}, [$self->{'name'}, $pid] );		# Store same class daemons
				} elsif ( !$receiver ) {
					push( @{$self->{'known_socks'}}, [$name, $pid] );		# Store ALL other daemons
				} elsif ( $name =~ /\b$receiver\b/ ) {
					push( @{$self->{'known_socks'}}, [$name, $pid] );		# Store ASKED daemons
				}
			}
		}
	}
	$receiver = '<ghost>' unless $receiver;
	$self->{'logger'}->debug("Rescanned ".scalar(@{$self->{'known_socks'}})." daemons for '$receiver' and ".
							scalar(@{$self->{'self_socks'}})." of '$self->{'name'}'", 2);

	return $self->{'known_socks'};
}
1;
###############

=pod
Construct:
	name	- signature of daemon - required
	socket	- socket path/filename - required
	listen	- Socket::UNIX Listen - optional (1)
	try		- Tries of I/O operation - optional (5)
	timeout	- Connect to server timeout - optional (6)
	logger	- LOGGY.pm object - optional

Methods:
	new()
	ask_daemon($daemon, $query)		- Send query to daemon and get his response, send/return REF
	from()							- Returns last received message signature
	send_msg($receiver, $message)	- Sends to receiver, message must be a REF
	listen($timeout)				- Wait for message from server socket, returns REF!
	terminate, destroy, stop

Abstract:
  my $messenger = TALKS->new(
		socket => "$sys_root$sys{'temp_dir'}/$$",
		name => $my_name,
		listen => 1,
		try => 3,
		timeout => 5,
		logger => {$logger} );

=cut
