package Utils::Tools;
# Interconnect utilities

use strict;
use utf8;
use Encode;
use Cwd 'abs_path';
use Mojo::UserAgent;
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use IO::Socket;
use IO::Select;
use DBI qw(:utils);

use Time::HiRes qw( usleep );
use Fcntl qw(:flock SEEK_END);

use Data::Dumper;

our $VERSION = '0.01';

#####################
sub ask_inet {		# Process inet transactions
#####################
	my $self = shift;
	my $init = { @_};

	return "Not enough data to connect" unless $init->{'host'};

	foreach my $ikey ( qw(msg login pwd) ) {			# Prevent UTF8 errors
		$init->{$ikey} = encode_utf8($init->{$ikey}) if data_string_desc($init->{$ikey}) =~ /UTF8 on/;
	}
	my $timeout = $Drive::sys{'inet_timeout'}	|| 5;
	my $buffsize = $Drive::sys{'inet_buffer'};
	my $proto = $Drive::sys{'inet_proto'} || 'tcp';
	my $msg_recv;
	if ( $init->{'host'} =~ /^http/i || !$init->{'port'}) {
		my $url = Mojo::URL->new($init->{'host'});
		$url->scheme('http') unless $url->scheme;
		$url->port($init->{'port'});
		$url->userinfo("$init->{'login'}:$init->{'pwd'}") if $init->{'login'} || $init->{'pwd'};
		my $sock = Mojo::UserAgent->new(
				'max_redirects' => 8,
				'connect_timeout' => $timeout,
			);			# our
		$sock->transactor->name('ATKDrive-Mozilla/12.0 (Macintosh; WOW63; Intel Mac OS X 10_86_17) AppleWebKit/537.36 (KHTML, like Gecko)');

		my $msg_out = {'code' => 'RAW', 'data' => $init->{'msg'} };
		unless ( ref( $init->{'msg'} ) ) {
			if ( $init->{'msg'} =~ /^[\{\[]"/ ) {
				eval { $msg_out = decode_json( $init->{'msg'} ) };
				$msg_out = {'code' => 'RAW', 'data' => $msg_out } if $@;
			}
		}
		my $got = $sock->post( $url => json => $msg_out );
		if ( $got->res->code == 200 ) {
			eval { $msg_recv = encode_json($got->res->json) };
			$msg_recv = $got->res->to_string if $@;
		} else {
			$msg_recv = $got->res->code || '524';		# 524 A Timeout Occurred 
			$msg_recv .= ': '.$got->res->error->{'message'};
		}

	} else {
		my $sock = IO::Socket::INET->new(
							PeerAddr	=> $init->{'host'},
							PeerPort	=> $init->{'port'},
							Proto		=> $proto,
						);
		return "$@ $IO::Socket::errstr" if $@;
		$sock->autoflush(1);
		my $msg = $init->{'msg'};

		my $ready = IO::Select->new( $sock );
		my ($canw, ) = $ready->can_write( $timeout );
		if ( $canw ) {
			$canw->send("$msg", 0);
			my ($canr, ) = $ready->can_read( $timeout );
			if ( $canr ) {
				unless ( $buffsize ) {
					while ( <$canr> ) {
						$msg_recv .= $_;
					}
				} else {
					$canr->recv( $msg_recv, $buffsize);
				}
			} else {
				return "Can't Read from $init->{'host'} in $timeout sec.";
			}
		} else {
			return "Can't Send to $init->{'host'} in $timeout sec.";
		}
	}
	return $msg_recv;
}
#########################
sub email_good {			# Precheck email address fnd fix possible miss
#########################
	my $self = shift;
	my $aref = shift;
	my $text = $$aref;
	$$aref =~ s/\s//g;
	my $good;
	my ($usr, $host) = split(/@/, $$aref);
	$usr =~ s/^\.+//g;
	$host =~ s/[,;\/]/./g;
	my $res = `host $host`;
	if ( $res =~ /(\d{1,3}.?){4}/ && $usr =~ /^[\w\-.]+$/ ) {
		$$aref = lc($usr).'@'.lc($host);
		$good = 1;
	}
	return $good;
}
#################
sub module_save {	#			# Store settings after editing
#################
my ($self, $owner, $qdata) = @_;

	my $config_path = Drive::upper_dir("$Drive::sys_root$Drive::sys{'conf_dir'}/query");

# 	my $table = {};
# 	$self->add_translate( $table, $qdata->{'qw_send'}->{'data'} );
# 	$self->add_translate( $table, $qdata->{'qw_recv'}->{'data'} );
	Drive::write_json( $qdata->{'translate'}, "$config_path/translate_keys.json") if $qdata->{'translate'};
	my $def = { 
# 				'translate' => $table, 
				'define_recv' => {'code' => $qdata->{'qw_recv'}->{'code'}, 'data' =>$qdata->{'qw_recv'}->{'data'} },
				'define_send' => {'code' => $qdata->{'qw_send'}->{'code'}, 'data' =>$qdata->{'qw_send'}->{'data'} },
			};
	my $result = Drive::write_json( $def, "$config_path/$owner.json");
	return {'fail' => $result} if $result;
}
#################
sub module_read {		#			# Load settings for editing
#################
my ($self, $owner) = @_;

	my $config_path = Drive::upper_dir("$Drive::sys_root$Drive::sys{'conf_dir'}/query");
	my $filename = "$config_path/$owner.json";

	my $ret = {};
	if ( -e( $filename ) ) {
		my $def = Drive::read_json( $filename, undef, 'utf8');
		if( ref($def) ) {
# 			$ret->{'translate'} = $def->{'translate'};
			$ret->{'qw_send'} = $def->{'define_send'};
			$ret->{'qw_recv'} = $def->{'define_recv'};
		} else {
			$ret->{'fail'} = "$filename : $def";
		}
	} else {
		$ret->{'fail'} = "File $filename not found";
	}
	return $ret;
}
#########################
sub add_translate {			# Collect data from JSONs for further translations
#########################
my ($self, $table, $json) = @_;
	my $terms = {};
	my $do_table;
	$do_table = sub { my $item = shift;
					if ( ref($item) eq 'ARRAY' ) {
						foreach my $row ( @$item ) {
							$do_table->($row);
						}
					} elsif( ref($item) eq 'HASH' ) {
						while ( my ($key, $val) = each(%$item) ) {
							next if $key =~ /^=+/;
							my ($name, $field) = split(/;/, $key);
							my $tgt = $name;		# Get only "localized" name
							my $src = $do_table->($val) || $field;
							$src =~ s/^\$//;
							if ( $src =~ /^\(.+\)$/ ) {
								$tgt .= "\$$src";
								$src = $field;
							}
							$table->{$src} = $tgt;
							$terms->{$src} = $tgt;
						}
					} else {
						return $item;
					}
				};
	$do_table->( $json );
	return $terms;
}
#########################
sub map_write {			# Store data in json format
#########################
my $self = shift;
my $init = { @_ };
	my $ret = {'fail' => 'Unusable defines for write', 'data' => {}, 'success' => 0};

	my $map = $init->{'map'};
	if ( ref( $map) eq 'ARRAY' ) {			# Find for structure map define
		while ( ref( $map = shift( @{$init->{'map'}}) ) ne 'HASH' ) {}		# Cut some service info
	}
	return $ret unless ref($map) eq 'HASH';

	my $data_in = $init->{'data'};
	$data_in = [ $data_in ] unless ref( $data_in) eq 'ARRAY';
	return $ret unless ref($data_in->[0]) eq 'HASH';			# Assumed array of hashes

	my $keyfld;
	my $utable = {};				# Pickup users table field definition
	my $conf_dir = Drive::upper_dir("$Drive::sys_root$init->{'sys'}->{'conf_dir'}");
	$utable = Drive::read_xml( "$conf_dir/config.xml" )->{'utable'};
	my $idx = Drive::find_first( $utable, sub { my $fld = shift; return $fld->{'link'} == 1 } );
	$keyfld = $utable->[$idx]->{'name'} if $idx > -1;					# Detect control field

	my ($can_add, $can_upd);			# Check for available keys
	my $fldmap = {};				# Prepare names translation table
	while ( my ($key, $val) = each( %$map) ) {		# Process definition map
		next if $key eq '==manifest';			# Service info = ignored
		my ($uname, $name) = split(/;/, $key);			# Extract fieldname and alias for field

		my $codec;
		if ( ref($val) ) {		# Only SCALARs musk be processed
			next
		} elsif ( $val =~ /^\$\((.+)\)$/ ) {		# Need some values decoding
			my @codes = split(/;/, $1);			# Translate definition into hash
			foreach my $def ( @codes ) {
				my ($from, $to) = split(/:/, $def);
				$codec->{$from} = $to;
			}
		} elsif( $val =~ /^\$(\w+)$/) {				# Plain field translation
			next unless $1 eq $name;			# Some errors in target field naming
		} else {			# Map value is not defined
			next
		}

		if ( $init->{'mode'} eq 'add' && $name eq $keyfld ) {		# Assign data_in row condition check
			$can_add = $keyfld;
		} elsif( $init->{'mode'} eq 'upd' && $name eq '_uid' ) {
			$can_upd = '_uid';
		} elsif( $init->{'mode'} eq 'upd' && $name eq $keyfld ) {	# Prefer _uid for checking
			$can_upd = $keyfld unless $can_upd;
		}

		$fldmap->{$uname} = {'name' => $name, 'codec' => $codec};
	}		# Definition map processing

	if ( ($init->{'mode'} eq 'add' && !$can_add) 
			|| ($init->{'mode'} eq 'upd' && !$can_upd) ) {			# Stop processing on errors
		$ret->{'fail'} = "$init->{'caller'} : Keyfield for '$init->{'mode'}' not defined";
		return $ret;
	}

	my $updlist = [];			# IDs to process ( Gates _uid)
	my $addlist = [];			# IDs to process (1C codes)
	my $data_out = [];				# Records to process
	foreach my $row_in ( @$data_in ) {			# Process received JSON
		next unless ref($row_in) eq 'HASH';
		my $row_out = {};
		while ( my ($uname, $val) = each( %$row_in) ) {
			next if ref($val);			# Some bugs in datarow
			next if $init->{'mode'} eq 'add' && $fldmap->{$uname}->{'name'} eq '_uid';		# Can't insert AUTO_INCREMENTed field

			if ( exists( $fldmap->{$uname}) ) {
				push( @$addlist, $val) if $fldmap->{$uname}->{'name'} eq $keyfld;		# Prepare list for unique checking
				push( @$updlist, $val) if $fldmap->{$uname}->{'name'} eq '_uid';		# Prepare list for exists checking
				$val = $fldmap->{$uname}->{'codec'}->{$val} if $fldmap->{$uname}->{'codec'};		# Reencode value, if need
				$row_out->{$fldmap->{$uname}->{'name'}} = $val;
			}
		}
		if ( ( $init->{'mode'} eq 'add' && exists( $row_out->{$can_add}) ) 
				|| ( $init->{'mode'} eq 'upd' && exists( $row_out->{$can_upd}) ) ) {
			push( @$data_out, $row_out);		# Validate dataOut rows
		}
	}

	my $processed;			# Report processed IDs
	my $sql;
	if ( $init->{'mode'} eq 'add' ) {
		if ( scalar( @$addlist) ) {			# Prevent duplicates
			my $keylist = join(',', @$addlist);
			my $exists;
			eval {
				$exists = $init->{'dbh'}->selectcol_arrayref("SELECT $keyfld FROM users WHERE FIND_IN_SET($keyfld,'$keylist')");
				};
			if ( $@ ) {
				$init->{'logger'}->dump("$init->{'caller'} : $@") if $init->{'logger'};
			} else {
				foreach my $code ( @$exists ) {
					my $idx = Drive::find_first( $data_out, sub { my $r = shift; return $r->{$keyfld} eq $code} );
					splice( @$data_out, $idx, 1) if $idx > -1;
				}
			}
		}

	} elsif( $init->{'mode'} eq 'upd' ) {
		$keyfld = '_uid';		# Reassign for report
		my $keylist = join(',', @$updlist);
		my $exists;
		eval {
			$exists = $init->{'dbh'}->selectall_arrayref("SELECT * FROM users WHERE FIND_IN_SET(_uid,'$keylist')", {Slice=>{}});
			};
		if ( $@ ) {
			$init->{'logger'}->dump("$init->{'caller'} : $@") if $init->{'logger'};
		} else {
			foreach my $row ( @$exists ) {
				my $idx = Drive::find_first( $data_out, sub { my $r = shift; return $r->{'_uid'} eq $row->{'_uid'}} );
				if ( $idx > -1 ) {
					while ( my($fld, $dat) = each( %{$data_out->[$idx]}) ) {
						$row->{$fld} = $dat;
					}
				}
			}
			$data_out = $exists;
		}
	}

	if ( scalar( @$data_out) ) {			# Now create SQL
		my $flist = [ keys( %{$data_out->[0]}) ];
		foreach my $reqrd ( qw( _rtime ) ) {		# Some fields must be present
			my $exst = Drive::find_first( $flist, sub { my $fn = shift; return $fn eq $reqrd } );
			push( @$flist, $reqrd ) if $exst < 0;
		}

		my $updates = [];
		my $fields = join(',', @$flist);
		my $values;
		foreach my $row ( @$data_out) {
			my $updrow;
			my $valrow = '';
			foreach my $fld ( @$flist) {
				my $val = $row->{$fld};
				if ( "_email,fullname,compname,_ustate,_uid,$keyfld" =~ /$fld/ ) {			# Some interesting fields must be returned
					$updrow->{$fld} = $val;
				}

				if ( $fld =~ /^(_rtime)$/ ) {
					$val = time unless $val;
				}
				$val =~ s/([\'%;])/'%'.unpack( 'H*', $1 )/eg;
				
				$valrow .= "'$val',";
				push( @$processed, $row->{$fld} ) if $fld eq $keyfld;
			}
			$valrow =~ s/,$//;
			$values .= "($valrow),";
			push( @$updates, $updrow) if ref( $updrow) eq 'HASH';		# Prepare return values
		}
		$values =~ s/,$//;
		my $sql = "REPLACE INTO users ($fields) VALUES $values";
		eval {
			$init->{'dbh'}->do( $sql );
			};
		if ( $@ ) {
			$init->{'logger'}->dump("$@\n\t$sql", 2) if $init->{'logger'};
			$ret = {'fail' => "$init->{'caller'} : $@", 'success' => 0};
		} else {
			$ret = {'data'=>{'keyfield'=>$keyfld, 'keylist'=>$processed, 'updates' => $updates}, 'success' => 1};
		}
	} else {
		$ret->{'fail'} = "$init->{'caller'} : No data to process $init->{'mode'}.";
	}
	return $ret;
}
#########################
sub map_read {			# Read data in json format
#########################
my $self = shift;
my $init = { @_ };
	my $ret = {'fail' => 'Unusable defines for read', 'data' => {}};

	my $map = $init->{'map'};
	if ( ref( $map) eq 'ARRAY' ) {			# Find for structure map define
		$ret->{'data'} = [];				# Result been an Array
		while ( ref( $map = shift( @{$init->{'map'}}) ) ne 'HASH' ) {}		# Cut some service info
	}
	return $ret unless ref($map) eq 'HASH';

	my $codec;
	my $uid_name;				# Anyway wee need to select _uid in sql
	my $user_names;			# Fields from users
	my $media_names;		# Fields from media
	my $media_keys = [];
	while ( my ($k, $v) = each( %{$init->{'sys'}->{'media_keys'}}) ) {			# Some preparation
		push( @$media_keys, {'name'=>$k, 'ord'=>$v->{'ord'}});
	}
	my $user_flds;
	while ( my ($key, $val) = each( %$map) ) {		# Process definition map
		next if $key eq '==manifest';			# Service info, ignored
		my ($uname, $name) = split(/;/, $key);			# Extract fieldname and alias for field
		$name = $uname unless $name;

		if ( ref($val) eq 'ARRAY' ) {			# Media fields detected, prepare dictionary
			shift( @$val) if ref( $val->[0]) ne 'HASH'; 		# Cut some service info
			while ( my ($mk, $mv) = each( %{$val->[0]}) ) {
				next if $mk eq '==manifest';			# Service info, ignored
				my ($un, $na) = split(/;/, $mk);			# Extract fieldname and alias for field
				$na = $un unless $na;
				my $keyIn = Drive::find_first( $media_keys, sub{ my $def = shift; return $def->{'name'} eq $na});
				$media_keys->[$keyIn]->{'uname'} = $un if $keyIn > -1;
			}
			$media_names->{$name} = $uname;
		} else {
			$uid_name = "users.$name" if $name eq '_uid';		# _uid field user defined name in query result
			$user_names->{$name} = $uname;		# Users fields.
			$user_flds .= ",users.$name AS 'users.$name'";

			if ( $val =~ /^\$\((.+)\)$/ ) {		# Need some values decoding
				my @codes = split(/;/, $1);			# Translate definition into hash
				foreach my $def ( @codes ) {
					my ($from, $to) = split(/:/, $def);
					$codec->{"users.$name"}->{$from} = $to;
				}
			}
		}
	}
	$user_flds =~ s/^,//;
	unless ( $uid_name ) {		# Wee need to select _uid in sql anyway
		$uid_name = 'users._uid';
		$user_flds = "$uid_name AS '$uid_name',$user_flds";
	}

	my $where = "users._ustate=$init->{'sys'}->{'user_state'}->{'verify'}->{'value'}";		# Default user state filtered
	$where = $init->{'where'} if $init->{'where'};					# Any other filter

	my $sql = "SELECT $user_flds FROM users"
					." WHERE $where ORDER BY users._uid";
	if ( $media_names ) {							# Plug in media table if need
		my $media_flds = "media.owner_field AS 'media.owner_field'";
		foreach my $fld (  sort { $a->{'ord'}<=>$b->{'ord'} } @$media_keys ) {		# Sorted fields need
			if ($fld->{'name'} eq 'url' ) {
				$media_flds .= ",CONCAT_WS('/','$init->{'sys'}->{'our_host'}/channel/media',media.owner_id,media.owner_field,media.filename)"
											." AS 'media.$fld->{'name'}'";
			} else {
				$media_flds .= ",media.$fld->{'name'} AS 'media.$fld->{'name'}'";
			}
		}
		$sql = "SELECT $user_flds,$media_flds FROM users"
						." LEFT JOIN media ON media.owner_table='users' AND media.owner_id=users._uid"
						." WHERE $where ORDER BY users._uid";
	}
	my $db_got = [];
	eval { $db_got = $init->{'dbh'}->selectall_arrayref( $sql, {Slice=>{}} ) };

	if ( $@ ) {
		$ret->{'fail'} = "$init->{'caller'} : $@";
		$init->{'logger'}->dump("$@\n\t$sql", 2) if $init->{'logger'};
	} else {
		my $data = [];
		my $row_out;
		my $curr_id;
		foreach my $row_in ( @$db_got) {		# Collect output table
			if ( $row_in->{$uid_name} == $curr_id ) {			# More files for same client
				if ( $row_in->{'media.owner_field'} && exists($media_names->{$row_in->{'media.owner_field'}}) ) {
					my $mediadata = {};
					foreach my $fld ( @$media_keys ) {
						$mediadata->{$fld->{'uname'}} = Drive::mysqlmask($row_in->{"media.$fld->{'name'}"}, 1);
					}
					push( @{$data->[-1]->{ $media_names->{$row_in->{'media.owner_field'}}}}, $mediadata );
				}

			} else {
				$row_out = {};				# Create new empty row
				while ( my ( $name, $uname) = each( %$media_names )) {
					$row_out->{$uname} = [];
				}
				while ( my ($fld, $val) = each( %$row_in) ) {
					if ( $fld =~ /^users\.(.+)$/ ) {
						$fld = $1;
						my $ufld = $user_names->{$fld};
						if ( exists( $codec->{"users.$fld"}) ) {		# Have decoder table?
							$val = $codec->{"users.$fld"}->{$val};
						} else {
							$val = Drive::mysqlmask( $val, 1);
						}
						$row_out->{ $ufld} = $val if $ufld;
					}
				}
				if ( $row_in->{'media.owner_field'} && exists($media_names->{$row_in->{'media.owner_field'}}) ) {
					my $mediadata = {};
					foreach my $fld ( @$media_keys ) {
						$mediadata->{$fld->{'uname'}} = Drive::mysqlmask($row_in->{"media.$fld->{'name'}"}, 1);
					}
					push( @{$row_out->{ $media_names->{$row_in->{'media.owner_field'}}} }, $mediadata );
				}
				$curr_id = $row_in->{ $uid_name };
				push( @$data, $row_out);
			}
		}
		delete( $ret->{'fail'});
		$ret->{'data'} = $data if ref( $ret->{'data'}) eq 'ARRAY' ;
		$ret->{'data'} = $data->[0] if ref( $ret->{'data'}) eq 'HASH' ;
	}
	return $ret;
}
1
