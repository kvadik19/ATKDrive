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

	my $template = 'main';
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
	my $auth_file = "$Drive::sys_root$Drive::sys{'conf_dir'}/admin";
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
sub access_read {			# .htaccess read
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
sub access_write {			# htpasswd operations
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
sub connect {		# Setup interconnect settings
#####################
	my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $conf_dir = "$Drive::sys_root$Drive::sys{'conf_dir'}";
	my $conf_file = "$conf_dir/config.xml";
	my $auth_file = "$conf_dir/.wsclient";
	my $config = {};
	$config = Drive::read_xml( $conf_file );

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
							msg => encode_utf8($param->{'data'}->{'ping_msg'}),
							login => $param->{'data'}->{'htlogin'},
							pwd => $param->{'data'}->{'htpasswd'},
						);
		$ret->{'json'} = { 'code' => $param->{'code'}, 'response' => decode_utf8($resp) };

	} elsif( $param->{'code'} eq 'connect' ) {
		$ret->{'json'} = {'code' => $param->{'code'}, 'success' => 1, 'params' => []};

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
sub utable {		# User registration tuneup
#####################
	my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $conf_dir = "$Drive::sys_root$Drive::sys{'conf_dir'}";
	my $conf_file = "$conf_dir/config.xml";
	my $ret = { 'struct'=>[], 'scr_num'=>1, };

	my $config = {};
	$config = Drive::read_xml( $conf_file );

	my $struct = $self->dbh->selectall_arrayref("DESCRIBE users",{Slice=>{}});
	foreach my $def (@$struct) {
		my $dat = {};
		foreach my $fld ( qw(Field Type Default Key) ) {
			$dat->{lc($fld)} = $def->{$fld};		# Lower case column names!
		}
		if ( $dat->{'type'} =~ /^(\w+)\(([\d\.]+)\)$/ ) {
			$dat->{'typet'} = $1;
			$dat->{'len'} = $2;
		}
		$dat->{'scr'} = 1 if $ret->{'scr_num'} == 1;
		push( @{$ret->{'struct'}}, $dat);
	}

	unless ( $param->{'code'} ) {
	} elsif( $param->{'code'} eq 'utable') {
		$ret->{'json'} = { 'code' => $param->{'code'}, 'success' => 1 };
		my $define = $param->{'data'};

		my $dupes;			#### Prevent duplicates first
		my $recno = 0;
		foreach my $def ( @$define ) {
			push( @{$dupes->{$def->{'name'}}}, $recno );
			$recno++;
		}
		if ( scalar( keys(%$dupes)) != scalar(@$define) ) {
			my $to_drop = [];
			while( my($fld, $rec) = each( %$dupes) ) {
				while ( scalar( @$rec) > 1 ) {
					push( @$to_drop, shift( @$rec) );
				}
			}
			if ( scalar( @$to_drop) ) {
				push( @{$ret->{'json'}->{'fail'}}, scalar( @$to_drop).' Duplicates found');
				$to_drop = [ sort {$b <=> $a} @$to_drop ];		# Delete some recods, begining from end
				while ( my $no = shift( @$to_drop) ) {
					splice( @$define, $no, 1);
				}
			}
		}			#### Prevent duplicates first end

		my $sql_stack;
		foreach my $def ( @$define ) {			# Find for new/changed fields
			my $sql = $self->db_modi( $def, $ret->{'struct'});
			if ( $sql ) {
				push( @$sql_stack, {'name'=>$def->{'name'}, 'sql'=>$sql});
				if ( $sql =~ /ADD COLUMN/ ) {
					push( @$sql_stack, {'name'=>$def->{'name'}, 'sql'=>"ALTER TABLE users ADD INDEX $def->{'name'} ($def->{'name'})"});
				}
			}
		}
		foreach my $def ( @{$ret->{'struct'}} ) {			# Find for deleted fields
			my $has = Drive::find_first( $define, sub { my $r = shift; return $r->{'name'} eq $def->{'field'}} );
			if ( $has < 0 ) {
				push( @$sql_stack, {'name'=>$def->{'field'}, 'sql'=>"ALTER TABLE users DROP COLUMN $def->{'field'}"});
			}
		}
		$ret->{'json'}->{'update'} = $sql_stack;
	}
	return $ret;
}
#####################
sub db_modi {		# Create sql to modify table
#####################
my ($self, $def, $struct) = @_;
my $sql;
	return $sql if $def->{'type'} eq 'file';

	my $sql_make = sub {
			my ($new, $old) = @_;
			my $sql = '';
			$new->{'field'} = $new->{'name'};
			$new->{'len'} =~ s/\D+/,/;
			$new->{'type'} = "$new->{'type'}($new->{'len'})" if $new->{'len'};
			if ( $old ) {
				my $upd = 0;
				foreach my $fname ( qw(field type default) ) {
					if ( $new->{$fname} ne $old->{$fname} ) {
						$upd = 1;
						last;
					}
				}
				$sql = "ALTER TABLE users CHANGE $old->{'field'} $new->{'field'} $new->{'type'} DEFAULT '$new->{'default'}'" if $upd;
			} else {
				$sql = "ALTER TABLE users ADD COLUMN $new->{'field'} $new->{'type'} DEFAULT '$new->{'default'}'";
			}
			return $sql;
		};

	my $has = Drive::find_first( $struct, sub{ my $r = shift; return $r->{'field'} eq $def->{'name'}} );
	if ( $has < 0 ) {
		$has = Drive::find_first( $struct, sub{ my $r = shift; return $r->{'field'} eq $def->{'_default'}->{'name'}} );
		if ( $has < 0 ) {			#  Check for renamed field
			$sql = $sql_make->( $def );
		} else {
			$sql = $sql_make->( $def, $struct->[$has]);
		}
	} else {			# Existing field, change define
		$sql = $sql_make->( $def, $struct->[$has]);
	}
	return $sql;
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
#####################
sub reboot {		# Manually reboot backserver
#####################
	my $self = shift;
	my $signal = 'USR2';
	my $res = kill( $signal, getppid() );
	return {'pid' => getppid, 'signal' => $signal};
}
1
