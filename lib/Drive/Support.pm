#! /usr/bin/perl
# Admin operations
# 2021 (c) mac-t@yandex.ru
package Drive::Support;
use utf8;
use Encode;
use strict;
use warnings;
use Cwd 'abs_path';
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Utils::NETS;
use Time::HiRes qw( usleep );
use HTML::Template;

our $templates;
our %sys = %Drive::sys;
use Data::Dumper;

#############################
sub hello {					# Operations root menu
#############################
my $self = shift;
	$self->{'qdata'}->{'layout'} = 'support';
	$self->render( template => 'drive/splash', status => $self->stash('http_state') );
}
#############################
sub support {				# All of operations dispatcher
#############################
my $self = shift;

	my $action = shift( @{$self->{'qdata'}->{'stack'}} );
	$action = shift( @{$self->{'qdata'}->{'stack'}} ) if $action eq 'drive';

	my $template = 'drive/main';
	my $out = "404 : Page $action not found yet";

	eval { $out = $self->$action };
	if ( $@) {			# sub is not defined (yet?)
		$self->logger->dump("$action : $@", 3);
		$self->stash( 'http_state' => 404 );
		$self->{'qdata'}->{'tags'}->{'page_title'} = $out;
		$template = 'exception';
	} else {
		$self->{'qdata'}->{'tags'}->{'page_title'} = $action;
		$template = "drive/$action";
	}

	if ( ref($out) eq 'HASH' ) {
		if ( exists( $out->{'json'}) ) {
			$self->render( type => 'application/json', json => $out->{'json'} );
			return;
		} else {
			while ( my ($key,$val) = each(%$out) ) {
				$self->stash( $key => $val );
			}
		}
	} else {
		$self->stash( 'html_code' => $out );
	}
	$self->{'qdata'}->{'layout'} = 'support';
	$self->render( template => $template, status => $self->stash('http_state') );
}
#############################
sub access {				# .htaccess file editor
#############################
my $self = shift;
	my $auth_file = Drive::upper_dir("$Drive::sys_root$Drive::sys{'conf_dir'}").'/.admin';
	my $param = $self->{'qdata'}->{'http_params'};
	my $ret = {'users' => [], 'auth_file' => $auth_file, 'magic_mask' => 8};

	unless ( $param->{'code'} ) {
		$ret->{'users'} = $self->access_read( $auth_file, $ret->{'magic_mask'} );

	} elsif( $param->{'code'} eq 'access' ) {
		$ret->{'json'} = $param;
		$ret->{'json'}->{'success'} = 1;
		my $op = $self->access_write( $auth_file, $param->{'users'} );
		if ( $op ) {
			$ret->{'json'}->{'success'} = 0;
			$ret->{'json'}->{'fail'} = $op;
		}
	}
	return $ret;
}
#############
sub access_read {
#############
	my $self = shift;
	my $fn = shift;
	my $mask_len = shift || 8;
	my $list = [];
	if ( -e($fn) ) {
		my $mask = '&#9733;' x $mask_len;			# What to show in password table cell
		open( my $fh, "< $fn");
		while ( my $line = <$fh> ) {
			chomp( $line );
			my ($name, $pwd) = split(/:/, $line);
			push( @$list, {'name' => $name, 'pwd' => $pwd, 'display' => $mask});
		}
		close($fh);
	}
	return $list;
}
#############
sub access_write {
#############
	my ($self, $fn, $list) = @_;
	my $fout;
	my $assign = [];
	foreach my $row ( @$list ) {			# Write flat data
		next unless $row->{'name'} && $row->{'pwd'};
		$fout .= "$row->{'name'}:$row->{'pwd'}\n";
		push( @$assign, $row) if $row->{'pwd'} ne $row->{'old_pwd'};
	}
	open( my $fh, "> $fn");
	print $fh $fout;
	close( $fh );
	foreach my $usr ( @$assign ) {					# Generate and update passwords
		my $fs = system($Drive::sys{'call_htpasswd'},'-b', $fn, $usr->{'name'}, $usr->{'pwd'});
		if ( $fs > 0 ) {
			$self->logger->dump("Passwd operation '$usr->{'name'}' at '$fn':$!",2);
			return $!;
		}
	}
	return undef;
}
#####################
sub connect {		# Process websocket queries
#####################
	my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$Drive::sys{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";
	my $auth_file = "$conf_dir/.wsclient";
	my $config = {};
	Drive::add_xml( $config, $conf_file );
	my $ret = {'config_file' => $conf_file, 'auth_file' => $auth_file, 'magic_mask' => 8,
				'config' => $config->{'connect'}};

	my $masker = sub {
			my ( $hashref, $umask ) = @_;
			foreach my $key ( qw(ping_msg js_wsocket) ) {
				$hashref->{$key} = Drive::xml_mask( $hashref->{$key}, $umask );
			}
		};

	unless ( $param->{'code'} ) {
		$masker->( $config->{'connect'}, 1);
		unless ( $config->{'connect'}->{'js_wsocket'} ) {		# Prepare some defaults
			if ( -e( "$conf_dir/js_wsocket_default.tmpl" ) ) {
				my $jstmpl = HTML::Template->new( 				# Insert some site-specific data
						filename => "$conf_dir/js_wsocket_default.tmpl",
						die_on_bad_params => 0,
						die_on_missing_include => 0,
					);
				$jstmpl->param( { 'ws_url' => "ws://username:password\@$self->{'qdata'}->{'user_state'}->{'host'}"
									.$self->url_for('wsocket') } );
				$ret->{'config'}->{'js_wsocket'} = decode_utf8( $jstmpl->output() );
			}
		}
		$ret->{'users'} = $self->access_read( $auth_file, $ret->{'magic_mask'} );

	} elsif( $param->{'code'} eq 'ping' ) {
		my $resp = Utils::NETS->ask_inet(
							host => $param->{'data'}->{'host'},
							port => $param->{'data'}->{'port'},
							msg => encode_utf8($param->{'data'}->{'msg'}),
							login => $param->{'data'}->{'htlogin'},
							pwd => $param->{'data'}->{'htpasswd'},
						);
		$ret->{'json'} = { 'code' => 'ping', 'response' => decode_utf8($resp) };

	} elsif( $param->{'code'} eq 'connect' ) {
		$ret->{'json'} = {'code' => 'connect', 'success' => 1, 'params' => []};

		if ( $param->{'data'}->{'users'} ) {
			my $op = $self->access_write( $auth_file, $param->{'data'}->{'users'} );
			if ( $op ) {
				$ret->{'json'}->{'success'} = 0;
				$ret->{'json'}->{'fail'} = $op;
			}
			delete( $param->{'data'}->{'users'} );
		}
		if ( $ret->{'json'}->{'success'} ) {
			$masker->( $param->{'data'} );
			while( my ($key, $val) = each( %{$param->{'data'}} ) ) {
				$config->{'connect'}->{$key} = $val;
				push( @{$ret->{'json'}->{'params'}}, $key);
			}
			Drive::write_xml( $config, $conf_file );
		}
	}
	return $ret;
}
#####################
sub reboot {		# Manually reboot backserver
#####################
	my $self = shift;
	my $signal = 'USR2';
	my $res = kill( $signal, getppid() );
	return {'pid' => getppid, 'signal' => $signal};
}
#####################
sub wsocket {		# Process websocket queries
#####################
	my $self = shift;

	$self->on( message => sub { my ( $ws, $msg_recv ) = @_;
						my $msg_send = {'fail' => "418 : I'm a teapot"};

						if ( $msg_recv =~ /^[\{\[].+[\}\]]$/ ) {		# Got JSON?
							my $qry;
							eval{ $qry = decode_json( encode_utf8($msg_recv) )};
							if ( $@) {
								$msg_send->{'fail'} = "Decode JSON : $@";
								$self->logger->dump( $msg_send->{'fail'} );
							} else {
								delete( $msg_send->{'fail'});
								$msg_send->{'code'} = 'ECHO';
								$msg_send->{'data'} = $qry;
							}
							$msg_send = decode_utf8(encode_json( $msg_send ));
						} else {
							$msg_send ="ECHO: $msg_recv";
						}
						$ws->send( $msg_send );
					});

	$self->on( finish => sub { my ( $ws, $code, $reason ) = @_;
						$self->{'messenger'}->terminate() if $self->{'messenger'};
					});
}
1
