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
use File::Path qw(make_path mkpath remove_tree rmtree);
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
my $out;
	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";
	my $now = time();

	my $struct = [];
	$struct = Drive::read_xml( $conf_file, 'config', 'to_encode' )->{'utable'};

	if ( $param->{'code'} ) {			# AJAX request received?
		$out = {'json' => {'code' => 0}};			# JSON will be returned

		if ( $param->{'code'} eq 'checkmail'  
				&& $udata->{'fp'} eq $param->{'data'}->{'fp'} ) {		# Precheck email address
			$out->{'json'}->{'data'} = {'email' => $param->{'data'}->{'email'}};
			$out->{'json'}->{'code'} = Utils::NETS->email_good( \$out->{'json'}->{'data'}->{'email'} );
			my $exists = $self->dbh->selectrow_arrayref("SELECT _uid FROM users WHERE _email='$out->{'json'}->{'data'}->{'email'}'");
			$out->{'json'}->{'data'}->{'warn'} = 'exists' if $exists;		# Check early used email

		} elsif( $param->{'code'} eq 'rm' 
				&& $udata->{'fp'} eq $param->{'fp'} ) {		# Remove uploaded
			$out->{'json'}->{'filename'} = $param->{'filename'};
			my $fname = "$Drive::sys_root$sys{'user_dir'}/$param->{'session'}/$param->{'field'}/$param->{'filename'}";
			if ( -e($fname) ) {
				if ( unlink($fname) ) {
					$out->{'json'}->{'code'} = 1;
				} else {
					$out->{'json'}->{'fail'} = $!;
				}
			} else {
				$out->{'json'}->{'fail'} = "File not found";
			}
			
		} elsif( $param->{'code'} eq 'upload' 
				&& $udata->{'fp'} eq $param->{'fp'} ) {
			my $up_dir = "$Drive::sys_root$sys{'user_dir'}/$param->{'session'}/$param->{'name'}";
			mkpath( $up_dir, { mode => 0775 } ) unless -d( $up_dir );		# Prepare storage, if need
			my $done = $self->getUpload($up_dir);
			if ( ref($done) eq 'ARRAY' ) {
				open( my $fh, "+>> $Drive::sys_root$sys{'user_dir'}/$param->{'session'}/mime.types" );
				foreach my $frow ( @$done ) {			# Some postflights
					print $fh "$param->{'name'}/$frow->{'filename'}\t$frow->{'mime'}\n";
					$frow->{'field'} = $param->{'name'};
					$frow->{'url'} = $sys{'user_dir'};
					$frow->{'url'} =~ s/^$sys{'url_prefix'}//;
					$frow->{'url'} = "$frow->{'url'}/$param->{'session'}/$param->{'name'}/$frow->{'filename'}";
				}
				close($fh);
				$out->{'json'}->{'data'} = $done ;
				$out->{'json'}->{'code'} = scalar(@$done);
			} else {
				$out->{'json'}->{'fail'} = $done;
			}

		} elsif( $param->{'code'} eq 'register' 
				&& $udata->{'fp'} eq $param->{'data'}->{'fp'} ) {
			my $fields = '_ustate,_fp,_rtime,_ltime,_ip';
			my $values = "'$sys{'user_state'}->{'register'}->{'value'}','$udata->{'fp'}',$now,$now,$udata->{'ip'}";
			foreach my $fld ( @$struct ) {
				if ( exists( $param->{'data'}->{$fld->{'name'}}) ) {
					$fields .= ",$fld->{'name'}";
					my $val = $param->{'data'}->{$fld->{'name'}};
					$val = Drive::mysqlmask( $val ) if $fld->{'type'} =~ /^char/;
					$values .= ",'$val'";
				}
			}
			eval { $self->dbh->do("INSERT INTO users ($fields) VALUES ($values)") };
			if ( $@ ) {
				$out->{'json'}->{'fail'} = $@;
				$self->logger->dump("New user: $@", 2);
			} else {
				my $uid = $self->dbh->{'mysql_insertid'};
$self->logger->dump("Got uid $uid");

				$out->{'json'}->{'data'}->{'html_code'} = $self->hash_door( $param->{'code'}, $uid );
				$out->{'json'}->{'code'} = 1;

				my $up_dir = "$Drive::sys_root$sys{'user_dir'}";
				my $mimes;
				if ( -e("$up_dir/$param->{'data'}->{'session'}/mime.types") ) {
					open( my $fh, "< $up_dir/$param->{'data'}->{'session'}/mime.types" );
					$mimes = [<$fh>];
					close( $fh);
				}
				my $fields = 'owner_id,owner_field,ord,uptime,filename,mime';
				my $values;
				my $cnt = 0;
				foreach my $file ( @{$param->{'data'}->{'files'}} ) {			# Move newly uploaded files onto place
					my $fname = $file->{'name'};
					if ( -e( "$up_dir/$param->{'data'}->{'session'}/$file->{'field'}/$fname" ) ) {
						my $idx = Drive::find_first( $mimes, sub { my $fr = shift;
													return $fr =~ /^$file->{'field'}\/$fname/;
												} );
						if ( $idx > -1 ) {				# Ignore files without mimetype
							chomp( $mimes->[$idx] );
							$values .= "($uid,'$file->{'field'}',$cnt,$now,'"
											.Drive::mysqlmask( $fname )
											."','"
											.substr( $mimes->[$idx], rindex($mimes->[$idx], "\t")+1 )
											."'),";
							mkpath( "$up_dir/$uid/$file->{'field'}", { mode => 0775 } ) unless -d( "$up_dir/$uid/$file->{'field'}" );
							rename("$up_dir/$param->{'data'}->{'session'}/$file->{'field'}/$fname",
												"$up_dir/$uid/$file->{'field'}/$fname");
							$cnt++;
						}
					} else {
$self->logger->dump("Not -e $up_dir/$param->{'data'}->{'session'}/$file->{'field'}/$fname");
					}
				}
				if ( $values ) {
					$values =~ s/,$//;
					eval { $self->dbh->do("INSERT INTO media ($fields) VALUES $values") };
					if ( $@ ) {
						$out->{'json'}->{'warn'} = $@;
						$self->logger->dump("Media store: $@", 2);
						$out->{'json'}->{'code'} = 0;
					}
				}
			}			# Success users table update?
		}

	} else {			# Prepare html for page
		$param->{'session'} = $udata->{'fp'};
		$param->{'uploads'} = [ grep { $_->{'type'} eq 'file' } @$struct ];
		$param->{'email'} = $param->{'login'} if $param->{'login'} =~ /\w+@\w+/;
		foreach my $sparam ( qw(user_mode user_type) ) {
			while( my($p,$v) = each( %{$sys{$sparam}} ) ) {
				$param->{$p} = $v->{'value'};
			}
		}

		$templates->{'register'}->param($param);
		$templates->{'register'}->param($self->{'qdata'}->{'user_state'});
		$out = decode_utf8($templates->{'register'}->output());

	}
	return $out
}
#############################
sub hash_door {				# Open door to user cabinet by hash reference
#############################
my $self = shift;
my $action = shift;
my $uid = shift;
	my $param = $self->{'qdata'}->{'http_params'}->{'data'};
	my $udata = $self->{'qdata'}->{'user_state'};
	my $message;
	return $message unless -e("$Drive::sys_root$sys{'mail_dir'}/$action.tmpl");

	my $timestamp = Time::HiRes::time();
	my $hash = $udata->{'fp'}.md5_sum($timestamp);
	my $hashlink = "$udata->{'proto'}://$udata->{'host'}/cabinet?h=$udata->{'fp'}&t=$timestamp";

	my $mdata = {'link_accept' => $hashlink, 'link_reject' => "$hashlink&r=1",
					'site_name' => $sys{'our_site'}, 'site_url' => $sys{'our_host'},
					'timeout' => $sys{'reg_timeout'}, 
				};
	my $where;
	if ( $uid ) {
		$where = "_uid='$uid'";
		$mdata->{'_email'} = $param->{'_email'};
		$mdata->{'_login'} = '';
	} else {
		my $urec = $self->get_login( $param->{'login'}, $param->{'pwd'} );
		if ( $urec->{'state'} == 3 ) {			# login match
			$where = "_login='$param->{'login'}'";
		} elsif( $urec->{'state'} == 4 ) {			# email match
			$where = "_email='$param->{'login'}'";
		}
		$mdata->{'_email'} = $urec->{'_email'};
		$mdata->{'_login'} = $urec->{'_login'};
	}

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
			To => encode( 'MIME-Header', $mdata->{'_login'})." <$mdata->{'_email'}>",
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
sub getUpload {				# Decompose file uploads
#############################
my $self = shift;
my $path = shift;
my $res;
	if ( $self->req->{'finished'} ) {
		foreach my $part ( @{$self->req->content->parts} ) {
			my $finfo;
			my $descriptor = $part->headers->content_disposition;
			foreach my $data ( (split(/;/, $descriptor)) ) {
				next unless $data =~ /=/;
				my ($name, $value) = split(/=/, $data);
				$name =~ s/^\s+|\s+$//g;
				$value =~ s/^["']|["']$//g;
				$finfo->{$name} = decode_utf8($value);
			}

			if ( $finfo->{'filename'} ) {
				eval { $part->asset->move_to("$path/$finfo->{'filename'}") };
				if ( $@ ) {
					$res = $@;
					last;
				}
				chmod(0666, "$path/$finfo->{'filename'}");
				push( @$res, {'filename' => $finfo->{'filename'}, 'size'=> $part->asset->size(),
							'mime' => $part->headers->content_type} );
			}
		}		# For each parts

	} else {
		$res = "Upload not finished";
	}
	return $res;
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
