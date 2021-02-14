#! /usr/bin/perl
# Client operations
# 2021 (c) mac-t@yandex.ru
package Drive::Client;
use utf8;
use Encode;
use strict;
use warnings;
use Cwd 'abs_path';
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Time::HiRes qw( usleep );
use HTML::Template;

our $templates;
our $my_name = 'client';

use Data::Dumper;

#########################
sub checkin {		# 
#########################
my $self = shift;
	my $udata = $self->{'qdata'}->{'user_state'};
	my $param = $self->{'qdata'}->{'http_params'};

	my $template = 'client/checkin';
	$template = 'client/cabinet' if $udata->{'logged'} == 1;

	if ( $param->{'code'} ) {
		unless ( $param->{'data'}->{'fp'} eq $udata->{'fp'} ) {
			$self->redirect_to( 'cabinet', query => $self->{'qdata'}->{'http_params'} );
			return;
		}
		my $json = {'code' => $param->{'code'}, 'data' => $param->{'data'} };
		$json->{'data'}->{'state'} = 0;
		if ( $param->{'code'} eq 'checkin' ) {
			if ( $param->{'data'}->{'action'} eq 'login' ) {
				$json->{'data'}->{'state'} = $self->get_login();
			} elsif( $param->{'data'}->{'action'} eq 'register' ) {
			} elsif( $param->{'data'}->{'action'} eq 'reset' ) {
			}
			$self->{'qdata'}->{'tags'}->{'page_title'} = "Under construction";
		} elsif( $param->{'code'} eq 'register') {
			$self->redirect_to( 'cabinet', query => $self->{'qdata'}->{'http_params'} );
			return;
		} elsif( $param->{'code'} eq 'reset' ) {
		}
		$self->render( type => 'application/json', json => $json );
		return;

	} else {
		$self->render( template => $template, status => $self->stash('http_state') );
	}
}
#############################
sub checked {				# All of operations dispatcher
#############################
my $self = shift;
	unless ( $self->{'qdata'}->{'user_state'}->{'logged'} == 1 ) {
		$self->redirect_to( 'cabinet', query => $self->{'qdata'}->{'http_params'} );
		return;
	}

	my $action = shift( @{$self->{'qdata'}->{'stack'}} );

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
sub get_login {				# Query user id by some user information
#############################
my $self = shift;
	my $ret_state = 0;
	my $udata =  $self->{'qdata'}->{'http_params'}->{'data'};
	my $flist = '_uid,_fp,_email,_login,_pwd';
	my $sql = "SELECT 1 AS state,$flist FROM users WHERE _login='$udata->{'login'}' AND _pwd=MD5('$udata->{'pwd'}')";
	$sql .= " UNION SELECT 2 AS state,$flist FROM users WHERE _email='$udata->{'login'}' AND _pwd=MD5('$udata->{'pwd'}')";
	$sql .= " UNION SELECT 3 AS state,$flist FROM users WHERE _login='$udata->{'login'}'";
	$sql .= " UNION SELECT 4 AS state,$flist FROM users WHERE _email='$udata->{'login'}'";
	my $urec = $self->dbh->selectall_arrayref($sql, {Slice=>{}});
	if ( scalar( @$urec ) ) {
		if ( $urec->[0]->{'state'} < 3 ) {
			$self->dbh->do("UPDATE users SET _fp='$udata->{'fp'}' WHERE _uid='$urec->[0]->{'_uid'}'");
			$self->{'qdata'}->{'user_state'}->{'cookie'}->{'uid'} = $urec->[0]->{'_uid'};
			$ret_state = 1;
		} else {
			$ret_state = 2;
		}
	}
	$self->logger->dump(Dumper($urec->[0]),2,1);
	$self->logger->dump("WE ARE $udata->{'fp'}",2,1);
	return $ret_state;
}
1
