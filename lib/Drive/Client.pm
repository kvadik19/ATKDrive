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
use Utils::Tools;
use Drive::Media;
use Drive::Support;

our $templates;
our $pages;
our $my_name = 'client';
our $sys = \%Drive::sys;
my $uncheck = 'logout';

use Data::Dumper;

#####################
sub checkin {		#		Operations without authorization
#####################
my $self = shift;
	my $udata = $self->{'qdata'}->{'user_state'};
	my $param = $self->{'qdata'}->{'http_params'};
	return $self->checked() if $udata->{'logged'} == 1;

	my $logtime = time;
	my $template = 'client/checkin';
	$self->{'qdata'}->{'tags'}->{'page_title'} = '';

	if ( $param->{'code'} ) {			# Login panel buttons operations
		unless ( $param->{'data'}->{'fp'} eq $udata->{'fp'} ) {
			$self->redirect_to( 'cabinet', query => $param );
			return;
		}
		my $json = {'code' => $param->{'code'}, 'data' => { %{$param->{'data'}} } };		# Copy, not reference!
		$json->{'data'}->{'state'} = 0;

		if ( $param->{'code'} eq 'checkin' ) {				# Buttons on login panel
			if ( $param->{'data'}->{'action'} eq 'login' ) {
				$json->{'data'}->{'state'} = $self->login_status();

			} elsif( $param->{'data'}->{'action'} eq 'register' ) {
				$json->{'data'}->{'point'} = $self->url_with('/register')->query($param->{'data'})->to_abs;

			} elsif( $param->{'data'}->{'action'} eq 'reset' ) {
				$json->{'data'}->{'html_code'} = $self->hash_door( $param->{'data'}->{'action'} );
			}

		} elsif( $param->{'code'} eq 'apply') {			# Store user defined login/password
			my $verify_state = $sys->{'user_state'}->{'verify'}->{'value'};
			my $sql = "UPDATE users SET ".
						"_login='".Drive::mysqlmask($param->{'data'}->{'login'})."',".
						"_pwd='".md5_sum($param->{'data'}->{'pwd'})."',".
						"_fp='$udata->{'cookie'}->{'fp'}',".
						"_ltime='$logtime',".
						"_hash='',".
						"_ustate=IF(_ustate>$verify_state,_ustate,$verify_state) ".
					"WHERE _uid='$param->{'data'}->{'uid'}'";

			eval { $self->dbh->do( $sql ) };
			if ( $@ ) {
				$self->logger->dump($sql, 2, 1);
				$json->{'data'}->{'success'} = 0;
				$json->{'fail'} = $@;
			} else {
				$json->{'data'}->{'success'} = 1;
				$udata->{'logged'} = 1;
				$udata->{'cookie'}->{'uid'} = $param->{'data'}->{'uid'};		# Mark as logged in
			}

		} elsif( $param->{'code'} eq 'find') {				# Search something in `users`
			$json->{'data'} = {};
			my $qry;
			my $got;
			while( my ($fld,$val) = each( %{$param->{'data'}}) ) {
				next if $fld eq 'fp';		# Omit special parameter
				$qry .= " AND $fld='$val'";
			}
			$qry =~ s/^ AND //;
			eval { $got = $self->dbh->selectrow_arrayref("SELECT _uid FROM users WHERE $qry LIMIT 0,1") };
			$json->{'data'} = {'got' => scalar(@$got) } if $got;
			$json->{'fail'} = $@ if $@;
		}

		$self->render( type => 'application/json', json => $json );
		return;

	} elsif ( $param->{'h'} && $param->{'t'} ) {			# `Secret url` is used to set/restore login/password
		my $urec;
		my $time = Time::HiRes::time();
		$time -= $sys->{'reg_timeout'} * 60 * 60;

		my $ustate;
		while ( my ($key, $val) = each( %{$sys->{'user_state'}} ) ) {
			$ustate->{$key} = $val->{'value'};
		}
		if ($time <= $param->{'t'}) {			# Check for link actuality
			my $hash = $param->{'h'}.md5_sum($param->{'t'});
			$urec = $self->dbh->selectall_arrayref("SELECT * FROM users WHERE _hash='$hash'", {Slice=>{}})->[0];
			$urec->{'reject'} = $param->{'r'} if $param->{'r'};
										# User has rejected our registration. SOME ACTIONS ALSO MUST BE HERE!
		}
		$self->stash( 'udata' => $urec,
					'ustate' => $ustate,
					'referer' => $param->{'m'},
					'sys' => $sys,
					);
		$template = 'client/hashref'
	}

	$self->render( template => $template, status => $self->stash('http_state') );
}
#################
sub checked {	# All of operations dispatcher for authorized user
#################
my $self = shift;
	my $udata = $self->{'qdata'}->{'user_state'};
	my $param = $self->{'qdata'}->{'http_params'};
	if ( $self->{'qdata'}->{'stack'}->[0] && $uncheck =~ /$self->{'qdata'}->{'stack'}->[0]/ ) {
		# Some url must be passed as-is

	} elsif ( $udata->{'logged'} == 1 ) {
		my $urec = $self->dbh->selectall_arrayref("SELECT * FROM users WHERE _uid='$udata->{'cookie'}->{'uid'}'", {Slice=>{}})->[0];
		$urec->{'_setup'} = decode_json( $urec->{'_setup'} ) if $urec->{'_setup'} =~ /^\{.+\}$/;
		while ( my ($fld, $val) = each( %$urec) ) {
			$urec->{$fld} = Drive::mysqlmask( $val, 1) if $val =~ /\D/;
		}

		my $upath = $urec->{'_setup'}->{'start'};		# Personal start page for root of site
		$upath =~ s/^\///g;
		$upath = [ split(/\//, $upath) ];
		push( @{$self->{'qdata'}->{'stack'}}, @$upath) unless scalar( @{$self->{'qdata'}->{'stack'}} );

		#### Check user permissions, defined at conf_dir/dict.xml
		my $refstate = { %{$sys->{'user_state'}} };			# Modifying test will be processed, need to use a copy!
		my $permission = Drive::find_hash( $refstate, sub { my $key = shift; 
												return ($refstate->{$key}->{'value'} == $urec->{'_ustate'}); # Modifying hashref!
											});
		$permission = $sys->{'user_state'}->{$permission}->{'allow'};
		if ( $permission eq 'all') {
			# All pages permitted, leave query stack unchanged
		} elsif( $permission eq 'none') {		# Drop logged state, redirect to sign in
			unshift( @{$self->{'qdata'}->{'stack'}}, 'logout');		# Call logging out.

		} elsif( $permission =~ /\b$self->{'qdata'}->{'stack'}->[0]\b/i ) {
			# Permitted page requested, leave query unchanged

		} elsif( $permission =~ /\b$upath->[0]\b/i ) {			# Predefined Start page allowed? Modify query
			$self->{'qdata'}->{'stack'}->[0] = $upath->[0];

		} elsif( $permission ) {			# Some allowed? Modify query to retrieve permitted page
			$self->{'qdata'}->{'stack'}->[0] = [split(/,/, $permission)]->[0];

		} else {				# Undescribed cases
			unshift( @{$self->{'qdata'}->{'stack'}}, 'logout');		# Call logging out.
		}		#### Addreesing Users depending on their permissions 

		$udata->{'record'} = $urec;

	} elsif( $self->{'qdata'}->{'stack'}->[0] ne 'register' ) {		# Not logged can go to registration page, otherwise
		$self->redirect_to( 'cabinet', query => $param );
		return;
	}

	my $action = shift( @{$self->{'qdata'}->{'stack'}} ) || 'account';		# Default user path
	my $template = 'main';

	while ( my($dir, $stat) = each( %{$udata->{'stats'}}) ) {
		$sys->{$dir} = $stat;					# Some extra data to transfer into template
	}
	$self->prepare_tmpl($action);

	my $out = "404 : Page $action not found yet";
	eval { $out = $self->$action };
	if ( $@) {			# Special sub is not defined (yet?)
		$out = $self->process($action);		# Process queries based on template
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
sub prepare_tmpl {	# Prepare template
#################
my $self = shift;
my $tmpname = shift;
	my $tmplfile = "$Drive::sys_root$sys->{'html_dir'}/$tmpname.tmpl";
	my $qryfile = "$Drive::sys_root$sys->{'conf_dir'}/query/$tmpname.json";

	my $query_load = sub { my $ttxt = shift;
								my $dom = Mojo::DOM->new( $ttxt );
								my $define = Drive::Support->template_map( $tmpname);
								my $tmpl_json = Drive::Support->dom_json( $dom);
								my $json_sync = Drive::Support->json_sync( $define->{'init'}->{'qw_recv'}->{'data'}, $tmpl_json);
								$define->{'init'}->{'qw_recv'}->{'data'} = $json_sync;
								return $define;
						};
	
	my $tmpl_load = sub  { open( my $th, "< $tmplfile");
							my $ttxt = decode_utf8(join('', <$th>));
							close( $th);
							my $templ;
							eval {
								$templ = HTML::Template->new(
										scalarref => \$ttxt,
										die_on_bad_params => 0,
										die_on_missing_include => 0,
									);
								};
							if ( $@ ) {
								$self->logger->dump("Template $tmpname: $@");
								$templ = "<h1>Error loading $tmpname:</h1><p class=\"fail\">$@</p>";
							} else {
								my $query = $query_load->( $ttxt );
								$templates->{$tmpname} = {
													'tmpl' => $templ, 
													'query' => $query,
													'upd' => {'tmpl' => (stat($tmplfile))[9],
																'query' => (stat($qryfile))[9],
															},
												};
							}
							return $ttxt;
						};

	if ( $templates->{$tmpname} ) {
		if ( $templates->{$tmpname}->{'upd'}->{'tmpl'} < (stat($tmplfile))[9] ) {			# Is too old template definition?
			$tmpl_load->();
		}
		if ( $templates->{$tmpname}->{'upd'}->{'query'} < (stat($qryfile))[9] ) {
			open( my $th, "< $tmplfile");
			my $ttxt = decode_utf8(join('', <$th>));
			close( $th);
			$templates->{$tmpname}->{'query'} = $query_load->( $ttxt);		# Load translaton map for template
			$templates->{$tmpname}->{'upd'}->{'query'} = (stat($qryfile))[9];
		}
	} elsif( -f( $tmplfile ) ) {
		$tmpl_load->();
	} else {
		$self->logger->dump("Template for $tmpname not found", 3);
	}
}
#################
sub process {	# Main user operations form
#################
my $self = shift;
my $action = shift;
my $out = {'html_code' => "<div class=\"container\"><h1>$action is not implemented yet</h1></div>", 'http_state' => 404 };
	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};

	if ( $templates->{$action} && $templates->{$action}->{'tmpl'} ) {
		if ( $self->req->content->headers->content_type eq 'application/x-www-form-urlencoded' 
				&& $param->{'code'} ) {
$self->logger->dump("Process ajax $action/$param->{'code'}");
		} else {
$self->logger->dump("Process init for $action");
			my $qw_send = $templates->{$action}->{'query'}->{'init'}->{'qw_send'};
			Drive::Support->apply_user( $qw_send, $udata->{'record'} );
$self->logger->dump(Dumper($qw_send));
		}

		$templates->{$action}->{'tmpl'}->param($param);
		$templates->{$action}->{'tmpl'}->param($udata);
		$templates->{$action}->{'tmpl'}->param($sys);
		$templates->{$action}->{'tmpl'}->param($udata->{'record'});
		$out = $templates->{$action}->{'tmpl'}->output();
		my $dom = Mojo::DOM->new( $out );
		my $title = $dom->find('h1')->[0];
		$self->{'qdata'}->{'tags'}->{'page_title'} = $title->text() if $title;
	} else {
		$self->logger->dump("Undefined processor for '$action'", 3);
	}

	return $out;
}
#################
sub account {	# Setup user account form
#################
my $self = shift;
my $out;

	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};

	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";

	my $struct = [];
	$struct = Drive::read_xml( $conf_file, 'config' )->{'utable'};

	if ( $param->{'code'} ) {
		$out = { 'json' => {'code' => $param->{'code'}} };
		if ( $param->{'code'} eq 'rpwd' ) {
			my $pwold = md5_sum($param->{'data'}->{'pwd'});
			my $pwnew = md5_sum($param->{'data'}->{'pwd1'});
			my $res = $self->dbh->do("UPDATE users SET _pwd=? WHERE _uid=? AND _pwd=?",
													undef, $pwnew, $udata->{'cookie'}->{'uid'}, $pwold  );
			$out->{'json'}->{'data'} = {'success' => $res};

		} elsif ( $param->{'code'} eq 'checkmail' ) {		# Precheck email address
			$out->{'json'} = $self->check_email( $param->{'data'}->{'email'});

		} elsif( $param->{'code'} eq 'commit' ) {
			$out->{'json'} = $self->udata_commit( $udata->{'cookie'}->{'uid'} );
		}

	} else {
		foreach my $sparam ( qw(user_mode user_type) ) {		# Add some defined codes
			while( my($p,$v) = each( %{$sys->{$sparam}} ) ) {
				$param->{$p} = $v->{'value'};
			}
		}
		if ( $udata->{'record'}->{'_umode'} == $sys->{'user_mode'}->{'both'}->{'value'} ) {
			$param->{"carrier_mark"} = 'checked';
			$param->{"customer_mark"} = 'checked';			## Markup checkboxes
		} else {
			while ( my($mod, $def) =  each( %{$sys->{'user_mode'}} ) ) {
				if ( $udata->{'record'}->{'_umode'} == $def->{'value'} ) {
					$param->{"$mod\_mark"} = 'checked';
				}
			}
		}

		my $umedia = Drive::Media->medialist( qdata => $self->{'qdata'}, dbh => $self->dbh, logger => $self->logger );
		$param->{'uploads'} = [grep { $_->{'type'} eq 'file' } @$struct];
		$param->{'session'} = $udata->{'fp'};

		foreach my $row ( @{$param->{'uploads'}} ) {
			$row->{'list'} = [grep { $_->{'owner_field'} eq $row->{'name'} } @$umedia];
		}
		$templates->{'account'}->{'tmpl'}->param($param);
		$templates->{'account'}->{'tmpl'}->param($sys);
		$templates->{'account'}->{'tmpl'}->param($udata->{'record'});
		$out = $templates->{'account'}->{'tmpl'}->output();

		my $dom = Mojo::DOM->new( $out );
		my $title = $dom->find('h1')->[0];
		$self->{'qdata'}->{'tags'}->{'page_title'} = $title->text() if $title;


	}
	return $out;
}
#################
sub udata_commit {		# Save registration/personal data form
#################
my $self = shift;
my $uid = shift;
	my $out = {'code' => 0};			# JSON will be returned
	my $now = time;
	my $exists = ( $uid > 0);

	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};

	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";

	my $struct = [];
	$struct = Drive::read_xml( $conf_file, 'config' )->{'utable'};

	my $db_update = {'_ustate' => $udata->{'record'}->{'_ustate'} || $sys->{'user_state'}->{'register'}->{'value'},
					'_fp' => $udata->{'fp'},
					'_rtime' => $now,
					'_ltime' => $now,
					'_ip' => $udata->{'ip'}
					};
	foreach my $fld ( @$struct ) {				# Store only storable values!
		if ( exists( $param->{'data'}->{$fld->{'name'}}) ) {
			my $val = $param->{'data'}->{$fld->{'name'}};
			$val =~ s/([\'%;])/'%'.unpack( 'H*', $1 )/eg if $fld->{'type'} =~ /^char/;
			$db_update->{$fld->{'name'}} = $val;
		}
	}

	my $sql;
	if ( $exists) {
		delete( $db_update->{'_fp'});
		delete( $db_update->{'_rtime'});
		my $updata;
		while ( my($fld, $val) = each(%$db_update) ) {
			$updata .= ",$fld='$val'";
		}
		$updata =~ s/^,//;
		$sql = "UPDATE users SET $updata WHERE _uid=$uid";
	} else {
		my $fields = '';
		my $values = '';
		while ( my($fld, $val) = each(%$db_update) ) {
			$fields .= ",$fld";
			$values .= ",'$val'";
		}
		$fields =~ s/^,//;
		$values =~ s/^,//;
		$sql = "INSERT INTO users ($fields) VALUES ($values)";
	}

	eval {	$self->dbh->do($sql);
			$uid = $self->dbh->selectrow_arrayref( "SELECT _uid FROM users WHERE _fp='$udata->{'fp'}'")->[0] unless $exists;
		};

	if ( $@ ) {
		$out->{'fail'} = $@;
		$self->logger->dump("Update user data: $@", 2);

	} elsif( $uid > 0 ) {			# Only when successed
		$out->{'data'}->{'html_code'} = $self->hash_door( 'register', $uid ) unless $exists;
		$out->{'code'} = 1;

		my $mres = Drive::Media->filesync( qdata => $self->{'qdata'}, dbh => $self->dbh, logger => $self->logger );
		if ( $mres ) {
			$out->{'code'} = 0;
			while ( my($k,$v) = each(%$mres) ) {
				$out->{$k} = $v;
			}
		}

	}			# Success users table update?
	return $out;
}
#################
sub check_email {		# Chack email availability
#################
my $self = shift;
my $email = shift;
	my $out = {'data' => {'email' => lc($email) } };
	$out->{'code'} = Utils::Tools->email_good( \$out->{'data'}->{'email'} );
	my $exists = $self->dbh->selectcol_arrayref("SELECT _uid FROM users WHERE _email='$out->{'data'}->{'email'}'"
										." AND NOT _uid='$self->{'qdata'}->{'user_state'}->{'cookie'}->{'uid'}'");
	$out->{'data'}->{'warn'} = 'exists '.scalar(@$exists) if scalar(@$exists);		# Check early used email
	return $out;
}
#################
sub register {		# User registration/personal data form
#################
my $self = shift;
my $out;
	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};

	if ( $udata->{'logged'} == 1 ) {
		$self->prepare_tmpl('account');			# If Not loaded yet
		return $self->account();
	}

	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";
	my $now = time();

	my $struct = [];
	$struct = Drive::read_xml( $conf_file, 'config' )->{'utable'};

	if ( $param->{'code'} ) {			# AJAX request received?
		$out = {'json' => {'code' => 0}};			# JSON will be returned
		my $param_fp = $param->{'fp'} || $param->{'data'}->{'fp'};			# Must have 2-way fingerprint
		return $out unless $udata->{'fp'} eq $param_fp;

		if ( $param->{'code'} eq 'checkmail' ) {		# Precheck email address
			$out->{'json'} = $self->check_email( $param->{'data'}->{'email'});

		} elsif( $param->{'code'} eq 'commit' ) {
			$out->{'json'} = $self->udata_commit(0);
		}

	} else {			# Prepare html for page
		$param->{'_uid'} = 0;
		$param->{'session'} = $udata->{'fp'};
		$param->{'uploads'} = [ grep { $_->{'type'} eq 'file' } @$struct ];
		$param->{'email'} = $param->{'login'} if $param->{'login'} =~ /\w+@\w+/;
		foreach my $sparam ( qw(user_mode user_type) ) {
			while( my($p,$v) = each( %{$sys->{$sparam}} ) ) {
				$param->{$p} = $v->{'value'};
			}
		}
		$templates->{'register'}->{'tmpl'}->param($param);
		$templates->{'register'}->{'tmpl'}->param($self->{'qdata'}->{'user_state'});
		$out = $templates->{'register'}->{'tmpl'}->output();
		my $dom = Mojo::DOM->new( $out );
		my $title = $dom->find('h1')->[0];
		$self->{'qdata'}->{'tags'}->{'page_title'} = $title->text() if $title;

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
	return $message unless -e("$Drive::sys_root$sys->{'mail_dir'}/$action.tmpl");

	my $timestamp = Time::HiRes::time();
	my $hash = $udata->{'fp'}.md5_sum($timestamp);
	my $hashlink = "$udata->{'proto'}://$udata->{'host'}?h=$udata->{'fp'}&t=$timestamp";

	my $mdata = {'link_accept' => $hashlink, 'link_reject' => "$hashlink&r=1",
					'site_name' => $sys->{'our_site'}, 'site_url' => $sys->{'our_host'},
					'timeout' => $sys->{'reg_timeout'}, 
				};
	my $where;
	if ( $uid ) {
		$where = "_uid='$uid'";
		$mdata->{'_email'} = $param->{'_email'};
		$mdata->{'_ustate'} = $sys->{'user_state'}->{'confirm'}->{'value'};
		$mdata->{'_login'} = '';
	} else {
		my $urec = $self->get_login( $param->{'login'}, $param->{'pwd'} );
		if ( $urec->{'state'} == 3 ) {			# login match
			$where = "_login='$param->{'login'}'";
		} elsif( $urec->{'state'} == 4 ) {			# email match
			$where = "_email='$param->{'login'}'";
		}
		$mdata->{'_ustate'} = $urec->{'_ustate'};			# User always registered on gate
		$mdata->{'_email'} = $urec->{'_email'};
		$mdata->{'_login'} = $urec->{'_login'};
	}

	my $banner;
	my $letter;
	eval {
		$letter = HTML::Template->new( filename => "$Drive::sys_root$sys->{'mail_dir'}/$action.tmpl",
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

	if ( $sys->{'smtp_host'} ) {			# sysd.conf settings
		my ($usr, $pwd) = split(/:/, $sys->{'smtp_login'} );
		if ( $usr && $pwd ) {
			$msg->send('smtp', $sys->{'smtp_host'}, Debug=>1, AuthUser=>$usr, AuthPass=>$pwd );	# Send via Authorized smtp
		} else {
			$msg->send('smtp', $sys->{'smtp_host'}, Debug=>1 );			# Send via free smtp
		}
	} else {
		$msg->send();			# Send via sendmail
	}
	$self->dbh->do("UPDATE users SET _hash='$hash',_ip='$udata->{'ip'}',_ustate='$mdata->{'_ustate'}' WHERE $where");

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
	$login = Drive::mysqlmask( $login);
	$pwd = md5_sum( $pwd);
	my $flist = '_uid,_fp,_email,_login,_pwd,_ustate';
	my $sql = "SELECT 1 AS state,$flist FROM users WHERE _login='$login' AND _pwd='$pwd'";
	$sql .= " UNION SELECT 2 AS state,$flist FROM users WHERE LOWER(_email)='".lc($login)."' AND _pwd='$pwd'";
	$sql .= " UNION SELECT 3 AS state,$flist FROM users WHERE _login='$login'";
	$sql .= " UNION SELECT 4 AS state,$flist FROM users WHERE LOWER(_email)='".lc($login)."'";
	my $urec = $self->dbh->selectall_arrayref($sql, {Slice=>{}});
	return shift( @$urec );
}
#################
sub logout {	# Close user connection
#################
my $self = shift;
	$self->{'qdata'}->{'user_state'}->{'cookie'}->{'uid'} = 0;
	$self->{'qdata'}->{'user_state'}->{'cookie'}->{'fp'} = '';
	return {'redirect' => 'cabinet'};
}
1
