# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::PutOld;

use utf8;
use Encode;
use Mojo::Base 'Mojolicious';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use XML::XML2JSON;


my @options = qw(
		dbh
		logger
		qdata
	);

#####################
sub describe {		# Report module information
#####################
my $self = shift;
	return { 'name' => 'Query::PutOld', 'title' => 'Принять старых клиентов', 'type' => 'write',
			'descr' => 'Получить список клиентов, уже записанных в базе данных офиса, внести их в таблицу шлюза '.
					'и разослать клиентам приглашение к использованию онлайн-сервиса',
			};
}
######################
sub new {
######################
my $class = shift;
	my %init = @_;
	my %hash = map(( "$_" => $init{$_} ), @options);
	my $self = bless \%hash, $class;
	return $self;
}

#####################
sub DESTROY {		#
#####################
my $self = shift;
	return undef $self;
}
