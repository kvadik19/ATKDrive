#! /usr/bin/perl
# Just for testing tcp communications between modules

use 5.18.0;
use strict;
use utf8;
use POSIX;
use IO::Socket;
use IO::Select;
use Mojo::JSON qw(decode_json encode_json);
use Encode;
use Data::Dumper;

my $EOL = "\015\012";
my $port = 10001;
my $buffsize = 1024;

my $sock = IO::Socket::INET->new(
					Listen	=> SOMAXCONN,
					LocalPort	=> $port,
					Proto		=> 'tcp',
					Reuse		=> 1,
				) || die "Cannot create socket: $@ $IO::Socket::errstr";

say 'Ready to serve tcp on port ', $sock->sockport;
say 'Ctrl+C or {"code":"STOP"} message to shut down';

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
			$msg_send->{'code'} = 'ECHO';
			$msg_send->{'data'} = $qry;
			$msg_send->{'data'}->{'client'} = $client->peerhost;
			$msg_send->{'data'}->{'comment'} = 'code:STOP will abort responder';
		}
		$msg_send = decode_utf8(encode_json( $msg_send ));
	} else {
		$msg_send ="ECHO: $msg_recv";
	}
	if ( $msg_recv =~ /HTTP\/\d+\.\d+/ ) {
		$msg_send = "HTTP/1.1 200 OK$EOL"
					."Content-Type:text/plain;charset=UTF8$EOL"
					."$EOL$msg_send";
	}
	$msg_recv = '';
	$client->send( "$msg_send", 0 );
}
