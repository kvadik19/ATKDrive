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
use Data::Dumper;

my ($dbh, $logger);
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
	$dbh = $self->{'dbh'};
	$logger = $self->{'logger'};
	
	return $self;
}

#################
sub commit {		#			# Store settings after editing
#################
my $self = shift;
my $qdata = shift;
	my ($table, $get_table);

	my $ret = {'success'=>1, 'action'=>'commit'};
	
	
	$get_table = sub { my $item = shift;
							if ( ref($item) eq 'ARRAY' ) {
								foreach my $row ( @$item ) {
									$get_table->($row);
								}
							} elsif( ref($item) eq 'HASH' ) {
								while ( my ($key, $val) = each(%$item) ) {
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
	my $def = {'code' => $qdata->{'qw_recv'}->{'code'}, 'table' => $table};
$logger->dump(Dumper($table));

	return $ret;
}
#################
sub load {		#			# Load settings for editing
#################
my $self = shift;
	my $ret = {'success'=>1, 'action'=>'load'};
	return $ret;
}
#####################
sub DESTROY {		#
#####################
my $self = shift;
	return undef $self;
}
