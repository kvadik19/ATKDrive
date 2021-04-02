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
use File::Path qw(make_path mkpath remove_tree rmtree);
use IO::Socket;
use IO::Select;
use POSIX;

use Utils::NETS;
use Time::HiRes qw( usleep );
use HTML::Template;

my $templates;
my $sys = \%Drive::sys;
my $use_fail = '';
eval( 'use Class::Unload;use Class::Inspector' );
$use_fail = $@ if $@;

use Data::Dumper;

our $intercom = {};

#############################
sub hello {					# Operations root menu
#############################
my $self = shift;
	$self->{'qdata'}->{'layout'} = 'support';
	$self->{'qdata'}->{'tags'}->{'page_title'} = '';
	$intercom->{'init'}->();
$self->logger->dump(Dumper($intercom));

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
	my $auth_file = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}/.admin");
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
		my $fs = system($sys->{'call_htpasswd'},'-b', $fn, $usr->{'name'}, $usr->{'pwd'});
		if ( $fs > 0 ) {
			$self->logger->dump("Passwd operation '$usr->{'name'}' at '$fn':$!",2);
			return $!;
		}
	}
	return undef;
}
#####################
sub query {			# Setup query translation tables
#####################
my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $ret = {'int' => [], 'ext' => []};

	if ( $param->{'code'} ) {			# Some AJAX received
		$ret->{'json'} = {'code' => $param->{'code'}, 'data' => $param->{'data'} };

		if ( $param->{'code'} eq 'watchdog' ) {		# Await incoming query for administrative purposes
			$ret->{'json'} = {'code' => 'watching'};
			my $watchfile = Drive::upper_dir("$Drive::sys_root/watchdog");
			if ( -e($watchfile) && -s($watchfile) ) {
				open( my $fh, "< $watchfile" );		# Read message reported by wsocket/hsocket
				$ret->{'json'}->{'data'} = decode_utf8(join('', <$fh>));
				$ret->{'json'}->{'code'} = 'received';
				close($fh);
				unlink( $watchfile );

			} elsif ( $param->{'data'}->{'cleanup'} ) {
				my $killstate = 0;
				if ( -e($watchfile) ) {
					unlink( $watchfile );
					$killstate = 1;
				}
				$ret->{'json'}->{'data'} = {'file' => $watchfile, 'kill' => $killstate };
			} else {
				open( my $fh, "> $Drive::sys_root/watchdog" );		# Zeroing buffer file
				close($fh);
			}
		} elsif ( $param->{'code'} =~ /^load|commit$/ ) {
			my $action = $param->{'code'};
			my $mod_lib = $param->{'data'}->{'name'};
			eval( "use $mod_lib" );
			$self->logger->debug($@, 2) if $@;
			my $module;
			my $oper;
			eval{ $module = $mod_lib->new(  dbh => $self->dbh, 
											logger => $self->logger, 
											qdata => $self->{'qdata'} );
					$oper = $module->$action( $param->{'data'} );
				};
			if ( $@ ) {
				$self->logger->debug($@, 2);
				$ret->{'json'}->{'fail'} = $@;
			} else {
				$module->DESTROY();
			}
			Class::Unload->unload( $mod_lib ) unless $use_fail;		# Class::Unload must be installed
			$ret->{'json'}->{'fail'} = $oper->{'fail'} if exists( $oper->{'fail'}); 
			$ret->{'json'}->{'data'} = $oper;
		}

	} else {			# Prepare static page
		my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
		my $conf_file = "$conf_dir/config.xml";
		my $config = Drive::read_xml( $conf_file );

		my $media_keys = [];
		while ( my ($k, $v) = each( %{$sys->{'media_keys'}}) ) {
			push( @$media_keys, {'name'=>$k, 'title'=>$v->{'title'}, 'ord'=>$v->{'ord'}});
		}
		$ret->{'media_keys'} = [ sort { $a->{'ord'}<=>$b->{'ord'} } @$media_keys ];

		my $struct = [];
		foreach my $def ( @{$config->{'utable'}} ) {
			push( @$struct, {'name'=>$def->{'name'}, 'title'=>$def->{'title'}, 'list'=>($def->{'type'} eq 'file') });
		}
		$ret->{'struct'} = $struct;

		my $modules = $self->get_modules();
		while ( my ($name, $data) = each(%$modules) ) {
			$ret->{$name} = $data;
		}
	}

	return $ret;
}
#####################
sub get_modules {			# Prepare installed modules
#####################
my $self = shift;
	my $mods;
	my $config_path = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}/query");
	mkpath( $config_path, { mode => 0775 } ) unless -d( $config_path );		# Prepare storage, if need

	my $qw_dir = "$Drive::sys_root/lib/Query";
	if ( -d($qw_dir) ) {			#### Collect available <fromOfficeToGate> QueryDispatcher libs
		opendir( my $dh, $qw_dir );
		while (my $qw_lib = readdir($dh) ) {
			next if $qw_lib =~ /^\./ || $qw_lib !~ /\.pm$/;
			$qw_lib =~ s/\.pm$//;
			$qw_lib = "Query::$qw_lib";
			eval( "use $qw_lib" );
			$self->logger->debug($@, 2) if $@;
			my $module;
			my $qw_info;
			eval{ $module = $qw_lib->new(  dbh => $self->dbh, 
											logger => $self->logger, 
											qdata => $self->{'qdata'} );
					$qw_info = $module->describe;
				};
			if ( $@ ) {
				$self->logger->debug($@, 2);
				push( @{$mods->{'int'}}, {'fail' => $@} );
			} else {
				push( @{$mods->{'int'}}, $qw_info );
				$module->DESTROY();
			}
			Class::Unload->unload( $qw_lib ) unless $use_fail;		# Class::Unload must be installed
		}
		closedir( $dh );
		push( @{$mods->{'int'}}, {'fail' => 'No modules found'} ) unless scalar( @{$mods->{'int'}});
	} else {			# Gathering available libraries
		push( @{$mods->{'int'}}, {'fail' => "$qw_dir not exists"} );
	}

	$qw_dir = "$Drive::sys_root$sys->{'html_dir'}";			#### Collect available <fromUserPageToOffice> templates
	if ( -d($qw_dir) ) {
		opendir( my $dh, $qw_dir );
		while (my $qw_tmpl = readdir($dh) ) {
			next if $qw_tmpl =~ /^\./ || $qw_tmpl !~ /\.tmpl$/;
			my $qw_info = {'name' => $qw_tmpl, 'title' => $qw_tmpl};

			open( my $fh, "< $qw_dir/$qw_tmpl");
			my $template = decode_utf8( join('', <$fh>));
			close( $fh);
			next if $template =~ /<!--\s*local\s*-->/i;		# Ignore unaccessible pages

			my $dom = Mojo::DOM->new( $template );
			my $title = $dom->find('h1')->[0];			# Extract page title as module name

			$qw_info->{'name'} =~ s/\.tmpl$//;
			$qw_info->{'title'} = $title->text() if $title;
			push( @{$mods->{'ext'}}, $qw_info );
		}
		closedir( $dh );
		push( @{$mods->{'ext'}}, {'fail' => 'No modules found'} ) unless scalar( @{$mods->{'ext'}});
	} else {
		push( @{$mods->{'ext'}}, {'fail' => "$qw_dir not exists"} );
	}
	return $mods;
}
#####################
sub connect {		# Setup interconnect settings
#####################
	my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";
	my $auth_file = "$conf_dir/.wsclient";
	my $config = {};
	$config = Drive::read_xml( $conf_file );

	my $ret = {'config_file' => $conf_file, 'auth_file' => $auth_file, 'magic_mask' => 8,
				'config' => $config->{'connect'}};

	unless ( $param->{'code'} ) {
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
				$self->logger->dump("Write $auth_file: $op", 3);
				$ret->{'json'}->{'success'} = 0;
				$ret->{'json'}->{'fail'} = $op;
			}
			delete( $param->{'data'}->{'users'} );
		}
		if ( $ret->{'json'}->{'success'} ) {
			while( my ($key, $val) = each( %{$param->{'data'}} ) ) {
				$config->{'connect'}->{$key} = $val;
				push( @{$ret->{'json'}->{'params'}}, $key);
			}
			my $op = Drive::write_xml( $config, $conf_file );
			if ( $op ) {
				$self->logger->dump("Save $conf_file: $op", 3);
				$ret->{'json'}->{'success'} = 0;
				$ret->{'json'}->{'fail'} = $op;
			}
		}
	}
	return $ret;
}
#####################
sub utable {		# User registration tuneup
#####################
	my $self = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $ret = { 'struct'=>[], 'scr_num'=>1, };
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}");
	my $conf_file = "$conf_dir/config.xml";

	my $config = {};
	$config = Drive::read_xml( $conf_file );

	my $struct = [];
	my $ustr = $self->dbh->selectall_arrayref("DESCRIBE users", {Slice=>{}});
	foreach my $def (@$ustr) {				# Just translate fieldnames to lowercase
		my $row = {};
		foreach my $fld ( qw(Field Type Default Key) ) {
			$row->{lc($fld)} = $def->{$fld};		# Lower case column names!
		}
		push( @$struct, $row);
	}

	unless ( $param->{'code'} ) {				# Output html page
		my $define = $config->{'utable'};
		my $deftype = sub { my $drow = shift;
						if ( $drow->{'type'} =~ /^(\w+)\(([\d\.\,]+)\)$/ ) {		# Like `dec(10,2)'
							$drow->{'typet'} = $1;					# `dec'
							$drow->{'len'} = $2;					# `10,2'
						} else {
							$drow->{'typet'} = $drow->{'type'};			# like `file'
							$drow->{'len'} = 'N/A';
						}
					};

		if ( $define ) {			# Have XML settings file?
			my $scr_count = [];
			foreach my $def ( @$define ) {			# Actualize XML to database
				$def->{'field'} = $def->{'name'};
				$def->{'scr'} = [ split(/,/, $def->{'scr'}) ] unless ref( $def->{'scr'}) eq 'ARRAY';
				$deftype->( $def );			# Compose fields 'typet' and 'len'

				if ( $def->{'type'} eq 'file' ) {
					push( @$scr_count, @{$def->{'scr'}} );
					push( @{$ret->{'struct'}}, $def);
				} else {
					my $hasCol = Drive::find_first( $struct, sub { my $r = shift; return $r->{'field'} eq $def->{'name'}} );
					unless ( $hasCol < 0 ) {
						$def->{'default'} = $struct->[$hasCol]->{'default'};
						if ( $def->{'type'} ne $struct->[$hasCol]->{'type'} ) {
							$def->{'type'} = $struct->[$hasCol]->{'type'};
							$deftype->( $def );			# Compose fields 'typet' and 'len'
						}
						push( @$scr_count, @{$def->{'scr'}} );
						push( @{$ret->{'struct'}}, $def);
					}		# Not in table structure - ignore for use
				}
			}

			foreach my $def ( @$struct) {			# Actualize database to XML
				my $hasCol = Drive::find_first( $ret->{'struct'}, sub { my $r = shift; return $r->{'name'} eq $def->{'field'}} );
				if ( $hasCol < 0) {
					$deftype->( $def );			# Compose fields 'typet' and 'len'
					$def->{'scr'} = ['1'];
					push( @{$ret->{'struct'}}, $def);
				}
			}
			$ret->{'scr_num'} = pop( @{ [sort(@$scr_count)] });

		} else {		# XML not stored yet
			foreach my $def ( @$struct) {
				$deftype->( $def );			# Compose fields 'typet' and 'len'
				$def->{'scr'} = ['1'];
				push( @{$ret->{'struct'}}, $def);
			}
		}

	} elsif( $param->{'code'} eq 'utable') {		# Got json query when 'save changes'
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
				$to_drop = [ sort {$b <=> $a} @$to_drop ];		# Delete some recods, begining from end
				while ( my $no = shift( @$to_drop) ) {
					push( @{$ret->{'json'}->{'warn'}}, "Duplicated name $define->[$no]->{'name'} found. Ignore");
					splice( @$define, $no, 1);
				}
			}
		}			#### Prevent duplicates first END

		my $sql_stack = [];
		foreach my $def ( @$define ) {			# Find for new/changed fields
			my $sql = $self->db_modi( $def, $struct);
			if ( $sql ) {
				push( @$sql_stack, {'name'=>$def->{'name'}, 'sql'=>$sql});
				if ( $sql =~ /ADD COLUMN/ ) {
					push( @$sql_stack, {'name'=>$def->{'name'}, 'sql'=>"ALTER TABLE users ADD INDEX $def->{'name'} ($def->{'name'})"});
				}
			}
		}
		foreach my $def ( @$struct ) {			# Find for deleted fields
			my $has = Drive::find_first( $define, sub { my $r = shift; return $r->{'name'} eq $def->{'field'}} );
			if ( $has < 0 ) {
				my $renamed = Drive::find_first( $sql_stack, sub { my $sq = shift; 
																if ( $sq->{'sql'} =~ / CHANGE $def->{'name'} (\w+) / ) {
																	return 1 if $1 ne $def->{'name'};
																}
																return 0;
															} );
				if ( $renamed < 0 ) {
					push( @$sql_stack, {'name'=>$def->{'field'}, 'sql'=>"ALTER TABLE users DROP COLUMN $def->{'field'}"});
				}
			}
		}

		my @date = Drive::timestr();			# Date (y,m,d,h,m,s,ms) for creating filenames
		my $sql_text = '';
		if ( scalar( @$sql_stack ) ) {
			my $bkup_dir = Drive::upper_dir("$Drive::sys_root$sys->{'bkup_dir'}");		# Backup tables
			my $bkup_file = "$date[0]-$date[1]-$date[2]_$date[3]-$date[4].dump";
			mkpath( $bkup_dir, { mode => 0775 } ) unless -d( $bkup_dir );		# Prepare storage, if need

			opendir( my $dh, $bkup_dir );				# Check outdated dumps
			my $flist = [ sort grep {$_ =~ /\.dump$/} readdir($dh) ];
			closedir($dh);
			while ( my $old_file = shift( @$flist ) ) {
				last if (stat( "$bkup_dir/$old_file"))[9] > time - (60*60*24*30) 
							|| $#{$flist} < 2;		# Remove 30-days old backups, but leave two previous backups as minimum
				unlink( "$bkup_dir/$old_file" );
			}
			
			my $host = '';
			$host = "-h $sys->{'db_host'}" if $sys->{'db_host'};
			my $fs = `mysqldump $host -B $sys->{'db_base'} -q -u $sys->{'db_usr'} -p$sys->{'db_pwd'} > $bkup_dir/$bkup_file`;
			if ( $fs ) {
				push( @{$ret->{'json'}->{'warn'}}, "Backup to $bkup_file: $fs");
				$self->logger->dump("Backup to $bkup_dir/$bkup_file: $fs", 3) ;
			}

			foreach my $sql ( @$sql_stack ) {			# Apply DB table changes
				eval { $self->dbh->do($sql->{'sql'}) };
				if ( $@ ) {
					push( @{$ret->{'json'}->{'fail'}}, $@);
					$self->logger->dump( "Apply SQL: $@", 2);
				} else {
					$sql_text .= "$sql->{'sql'};\n";
				}
			}
		}
		if ( $sql_text ) {				# And store sql into file
			my $sql_dir = Drive::upper_dir("$Drive::sys_root/sql/$date[0]");
			mkpath( $sql_dir, { mode => 0775 } ) unless -d( $sql_dir );		# Prepare storage, if need
			opendir( my $dh, $sql_dir );
			my $flist = [ sort {$b cmp $a} grep {$_ =~ /\.sql$/} readdir($dh) ];
			closedir($dh);
			my $last_file = shift( @$flist );
			my $nextnum = '00';
			if ( $last_file =~ /^(\d+)\D/ ) {
				$nextnum = $1 + 1;
				$nextnum = '0'x (2 - length($nextnum)).$nextnum;
			}
			$last_file = "$sql_dir/$nextnum\_$date[0]-$date[1]-$date[2].sql";
			
			eval {
					open( my $fh, "> $last_file");
					print $fh $sql_text;
					close($fh);
				};
			if ( $@ ) {
				push( @{$ret->{'json'}->{'warn'}}, "Write SQL to $last_file: $@; $!");
				$self->logger->dump( "Write SQL to $last_file: $@; $!", 2);
			}
		}			# Store sql into file for further structure replication END

		$config->{'utable'} = [];
		foreach my $def ( @$define ) {				# Prepare data to strore in XML
			$def->{'_screen'} = join(',', @{$def->{'_screen'}}) if ref($def->{'_screen'}) eq 'ARRAY';
			my $row = {'name'=>$def->{'name'}, 'type'=>$def->{'type'}, 'title'=>$def->{'title'}, 'scr'=>$def->{'_screen'}};
			$row->{'link'} = $def->{'link'} if exists( $def->{'link'});
			push( @{$config->{'utable'}}, $row);
		}
		my $res = Drive::write_xml( $config, $conf_file );
		if ( $res ) {
			push( @{$ret->{'json'}->{'fail'}}, "Write XML: $res");
			$self->logger->dump(Dumper($config), 2);
			$self->logger->dump("Write XML to $conf_file: $res", 2);
		}

		$ret->{'json'}->{'success'} = 0 if exists($ret->{'json'}->{'fail'});
		$ret->{'json'}->{'update'} = $sql_stack;
	}
	return $ret;
}
#####################
sub db_modi {		# Create sql to modify table
#####################
my ($self, $def, $struct) = @_;
my $sql;

	my $sql_make = sub {
			my ($new, $old) = @_;
			my $sql = '';
			$new->{'field'} = $new->{'name'};
			if ( $new->{'type'} eq 'file' ) {
				$sql = "UPDATE media SET owner_field='$new->{'name'}' WHERE owner_field='$new->{'_default'}->{'name'}'" 
							if $new->{'_default'}->{'name'} ne $new->{'name'};
				$sql = '' unless $new->{'_default'}->{'name'};		# NOOP if previous name undefined

			} else {
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
					if ( $upd ) {
						$sql = "ALTER TABLE users CHANGE $old->{'field'} $new->{'field'} $new->{'type'}";
						$sql .= " DEFAULT '$new->{'default'}'" if $new->{'type'} =~ /^char/ || length($new->{'default'}) > 0;
					}
				} else {
					$sql = "ALTER TABLE users ADD COLUMN $new->{'field'} $new->{'type'}";
					$sql .= " DEFAULT '$new->{'default'}'" if $new->{'type'} =~ /^char/ || length($new->{'default'}) > 0;
				}
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
sub hsocket {		# Process http admin queries
#####################
my $self = shift;
	unless ( $self->req->content->headers->content_type eq 'application/json') {
		$self->logger->dump('hsocket received wrong '.$self->req->content->headers->content_type, 3);
		$self->stash('html_code' => 'Wrong request type '.$self->req->content->headers->content_type);
		$self->render( template => 'exception', status => 404 );
		return;				# Report 404 on strange messages
	}

	my $msg_send = {'fail' => "418 : I'm a teapot"};
	my $msg_recv = $self->req->content->asset->{'content'};
	if ( $msg_recv =~ /^[\{\[].+[\}\]]$/s ) {		# Got JSON?
		my $qry;
		eval{ $qry = decode_json( encode_utf8($msg_recv) )};
		if ( $@) {
			$msg_send->{'fail'} = "Decode JSON : $@";
			$self->logger->dump( $msg_send->{'fail'} );
		} else {
			if ( -e("$Drive::sys_root/watchdog") && -z("$Drive::sys_root/watchdog") ) {		# Report received msg 
				$qry = decode_utf8( encode_json( $qry));
				open( my $fh, "> $Drive::sys_root/watchdog" );
				print $fh $qry;
				close($fh);
			}
			delete( $msg_send->{'fail'});
			my $operate = $self->process_query( $qry );
			while ( my ($key, $val) = each( %$operate) ) {
				$msg_send->{$key} = $val;
			}
		}
		$msg_send = decode_utf8(encode_json( $msg_send ));
	} else {
		$msg_send ="ECHO: $msg_recv";
	}
	$self->render( type => 'application/json', json => $msg_send );
}
#####################
sub wsocket {		# Process websocket admin queries
#####################
my $self = shift;

	$self->on( message => sub { my ( $ws, $msg_recv ) = @_;
						my $msg_send = {'fail' => "418 : I'm a teapot"};

						if ( $msg_recv =~ /^[\{\[].+[\}\]]$/s ) {		# Got JSON?
							my $qry;
							eval{ $qry = decode_json( encode_utf8($msg_recv) )};
							if ( $@) {
								$msg_send->{'fail'} = "Decode JSON : $@";
								$self->logger->dump( $msg_send->{'fail'} );
							} else {
								if ( -e("$Drive::sys_root/watchdog") && -z("$Drive::sys_root/watchdog") ) {	# Report received msg 
									$qry = decode_utf8( encode_json( $qry));
									open( my $fh, "> $Drive::sys_root/watchdog" );
									print $fh $qry;
									close($fh);
								}
								delete( $msg_send->{'fail'});
								my $operate = $self->process_query( $qry );
								while ( my ($key, $val) = each( %$operate) ) {
									$msg_send->{$key} = $val;
								}
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
sub process_query {		# Process intercommunication queries
#####################
my ($self, $query) = @_;
	my $ret = {'fail' => "418 : I'm a teapot"};
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}/query");
	return $ret unless -d($conf_dir);

	my $conf = $intercom->{ $query->{'code'}};
	unless ( $conf && $conf->{'upd'} >= ( stat($conf_dir))[9] ) {			# Update intercom
		opendir( my $dh, $conf_dir );
		while( my $fname = readdir($dh) ) {
			next unless $fname =~ /^\w+$/;
			if ( (stat("$conf_dir/$fname"))[9] > $conf->{'upd'} ) {
				my $def = Drive::read_xml( "$conf_dir/$fname", $fname, 'utf8' );
				if ( exists( $def->{'_xml_fail'}) ) {
					$ret->{'fail'} = $def->{'_xml_fail'};
				} elsif( $def ) {
					eval { $intercom->{ decode_json($def->{'define_recv'})->{'code'}} 
										= { 'upd'=>time, 'lib'=>"Query::$fname" } };
					$ret->{'fail'} = $@ if $@;
				}
			}
		}
		closedir($dh)
	}

	if ( exists( $intercom->{ $query->{'code'}}) ) {		# Recheck intercom
		my $libname = $intercom->{ $query->{'code'}}->{'lib'};
		eval( "use $libname" );
		$self->logger->debug($@, 2) if $@;
		my $module;
		my $qw_info;
		eval{ $module = $libname->new(  dbh => $self->dbh, 
										logger => $self->logger, 
										qdata => $self->{'qdata'} );
				$ret = $module->execute( $query->{'data'} );
			};
		if ( $@ ) {
			$self->logger->debug($@, 2);
			$ret->{'fail'} = $@;
		} else {
			$ret->{'code'} = $query->{'code'};
			$module->DESTROY();
		}
		Class::Unload->unload( $libname ) unless $use_fail;		# Class::Unload must be installed
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

1
