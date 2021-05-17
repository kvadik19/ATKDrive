#! /usr/bin/perl
# 1C response emulator

use 5.18.0;
use strict;
use utf8;
use POSIX;
use IO::Socket;
use IO::Select;
use Mojo::JSON qw(decode_json encode_json);
use Encode;
use Data::Dumper;
use FindBin;

my $EOL = "\015\012";
my $port = 10001;
my $buffsize = 4096;
my $sys_root = "$FindBin::Bin/..";

my $sock = IO::Socket::INET->new(
					Listen	=> SOMAXCONN,
					LocalPort	=> $port,
					Proto		=> 'tcp',
					Reuse		=> 1,
				) || die "Cannot create socket: $@ $IO::Socket::errstr";

say 'Ready to serve tcp on port ', $sock->sockport;
say 'Ctrl+C or {"code":"STOP"} message to shut down';

my $filename = "$sys_root/config/1Cresponder.json";
my $responder;

my $msg_recv = '';
while ( my $client = $sock->accept() ) {
	$client->autoflush(1);
	my $msg_send = {};

	$client->recv( $msg_recv, $buffsize );

	say $client->peerhost, ':', $client->peerport, ' => ', length($msg_recv),' bytes';
	if ( $msg_recv =~ /^[\{\[].+[\}\]]$/ ) {		# Got JSON?
		my $qry;
		eval{ $qry = decode_json( encode_utf8($msg_recv) )};
		if ( $@) {
			$msg_send->{'fail'} = "Decode JSON : $@";
			say $@;
		} else {
			if ( $qry->{'code'} eq 'STOP' ) {
				$client->send( "STOP served!", 0 );
				say 'STOP received';
				exit 0 ;
			}
			renew( $filename );
			if ( exists( $responder->{ $qry->{'code'}}) ) {
				$msg_send->{'code'} = $responder->{$qry->{'code'}}->{'code'} || $qry->{'code'};
				$msg_send->{'data'} = $responder->{$qry->{'code'}}->{'data'};
			} else {
				$msg_send->{'code'} = 'ECHO';
				$msg_send->{'data'} = $qry;
				$msg_send->{'data'}->{'client'} = $client->peerhost;
				$msg_send->{'data'}->{'comment'} = 'code:STOP will abort responder';
			}
		}
		$msg_send = encode_json( $msg_send );
	} else {
		$msg_send ="ECHO: $msg_recv";
	}
	if ( $msg_recv =~ /HTTP\/\d+\.\d+/ ) {
		$msg_send = "HTTP/1.1 200 OK$EOL"
					."Content-Type:application/json;charset=UTF8$EOL"
					."$EOL$msg_send";
	}
	$msg_recv = '';
	$client->send( $msg_send, 0 );
}
##########
sub renew {
	my $filename = shift;
	if ( ref( $responder) ne 'HASH' || -M( $filename ) < 0 ) {
		if ( -f( $filename ) ) {
			open( my $fh, "< $filename" ) || return "JSON $filename Open : $!";
			my $content = join('', <$fh>);
			close( $fh );
			eval{ $responder = decode_json( $content ) };
			die "$filename : $@" if $@;
		} else {
			say "$filename not ready. Continue";
		}
	}
}
##########
