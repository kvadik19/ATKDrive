package Drive;
use Mojo::Base 'Mojolicious';
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Transaction::WebSocket;
use FindBin;
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape b64_encode  trim md5_sum);
use Fcntl qw(:flock SEEK_END);
use Utils::LOGGY;
use Utils::DATER;
use Time::HiRes;
require 'Drive/funcs.pl';

use Data::Dumper;

use strict;
use utf8;

use DBI;

our %sys;
our $sys_root;
our $logger;
our $dbh;
our $gate_config;
our $translate;
our $our_timezone = `cat /etc/timezone` || 'Europe/Moscow';
our $our_locale = `locale | head -n1` || 'ru_RU';
our $dict_fields = {'user_mode'=>'_umode', 
					'user_state'=>'_ustate', 
					'user_type'=>'_usubj', 
					'_umode'=>'user_mode', 
					'_ustate'=>'user_state', 
					'_usubj'=>'user_type'};		# Define relations betweed dict.xml values and `users` table fields

#################
sub startup {
#################
	my $self = shift;
# kill( 'SIGUSR2', $mypid)
# 	$ENV{'MOJO_MAX_LINES'} = 150;
# 	$ENV{'MOJO_MAX_LINE_SIZE'} = 16384;
	$self->config( hypnotoad => { listen => [ "http://127.0.0.1:9021",
											"https://127.0.0.1:9020" ],	# Need to be set in nginx map directive
								workers => 2,		# two worker processes per CPU core
								spare => 8,
								proxy => 0,
								} );
	$self->plugin('DefaultHelpers');
	$self->secrets( ['sug4hyg327ah243Hhjck'] );
# 	$self->plugin('PODRenderer');
	$sys_root = "$FindBin::Bin/..";

	$our_locale = substr($our_locale, index($our_locale,'=')+1);
	chomp($our_timezone);
	chomp($our_locale);
	
	my $ws = Mojo::Transaction::WebSocket->new();
	my $r = $self->routes;

	$r->websocket('/channel')->to( controller => 'support', action => 'wsocket', )->name('wsocket');
	$r->any('/channel')->to( controller => 'support', action => 'hsocket', )->name('hsocket');
	$r->route('/channel/media/*path')->to(controller => 'media', action => 'admin_media');

	$r->route('/media')->to(controller => 'media', action => 'operate');
	$r->route('/media/*path')->to(controller => 'media', action => 'operate');

	$r->route('/drive')->to(controller => 'support', action => 'hello')->name('admin');
	$r->route('/drive/*path')->to(controller => 'support', action => 'support');

	$r->route('/')->to(controller => 'client', action => 'checkin')->name('cabinet');
	$r->route('/*path')->to(controller => 'client', action => 'checked');

	%sys = readcnf("$sys_root/lib/Drive/sysd.conf");
	add_xml( \%sys, "$sys_root/$sys{'conf_dir'}/dict.xml", 'sys');		# Some dictionaries

	our $mimeTypes = {
				'ttf'=>'application/x-font-ttf', 'ttc'=>'application/x-font-ttf', 'otf'=>'application/x-font-opentype', 
				'woff'=>'application/font-woff', 'woff2'=>'application/font-woff2', 'svg'=>'image/svg+xml',
				'tif'=>'image/tiff', 'tiff'=>'image/tiff', 'bmp'=>'image/x-ms-bmp','json'=>'application/json',
				'jpg'=>'image/jpeg', 'jpeg'=>'image/jpeg', 'jpe'=>'image/jpeg', 'png'=>'image/png', 'gif'=>'image/gif',
				'sfnt'=>'application/font-sfnt', 'eot'=>'application/vnd.ms-fontobject','zip'=>'application/zip', 
				};
	while ( my($ext, $type) = each(%$mimeTypes) ) {		# Add mime types for render
		$self->types->type( $ext => $type );
	}

	$logger = LOGGY->new(
			filename => "$sys_root$sys{log_dir}/drive.log",
			loglevel => $sys{'loglevel'},
			max_size => $sys{'logsize'},
			log_cycle => $sys{'logcycle'}
		);

	$self->helper( logger => sub { return $logger } );
	$self->helper( hostConfig => sub  { return $self->hostConfig });		#		Load/renew configuration
	$self->helper( translate_keys => sub  { return $self->translate_keys });		#		Load/renew translation table

	my @db_str = ( $sys{'db_base'},
					$sys{'db_host'} || 'localhost:3306',
				);
	($sys{'db_usr'}, $sys{'db_pwd'}) = split(/:/, $sys{'db_user'});
	my $db_connect = {	'string' => "DBI:mysql:".join(':', @db_str),
						'user' => $sys{'db_usr'}, 
						'pwd' => $sys{'db_pwd'},
						};		# Need to be tuned up by config files!!!

	my $create_dbh = sub {
						return DBI->connect($db_connect->{'string'}, $db_connect->{'user'}, $db_connect->{'pwd'},
										{mysql_enable_utf8 => 1,PrintError => 0, RaiseError => 1});
					};
	my $reconnect = sub {			# Re-estabilish MySQL connect dropped by timeout error
						my $self = shift;
						eval {  $Drive::dbh->do( "SET NAMES $sys{'db_encoding'}" )  };	# Execute dummy query
						$self->logger->debug("DB reconnect: $Drive::dbh->{'mysql_errno'} $@") if $@;
						my $try = 3;
						my $error = $Drive::dbh->{'mysql_errno'};
						while ( '-2006-2013-' =~ /\.$error\./ && $try -- ) {		# Server closed connection by timeout
# 							sleep(5);		# Wait for possible system self-recover (such as mysql restarts)
							$Drive::dbh = $create_dbh->();
							eval { $self->helper(dbh => $Drive::dbh) };
							eval { $Drive::dbh->do("SET NAMES $Drive::sys{'db_encoding'}") };
							$self->logger->debug("DB re-reconnect: $Drive::dbh->{'mysql_errno'} $@") if $@;
							$error = $Drive::dbh->{'mysql_errno'};
						}
						return $Drive::dbh->{'mysql_error'} if $Drive::dbh->{ 'mysql_error' };
						return undef;
					};
	$self->helper(dbh => $create_dbh );							# Because need DB handler in every forked subprocesses!
	$self->helper(db_reconnect => $reconnect );
	$dbh = $self->dbh;

	my $default_tags = {'site_name' => decode_utf8($sys{'our_site'})};

	$self->hook( before_dispatch => sub {
						my $self = shift;
						$logger->debug(">>>> ".$self->req->headers->every_header('x-real-ip')->[0]." => ".
											$self->req->method.": ".$self->req->url->base.$self->req->url->path );
						
						foreach my $dir ( qw(js css img) ) {			# Compose js/css version numbers to prevent browser caching
							$self->{'stats'}->{$dir} = ( stat($sys_root.$sys{"$dir\_dir"}))[9];
						}
						$self->{'qdata'} = query_data($self);
						my @date = timestr();
						$default_tags->{'years'} = $date[0];
						$default_tags->{'years'} = "2021-$default_tags->{'years'}" if $default_tags->{'years'} ne '2021';
						$self->stash(
								user => $self->{'qdata'}->{'user_state'},
								main_menu => {'path' => undef, 'list' => []},
								encoding => $sys{'encoding'},
								html_code => $self->{'qdata'}->{'html_code'},
								http_state => 200,
								tags => $default_tags,
								sys => \%sys,
								stats => $self->{'stats'},
								fail => $self->{'qdata'}->{'fail'},
							);
						$self->layout('default');
					}
			);
	$self->hook( before_render => sub {
						my ($self, $args ) = @_;
						if ( $self->{'qdata'}->{'layout'} ) {		# Omit default layout
							$self->layout( $self->{'qdata'}->{'layout'});
						}
						if ( $self->{'qdata'}->{'tags'} ) {			# Embed some data into template
							my $tags = $self->stash('tags');
							while ( my ($name,$value) = each(%{$self->{'qdata'}->{'tags'}}) ) {
								$tags->{$name} = $value;
							}
							$self->stash(tags => $tags);
						}
						my $domain = $self->req->url->base;
						$domain = substr( $domain, rindex($domain, '/')+1 );
						while ( my($cook, $val) = each( %{$self->{'qdata'}->{'user_state'}->{'cookie'}}) ) {
							next if $cook =~ /^__/;			# Cookie for browser only!
							my $opts = {'expires' => time + 176*24*60*60, 'domain' => $domain, 'path' => '/', };
							if( $val =~ /^$/ ) {
								$opts->{'expires'} = time - 365*24*60*60;
							}
							$self->cookie($cook => $val, $opts);
						}				# Create cookies
					}
			);
	$logger->debug("Starting server pid $$ on defined ports.");
}

