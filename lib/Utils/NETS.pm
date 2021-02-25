package Utils::NETS;
# Interconnect utilities

use Cwd 'abs_path';
use strict;
use Mojo::UserAgent;
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use IO::Socket;
use IO::Select;
use Net::SMTP::SSL;
use MIME::Lite;

use Time::HiRes qw( usleep );
use Fcntl qw(:flock SEEK_END);

our $VERSION = '0.01';
my @options = qw(
		host
		port
		msg
		login
		pwd
		logger
	);

#####################
sub ask_inet {		# Process inet transactions
#####################
	my $self = shift;
	my $init = { @_};

	return "Not enough data to connect" unless $init->{'host'};

	my $timeout = $Drive::sys{'inet_timeout'}	|| 5;
	my $buffsize = $Drive::sys{'inet_buffer'};
	my $proto = $Drive::sys{'inet_proto'} || 'tcp';
	my $msg_recv;
	if ( $init->{'host'} =~ /^http/i || !$init->{'port'}) {
		my $url = Mojo::URL->new($init->{'host'});
		$url->scheme('http') unless $url->scheme;
		$url->port($init->{'port'});
		$url->userinfo("$init->{'login'}:$init->{'pwd'}") if $init->{'login'} || $init->{'pwd'};
		my $sock = Mojo::UserAgent->new(
				'max_redirects' => 8,
				'connect_timeout' => $timeout,
			);			# our
		$sock->transactor->name('ATKDrive-Mozilla/12.0 (Macintosh; WOW63; Intel Mac OS X 10_86_17) AppleWebKit/537.36 (KHTML, like Gecko)');

		my $msg_out = {'code' => 'RAW', 'data' => $init->{'msg'} };
		unless ( ref( $init->{'msg'} ) ) {
			if ( $init->{'msg'} =~ /^[\{\[]"/ ) {
				eval { $msg_out = decode_json( $init->{'msg'} ) };
				$msg_out = {'code' => 'RAW', 'data' => $msg_out } if $@;
			}
		}
		my $got = $sock->post( $url => json => $msg_out );
		if ( $got->res->code == 200 ) {
			eval { $msg_recv = encode_json($got->res->json) };
			$msg_recv = $got->res->to_string if $@;
		} else {
			$msg_recv = $got->res->code.': '.$got->res->error->{'message'};
		}

	} else {
		my $sock = IO::Socket::INET->new(
							PeerAddr	=> $init->{'host'},
							PeerPort	=> $init->{'port'},
							Proto		=> $proto,
						);
		return "$@ $IO::Socket::errstr" if $@;
		$sock->autoflush(1);
		my $msg = $init->{'msg'};
		if ( ref( $init->{'msg'} ) ) {
		}

		my $ready = IO::Select->new( $sock );
		my ($canw, ) = $ready->can_write( $timeout );
		if ( $canw ) {
			$canw->send("$msg", 0);
			my ($canr, ) = $ready->can_read( $timeout );
			if ( $canr ) {
				unless ( $buffsize ) {
					while ( <$canr> ) {
						$msg_recv .= $_;
					}
				} else {
					$canr->recv( $msg_recv, $buffsize);
				}
			} else {
				return "Can't Read from $init->{'host'} in $timeout sec.";
			}
		} else {
			return "Can't Send to $init->{'host'} in $timeout sec.";
		}
	}
	return $msg_recv;
}
#########################
sub email_good {			# Precheck email address fnd fix possible miss
#########################
	my $self = shift;
	my $aref = shift;
	my $text = $$aref;
	$$aref =~ s/\s//g;
	my $good;
	my ($usr, $host) = split(/@/, $$aref);
	$usr =~ s/^\.+//g;
	$host =~ s/[,;\/]/./g;
	my $res = `host $host`;
	if ( $res =~ /(\d{1,3}.?){4}/ && $usr =~ /^[\w\-.]+$/ ) {
		$$aref = lc($usr).'@'.lc($host);
		$good = 1;
	}
	return $good;
}

1
