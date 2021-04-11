# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::GetNew;

use utf8;
use Encode;
use Mojo::Base 'Mojolicious';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Utils::Tools;

# use Data::Dumper;

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
	return { 'name' => __PACKAGE__, 'title' => 'Сдать новых клиентов', 'type' => 'read',
			'descr' => 'Предоставить список клиентов, прошедших автоматическую проверку, '.
						'для рассмотрения кандидатур администратором',
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

	my $ret = {'fail' => 'Unusable defines', 'data' => {}};
	my $def = $self->load();
	return $ret unless $def->{'success'} == 1;

	$ret = Utils::Tools->map_read( map => $def->{'qw_send'}->{'data'},
									caller => $my_name,
									dbh => $dbh,
									sys => $sys,
									logger => $logger
								);
	$ret->{'code'} = $def->{'qw_send'}->{'code'};
	return $ret;
}
#################
sub commit {	#			# Store settings after editing
#################
my $self = shift;
my $qdata = shift;
	my $ret = {'success'=>1};

	my $ret = Utils::Tools->module_save($my_name, $qdata);
	$ret = {'success'=>0, 'fail'=>$ret->{'fail'}} if $ret->{'fail'};
	return $ret;
}
#################
sub load {		#			# Load settings for editing
#################
my $self = shift;
	my $ret = Utils::Tools->module_read($my_name);
	$self->{'translate'} = $ret->{'translate'};
	$ret->{'success'} = 1;
	$ret->{'success'} = 0 if $ret->{'fail'};
	return $ret;
}
#####################
sub DESTROY {		#
#####################
my $self = shift;
	return undef $self;
}
