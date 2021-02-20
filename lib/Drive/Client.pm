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
use Mojo::Util qw(url_escape url_unescape b64_encode  trim md5_sum);
use Time::HiRes;
use HTML::Template;
use MIME::Lite;
use Utils::NETS;

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
			$self->redirect_to( 'cabinet', query => $param );
			return;
		}
		my $json = {'code' => $param->{'code'}, 'data' => $param->{'data'} };
		$json->{'data'}->{'state'} = 0;
		if ( $param->{'code'} eq 'checkin' ) {
			if ( $param->{'data'}->{'action'} eq 'login' ) {
				$json->{'data'}->{'state'} = $self->login_status();
			} elsif( $param->{'data'}->{'action'} eq 'register' ) {
				$self->redirect_to( 'cabinet', query => $param );
				return;
			} elsif( $param->{'data'}->{'action'} eq 'reset' ) {
				$json->{'data'}->{'html_code'} = $self->hash_door( $param->{'data'}->{'action'} );
			}
			$self->{'qdata'}->{'tags'}->{'page_title'} = "Under construction";
		} elsif( $param->{'code'} eq 'register') {
		} elsif( $param->{'code'} eq 'reset' ) {
			
		}
		$self->render( type => 'application/json', json => $json );
		return;

	} else {
# $self->logger->dump(Dumper($param),2,1);
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
sub hash_door {				# Open door to user cabinet by hash reference
#############################
my $self = shift;
my $action = shift;
	my $param = $self->{'qdata'}->{'http_params'}->{'data'};
	my $udata = $self->{'qdata'}->{'user_state'};
	my $message;
	return $message unless -e("$Drive::sys_root$Drive::sys{'mail_dir'}/$action.tmpl");

	my $timestamp = Time::HiRes::time();
	my $hash = $udata->{'fp'}.md5_sum($timestamp);
	my $hashlink = "$udata->{'proto'}://$udata->{'host'}/cabinet?h=$udata->{'fp'}&t=$timestamp";

	my $urec = $self->get_login( $param->{'login'}, $param->{'pwd'} );
	my $where;
	if ( $urec->{'state'} == 3 ) {			# login match
		$where = "_login='$param->{'login'}'";
	} elsif( $urec->{'state'} == 4 ) {			# email match
		$where = "_email='$param->{'login'}'";
	}

	my $mdata = {'link_accept' => $hashlink, 'link_reject' => "$hashlink&r=1",
					'site_name' => $Drive::sys{'our_site'}, 'site_url' => $Drive::sys{'our_host'},
					'timeout' => $Drive::sys{'reg_timeout'} 
				};
	my $letter = HTML::Template->new( filename => "$Drive::sys_root$Drive::sys{'mail_dir'}/$action.tmpl",
						die_on_bad_params => 0,
						die_on_missing_include => 0,
					);
	$letter->param( $mdata );
	eval {
		$letter = decode_utf8( $letter->output() );
		};
	if ( $@ ) {
		$self->logger->dump("Decode letter: $@", 3);
		$letter = '';
	}

	my $dom = Mojo::DOM->new($letter);				# Extract something from letter
	my $banner;
	if ( $dom->find('comment')->[0] ) {
		$banner = $dom->find('comment')->[0]->content;
		$dom->find('comment')->[0]->remove;
	}

	my $domplain = Mojo::DOM->new( $dom->to_string );
	$domplain->find('a')->each( sub { my ($itm, $num) = @_;
					return unless $itm;
					my $text = $itm->text();
					my $href = $itm->attr('href');
					$itm->replace("$text: $href");
				});
	my $txtpart = $domplain->all_text;
	$txtpart =~ s/[\s\n]*$//g;
	$txtpart .= "\n";

	my $subj = $dom->find('h1#head')->[0];
	$subj = $subj->text() if $subj;

	my $msg = MIME::Lite->new(
			From => encode('MIME-Header', decode_utf8($mdata->{'site_name'}))."<noreply\@$udata->{'host'}>",
			To => encode( 'MIME-Header', $urec->{'_login'})." <$urec->{'_email'}>",
			Subject => encode( 'MIME-Header', $subj),
			Type => 'multipart/alternative',
		);
	$msg->add('List-Unsubscribe' => $mdata->{'link_reject'});
	$msg->replace('X-Mailer' => "$udata->{'host'} Mail Agent");

	$msg->attach(
			Type => 'text/plain;charset=utf-8',
			Data => $txtpart,
		);
	my $htpart = MIME::Lite->new(
			Top => 0,
			Type =>'text/html',
			Data => $dom->to_string(),
		);

	$htpart->attr('content-type.charset' => 'UTF-8');
	$htpart->add('X-Comment' => 'HTML-formatted message');
	$msg->attach( $htpart );

	if ( $Drive::sys{'smtp_host'} ) {			# sysd.conf settings
		my ($usr, $pwd) = split(/:/, $Drive::sys{'smtp_login'} );
		if ( $usr && $pwd ) {
			$msg->send('smtp', $Drive::sys{'smtp_host'}, Debug=>1, AuthUser=>$usr, AuthPass=>$pwd );	# Send via Authorized smtp
		} else {
			$msg->send('smtp', $Drive::sys{'smtp_host'}, Debug=>1 );			# Send via free smtp
		}
	} else {
# open(my $fh, "> $Drive::sys_root/mail.out");
# $msg->print($fh);
# close $fh;
		$msg->send();			# Send via sendmail
	}

	$self->dbh->do("UPDATE users SET _hash='$hash',_ip='$udata->{'ip'}' WHERE $where");
	return $banner;
}
#############################
sub login_status {				# Query user id by some user information
#############################
my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'}->{'data'};
	my $udata = $self->{'qdata'}->{'user_state'};
	my $urec;
	my $ret_state = 0;

	$urec = $self->get_login( $param->{'login'}, $param->{'pwd'});
	return $ret_state unless $urec;
	if ( $urec->{'state'} < 3 ) {
		my $logtime = time;
		$self->dbh->do("UPDATE users SET _fp='$udata->{'cookie'}->{'fp'}',_ltime='$logtime' WHERE _uid='$urec->{'_uid'}'");
		$udata->{'cookie'}->{'uid'} = $urec->{'_uid'};
		$ret_state = 1;
	} else {
		$ret_state = 2;
	}
	return $ret_state;
}
#############################
sub get_login {				# Query user id by some user information
#############################
my ($self, $login, $pwd) = @_;
	my $flist = '_uid,_fp,_email,_login,_pwd';
	my $sql = "SELECT 1 AS state,$flist FROM users WHERE _login='$login' AND _pwd=MD5('$pwd')";
	$sql .= " UNION SELECT 2 AS state,$flist FROM users WHERE _email='$login' AND _pwd=MD5('$pwd')";
	$sql .= " UNION SELECT 3 AS state,$flist FROM users WHERE _login='$login'";
	$sql .= " UNION SELECT 4 AS state,$flist FROM users WHERE _email='$login'";
	my $urec = $self->dbh->selectall_arrayref($sql, {Slice=>{}});
	return shift( @$urec );
}
1
