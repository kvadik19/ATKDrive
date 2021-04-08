# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::PutOld;

use utf8;
use Encode;
use Mojo::Base 'Mojolicious';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Utils::Tools;

# use XML::XML2JSON;
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
	$self->load();
	return { 'name' => __PACKAGE__, 'title' => 'Принять старых клиентов', 'type' => 'write',
			'descr' => 'Получить список клиентов, уже записанных в базе данных офиса, внести их в таблицу шлюза '.
					'и разослать клиентам приглашение к использованию онлайн-сервиса',
			'translate' => $self->{'translate'}
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
	my $ret;
	my $def = $self->load();
	return $ret unless $def->{'success'} == 1;

	my $linkfield;
	$ret = Utils::Tools->map_write( map => $def->{'qw_send'}->{'data'},
									data => $qdata,
									caller => $my_name,
									dbh => $dbh,
									sys => $sys,
									logger => $logger
								);
	if ( $def->{'qw_send'}->{'data'} ) {
		$ret = Utils::Tools->map_read( map => $def->{'qw_send'}->{'data'},
										caller => $my_name,
										dbh => $dbh,
										sys => $sys,
										where => "FIND_IN_SET($linkfield,'')"
									);
		$ret->{'code'} = $def->{'qw_send'}->{'code'};
	}
	return $ret;
}
#################
sub commit {	#			# Store settings after editing
#################
my $self = shift;
my $qdata = shift;
	my $ret = {'success'=>1};

	my $table = {};
	Utils::Tools->add_translate( $table, $qdata->{'qw_send'}->{'data'} );
	Utils::Tools->add_translate( $table, $qdata->{'qw_recv'}->{'data'} );
	my $def = { 
				'translate' => $table, 
				'define_recv' => encode_json({'code' => $qdata->{'qw_recv'}->{'code'}, 'data' =>$qdata->{'qw_recv'}->{'data'} }),
				'define_send' => encode_json({'code' => $qdata->{'qw_send'}->{'code'}, 'data' =>$qdata->{'qw_send'}->{'data'} }),
			};
	my $result = Drive::write_xml( $def, "$config_path/$my_name.xml", $my_name);

	$ret = {'success'=>0, 'fail'=>$result} if $result;
	return $ret;
}
#################
sub load {		#			# Load settings for editing
#################
my $self = shift;
	my $ret = {'success'=>1};
	if ( -e("$config_path/$my_name.xml") ) {
		my $def = Drive::read_xml("$config_path/$my_name.xml", $my_name, 'utf8');
		if ( exists( $def->{'_xml_fail'}) ) {
			$ret->{'success'} = 0;
			$ret->{'fail'} = $def->{'_xml_fail'};
		} elsif( $def ) {
			$self->{'translate'} = $def->{'translate'};
			$ret->{'qw_send'} = decode_json($def->{'define_send'});
			$ret->{'qw_recv'} = decode_json($def->{'define_recv'});
		} else {
			$ret->{'success'} = 0;
		}
	} else {
		$ret->{'success'} = 0;
		$ret->{'fail'} = "File $config_path/$my_name.xml not found";
	}
	return $ret;
}

#####################
sub DESTROY {		#
#####################
my $self = shift;
	return undef $self;
}
