# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::GetNew;

use utf8;
use Encode;
use Mojo::Base 'Mojolicious';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Data::Dumper;

my ($dbh, $logger, $config_path, $my_name, $sys);
my @options = qw(
		dbh
		logger
		qdata
	);

#####################
sub describe {		# Report module information
#####################
my $self = shift;
	return { 'name' => __PACKAGE__, 'title' => 'Сдать новых клиентов', 'type' => 'read',
			'descr' => 'Предоставить список клиентов, прошедших автоматическую проверку, '.
						'для рассмотрения кандидатур администратором',
			};
}
######################
sub new {
######################
my $class = shift;
	my %init = @_;
	my %hash = map(( "$_" => $init{$_} ), @options);
	my $self = bless \%hash, $class;
	$sys = \%Drive::sys;
	$dbh = $self->{'dbh'};
	$logger = $self->{'logger'};

	$config_path = Drive::upper_dir("$Drive::sys_root$sys->{'conf_dir'}/query");
	$my_name = $self->describe->{'name'};
	$my_name = substr( $my_name, rindex( $my_name, ':')+1);
	return $self;
}

#################
sub execute {	#			# Make main operation
#################
my ($self, $qdata) = @_;

	my $ret = {'fail' => 'Unusable defines', 'data' => {}};

	my $def = $self->load();
	return $ret unless $def->{'success'} == 1;

	my $map = $def->{'qw_send'}->{'data'};
	if ( ref( $def->{'qw_send'}->{'data'}) eq 'ARRAY' ) {			# Find for structure map define
		$ret->{'data'} = [];				# Result been an Array
		while ( ref( $map = shift( @{$def->{'qw_send'}->{'data'}}) ) ne 'HASH' ) {}		# Cut some service info
	}
	return $ret unless ref($map) eq 'HASH';

	my $uid_name;				# Anyway wee need to select _uid in sql
	my $user_names;			# Fields from users
	my $media_names;		# Fields from media
	my $media_keys = [];
	while ( my ($k, $v) = each( %{$sys->{'media_keys'}}) ) {			# Some preparation
		push( @$media_keys, {'name'=>$k, 'ord'=>$v->{'ord'}});
	}
	my $user_flds;
	if ( ref( $map) eq 'HASH' ) {						# Process definition map
		while ( my ($key, $val) = each( %$map) ) {
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
				$uid_name = "users.$uname" if $name eq '_uid';		# _uid field user defined name in query result
				$user_names->{$name} = $uname;		# Users fields.
				$user_flds .= ",users.$name AS 'users.$uname'";
			}
		}
	}
	$user_flds =~ s/^,//;
	unless ( $uid_name ) {		# Wee need to select _uid in sql anyway
		$uid_name = 'users._uid';
		$user_flds = "$uid_name,$user_flds";
	}

	my $sql = "SELECT $user_flds FROM users"
					." WHERE users._ustate=$sys->{'user_state'}->{'verify'}->{'value'} ORDER BY users._uid";
	if ( $media_names ) {			# Plug in media table if need
		my $media_flds = "media.owner_field AS 'media.owner_field'";
		foreach my $fld (  sort { $a->{'ord'}<=>$b->{'ord'} } @$media_keys ) {
			if ($fld->{'name'} eq 'url' ) {
				$media_flds .= ",CONCAT_WS('/','$sys->{'our_host'}/drive/media',media.owner_id,media.owner_field,media.id)"
											." AS 'media.$fld->{'name'}'";
			} else {
				$media_flds .= ",media.$fld->{'name'} AS 'media.$fld->{'name'}'";
			}
		}
		$sql = "SELECT $user_flds,$media_flds FROM users"
						." LEFT JOIN media ON media.owner_table='users' AND media.owner_id=users._uid"
						." WHERE users._ustate=$sys->{'user_state'}->{'verify'}->{'value'} ORDER BY users._uid";
	}
	my $db_got = [];
	eval { $db_got = $dbh->selectall_arrayref( $sql, {Slice=>{}} ) };
	$logger->dump($sql);

	if ( $@ ) {
		$ret->{'fail'} = "$my_name : $@";
		$logger->dump( $ret->{'fail'} );
	} else {
		my $data = [];
		my $row_out;
		my $curr_id;

		foreach my $row_in ( @$db_got) {		# Collect output table

			if ( $row_in->{$uid_name} == $curr_id ) {			# More files for same client
				if ( $row_in->{'media.owner_field'} && exists($media_names->{$row_in->{'media.owner_field'}}) ) {
					my $mediadata = {};
					foreach my $fld ( @$media_keys ) {
						$mediadata->{$fld->{'uname'}} = $row_in->{"media.$fld->{'name'}"};
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
						$row_out->{ decode_utf8($1)  } = $val;
					}
				}
				if ( $row_in->{'media.owner_field'} && exists($media_names->{$row_in->{'media.owner_field'}}) ) {
					my $mediadata = {};
					foreach my $fld ( @$media_keys ) {
						$mediadata->{$fld->{'uname'}} = $row_in->{"media.$fld->{'name'}"};
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
#################
sub commit {	#			# Store settings after editing
#################
my $self = shift;
my $qdata = shift;
	my ($table, $get_table);

	my $ret = {'success'=>1};

	$get_table = sub { my $item = shift;
							if ( ref($item) eq 'ARRAY' ) {
								foreach my $row ( @$item ) {
									$get_table->($row);
								}
							} elsif( ref($item) eq 'HASH' ) {
								while ( my ($key, $val) = each(%$item) ) {
									next if $key =~ /^=+/;
									my ($name, $field) = split(/;/, $key);
									my $tgt = $name;		# Get only "localized" name
									my $src = $get_table->($val) || $field;
									$src =~ s/^\$//;
									$table->{$src} = $tgt;
								}
							} else {
								return $item;
							}
						};

	$get_table->( $qdata->{'qw_send'}->{'data'} );
	my $def = { 
				'translate' => $table, 
				'define_recv' => encode_json({'code' => $qdata->{'qw_recv'}->{'code'}, 'data' =>$qdata->{'qw_recv'}->{'data'} }),
				'define_send' => encode_json({'code' => $qdata->{'qw_send'}->{'code'}, 'data' =>$qdata->{'qw_send'}->{'data'} }),
			};

	my $result = Drive::write_xml( $def, "$config_path/$my_name", $my_name);
	if ( $result ) {
		$ret = {'success'=>0, 'fail'=>$result};
	}

	return $ret;
}
#################
sub load {		#			# Load settings for editing
#################
my $self = shift;
	my $ret = {'success'=>1};
	if ( -e("$config_path/$my_name") ) {
		my $def = Drive::read_xml("$config_path/$my_name", $my_name, 'utf8');
		if ( exists( $def->{'_xml_fail'}) ) {
			$ret->{'success'} = 0;
			$ret->{'fail'} = $def->{'_xml_fail'};
		} elsif( $def ) {
			$self->{'translate'} = $def->{'translate'};
			$ret->{'qw_send'} = decode_json( $def->{'define_send'});
			$ret->{'qw_recv'} = decode_json( $def->{'define_recv'});
		} else {
			$ret->{'success'} = 0;
		}
	} else {
		$ret->{'success'} = 0;
		$ret->{'fail'} = "File $config_path/$my_name not found";
	}
	return $ret;
}
#####################
sub DESTROY {		#
#####################
my $self = shift;
	return undef $self;
}