#####################
sub hostConfig {	#		Read/Renew
#####################
	my ($self, ) = @_;
	my $filename = "$sys_root$sys{'conf_dir'}/config.xml";
	if ( !$gate_config->{'_upd'} || $gate_config->{'_upd'} < (stat($filename))[9] ) {
		$gate_config = Drive::read_xml( $filename );
		$gate_config->{'_upd'} = (stat($filename))[9];
	}
	return $gate_config;
}
#####################
sub translate_keys {	#		Read/Renew translation table
#####################
	my ($self, ) = @_;
	my $filename = "$sys_root$sys{'conf_dir'}/query/translate_keys.json";
	if ( !$translate->{'_upd'} || $translate->{'_upd'} < (stat($filename))[9] ) {
		$translate = Drive::read_json( $filename, undef, 'utf8' );
		$translate->{'_upd'} = (stat($filename))[9];
	}
	return $translate;
}
#####################
sub query_data {	#		Collect query data as hash
#####################
	my ($self, ) = @_;

	my $pnames = $self->req->params->names;
	my $http_params;

	foreach my $par ( @$pnames) {
		$http_params->{$par} = $self->param($par);

		# Decode from IE shit
		$http_params->{$par} = encode_json( decode_json($self->param($par))) if $self->param($par) =~ /(\\u[\da-f]{4})+/i;

		if ( $http_params->{$par} =~ /^[\{\[].+[\]\}]$/ ) {		# Got JSON?
			my $data = $http_params->{$par};
			$data = url_unescape( $data );
			eval { $data = decode_json( encode_utf8($data) ) };
			unless ( $@ ) {
				$http_params->{$par} = $data;
			} else {
				$self->logger->dump("Decode param '$par' : $@", 2, 1);
			}
		}
	}

	my $user_state = {};
	$user_state = Drive::get_user( $self, );

	my $stack = [ grep { $_ } split(/\//, $user_state->{'query'}) ];

	return { 'http_params' => $http_params, 'user_state' => $user_state, 'stack' => $stack, 'method' => $self->req->method };
}
#################
sub get_user {	#	Catch user information
#################
	my ($self, ) = @_;
	my $usr_data = {
					'ip' => ipton($self->req->headers->every_header('x-real-ip')->[0]),
					'agent' => $self->req->headers->every_header('user-agent')->[0],
					'referer' => substr($self->req->headers->every_header('referer')->[0], 0, 255),
					'query' => url_unescape($self->req->url->path->{'path'}),
					'host' => $self->req->url->base->{'host'},
					'proto' => $self->req->url->base->{'scheme'},
					'stats' => $self->{'stats'},
				};		# $self->req->url->base.

	$usr_data->{'parent'} = $usr_data->{'referer'} || $usr_data->{'query'};
# 	$usr_data->{'parent'} =  $usr_data->{'query'} if $usr_data->{'referer'} eq $usr_data->{'parent'};
	$usr_data->{'parent'} =  '/' if $usr_data->{'query'} eq $usr_data->{'parent'};

	$usr_data->{'is_mobile'} = ( $usr_data->{'agent'} =~ /Android|webOS|iPhone|iP.d|BlackBerry|Mini|Mobile|Touch/i );
	$usr_data->{'on_mobile'} = $self->cookie('m') || $usr_data->{'is_mobile'} || '0';

	my $cooklist = $self->req->cookies;
	foreach my $cook ( @$cooklist ) {
		my $name = $cook->name;
		$usr_data->{'cookie'}->{$name} = $cook->value;
	}
	Drive::check_user( $self, $usr_data );

	return $usr_data;
}
#####################
sub check_user {	# Check for user logged in
#####################
	my ( $self, $usr)  = @_;
	my $logtime = time;
	my $new_fp = md5_sum( $usr->{'ip'}.Time::HiRes::time() );	# Create new fp, means as fingerprint
	$usr->{'fp'} = $usr->{'cookie'}->{'fp'};		# Store current fp
	$usr->{'cookie'}->{'fp'} = $new_fp;			# Write new fp

	my $where;
	my $udata;
	if ( $usr->{'fp'} ) {
		$where = "_fp='$usr->{'fp'}'";
		$udata = $self->dbh->selectall_arrayref("SELECT _uid,_umode,_ustate,_fp,_login FROM users WHERE $where",{Slice=>{}});
		if ( $udata->[0]->{'_uid'} ) {
			$usr->{'cookie'}->{'uid'} = $udata->[0]->{'_uid'};
			$usr->{'logged'} = 1;
			$usr->{'login'} = $udata->[0]->{'_login'};
			$self->dbh->do("UPDATE users SET _fp='$new_fp',_ltime='$logtime' WHERE _uid='$udata->[0]->{'_uid'}'");
		} else {
			$usr->{'cookie'}->{'uid'} = 0;
			$usr->{'logged'} = 0;
		}
	}
	return $usr;
}
#####################
sub check_column {	# Check for package is complete
#####################
	my ($self, $col, $spec) = @_;
	my ( $table, $column ) = split(/\./, $col);
	eval { $self->dbh->do("SELECT $column FROM $table LIMIT 0,1") };
	return 1 unless $@;
	if ( $self->dbh->{'mysql_errno'} == 1054 && $spec ) {		# Unknown column
		eval {	$self->dbh->do("ALTER TABLE $table ADD COLUMN $column $spec");
				$self->dbh->do("ALTER TABLE $table ADD INDEX $column ($column)");
			};
		return 1 unless $@;
	} elsif( $self->dbh->{'mysql_errno'} == 1146 ) {	# Unknown table
	};
	return 0;
}
1;
