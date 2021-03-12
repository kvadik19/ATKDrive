# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::GetNew;

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
	return { 'name' => 'Query::GetNew', 'title' => 'Сдать новых клиентов', 'type' => 'read',
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
	return $self;
}

#####################
sub DESTROY {		#
#####################
	my $self = shift;
	return undef $self;
}
