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
our %sys = %Drive::sys;

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
				$json->{'data'}->{'point'} = $self->url_with('/register')->query($param->{'data'})->to_abs;
			} elsif( $param->{'data'}->{'action'} eq 'reset' ) {
				$json->{'data'}->{'html_code'} = $self->hash_door( $param->{'data'}->{'action'} );
			}
			$self->{'qdata'}->{'tags'}->{'page_title'} = "Under construction";
		}
		$self->render( type => 'application/json', json => $json );
		return;

	} else {
		$self->render( template => $template, status => $self->stash('http_state') );
	}
}
#################
sub checked {	# All of operations dispatcher
#################
my $self = shift;
# $self->logger->dump("Do Checked",2,1);
# $self->logger->dump(Dumper($self->{'qdata'}),2,1);
# 
	unless ( length($self->{'qdata'}->{'user_state'}->{'fp'}) == 32 ) {
		$self->redirect_to( 'cabinet', query => $self->{'qdata'}->{'http_params'} );
		return;
	}

	my $action = shift( @{$self->{'qdata'}->{'stack'}} );

	my $template = 'main';
	my $out = "404 : Page $action not found yet";
	unless ( $templates->{$action} ) {
		my $templ;
		eval {
			$templ = HTML::Template->new(
					filename => "$Drive::sys_root$sys{'html_dir'}/$action.tmpl",
					die_on_bad_params => 0,
					die_on_missing_include => 0,
				);
			};
		if ( $@ ) {
			$self->logger->dump("Template $action: $@");
		} else {
			$templates->{$action} = $templ;
		}
	}

	eval { $out = $self->$action };
	if ( $@) {			# sub is not defined (yet?)
		$self->logger->dump("$action : $@", 3);
		$self->stash( 'http_state' => 404 );
		$self->{'qdata'}->{'tags'}->{'page_title'} = $out;
		$template = 'exception';
	}

	if ( ref($out) eq 'HASH' ) {
		if ( exists( $out->{'json'}) ) {
			$self->render( type => 'application/json', json => $out->{'json'} );
			return;
		} elsif( exists($out->{'redirect'})) {
			$self->redirect_to( $out->{'redirect'} );
			return;
		} else {
			while ( my ($key,$val) = each(%$out) ) {
				$self->stash( $key => $val );
			}
		}
	} else {
		$self->stash( 'html_code' => $out );
	}
	$self->render( template => $template, status => $self->stash('http_state') );
}
#################
sub logout {	# Close user connection
#################
my $self = shift;
	$self->{'qdata'}->{'user_state'}->{'cookie'}->{'uid'} = 0;
	return {'redirect' => 'cabinet'};
}
#################
sub cabinet {	# Main user operations form
#################
my $self = shift;
}
#################
sub register {		# User registration/personal data form
#################
my $self = shift;
my $param = $self->{'qdata'}->{'http_params'};

	$param->{'email'} = $param->{'login'} if $param->{'login'} =~ /\w+@\w+/;
	foreach my $sparam ( qw(user_mode user_type) ) {
		while( my($p,$v) = each( %{$sys{$sparam}} ) ) {
			$param->{$p} = $v->{'value'};
		}
	}

	$templates->{'register'}->param($param);
	$templates->{'register'}->param($self->{'qdata'}->{'user_state'});
	my $out = decode_utf8($templates->{'register'}->output());
	return $out
}
#############################
sub hash_door {				# Open door to user cabinet by hash reference
#############################
my $self = shift;
my $action = shift;
	my $param = $self->{'qdata'}->{'http_params'}->{'data'};
	my $udata = $self->{'qdata'}->{'user_state'};
	my $message;
	return $message unless -e("$Drive::sys_root$sys{'mail_dir'}/$action.tmpl");

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
					'site_name' => $sys{'our_site'}, 'site_url' => $sys{'our_host'},
					'timeout' => $sys{'reg_timeout'} 
				};
	my $banner;
	my $letter;
	eval {
		$letter = HTML::Template->new( filename => "$Drive::sys_root$sys{'mail_dir'}/$action.tmpl",
						die_on_bad_params => 0,
						die_on_missing_include => 0,
					);
		};

	return $@ unless $letter;
	$letter->param( $mdata );
	eval {
		$letter = decode_utf8( $letter->output() );
		};
	if ( $@ ) {
		$self->logger->dump("Decode letter: $@", 3);
		return $@;
	}

	my $dom = Mojo::DOM->new($letter);				# Extract something from letter
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

	if ( $sys{'smtp_host'} ) {			# sysd.conf settings
		my ($usr, $pwd) = split(/:/, $sys{'smtp_login'} );
		if ( $usr && $pwd ) {
			$msg->send('smtp', $sys{'smtp_host'}, Debug=>1, AuthUser=>$usr, AuthPass=>$pwd );	# Send via Authorized smtp
		} else {
			$msg->send('smtp', $sys{'smtp_host'}, Debug=>1 );			# Send via free smtp
		}
	} else {
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
