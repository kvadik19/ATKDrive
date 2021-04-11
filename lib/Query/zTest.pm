# Communication module from Office to Gate
# 2021 (c) mac-t@yandex.ru
# File encoding UTF8!

package Query::zTest;			# TEST FOR PutOld.pm
use strict;
use utf8;
use Encode;
use warnings;
use Mojo::Base 'Mojolicious';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Mojo::Util qw(url_escape url_unescape b64_encode trim md5_sum);
use Utils::Tools;
use Time::HiRes;
use HTML::Template;
use MIME::Lite;

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
	return { 'name' => __PACKAGE__, 'title' => 'DELEVOPE MODULE TYPE READ', 'type' => 'write',
			'descr' => '**** DON\'T TOUCH! ****',
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

	$ret = Utils::Tools->map_write( map => $def->{'qw_recv'}->{'data'},
									data => $qdata,
									caller => $my_name,
									dbh => $dbh,
									mode => 'add',
									sys => $sys,
									logger => $logger
								);
	if ( $ret->{'success'} == 1 ) {
		my $where = "FIND_IN_SET($ret->{'data'}->{'keyfield'},'".join(',', @{$ret->{'data'}->{'keylist'}})."')";
		if ( scalar( @{$ret->{'data'}->{'updates'}}) ) {
			foreach my $urow ( @{$ret->{'data'}->{'updates'}} ) {
				next unless $urow->{'_email'};
				$urow->{'_ustate'} = $sys->{'user_state'}->{'accepted'}->{'value'} unless exists( $urow->{'_ustate'} );
				$urow->{'name'} = $urow->{'fullname'} || $urow->{'compname'} 
									|| $urow->{'login'} 
									|| substr( $urow->{'_email'}, 0, index($urow->{'_email'}, '@'));
				$urow->{'__key'} = $ret->{'data'}->{'keyfield'};
				my $proc = $self->user_door( $urow );
			}
		}
		if ( $def->{'qw_send'}->{'data'} ) {
			$ret = Utils::Tools->map_read( map => $def->{'qw_send'}->{'data'},
											caller => $my_name,
											dbh => $dbh,
											sys => $sys,
											where => $where,
											logger => $logger
										);
			$ret->{'code'} = $def->{'qw_send'}->{'code'};
		}
	}
	return $ret;
}
#############################
sub user_door {				# Open door to Registered user cabinet by hash reference
#############################
my $self = shift;
my $init = shift;

	my $message;
	my $tmpl_file = "$Drive::sys_root$sys->{'mail_dir'}/access.tmpl";
	return $message unless -e( $tmpl_file );

	my $timestamp = Time::HiRes::time();
	my $hashpart = md5_sum( $init->{'_email'});
	my $hash = $hashpart.md5_sum( $timestamp);
	my $hashlink = "$sys->{'our_host'}?h=$hashpart&t=$timestamp&m=x";
	my ( $host ) = $sys->{'our_host'} =~ /\/([^\/]+)$/;

	my $mdata = {'link_accept' => $hashlink, 'link_reject' => "$hashlink&r=1",
					'site_name' => $sys->{'our_site'}, 'site_url' => $sys->{'our_host'},
					'host' => $host,
					'timeout' => $sys->{'reg_timeout'}, 
				};
	my $letter;
	eval {
		$letter = HTML::Template->new( filename => $tmpl_file,
						die_on_bad_params => 0,
						die_on_missing_include => 0,
					);
		};

	return "$my_name : $@" unless $letter;
	$letter->param( $mdata );
	$letter->param( $init );
	eval {
		$letter = decode_utf8( $letter->output() );
		};
	if ( $@ ) {
		$self->logger->dump("$my_name decode letter: $@", 3);
		return "$my_name : $@";
	}

	my $dom = Mojo::DOM->new($letter);				# Extract something from letter
	if ( $dom->find('comment')->[0] ) {
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
			From => encode('MIME-Header', decode_utf8($mdata->{'site_name'}))."<noreply\@$mdata->{'host'}>",
			To => encode( 'MIME-Header', $init->{'name'})." <$init->{'_email'}>",
			Subject => encode( 'MIME-Header', $subj),
			Type => 'multipart/alternative',
		);
	$msg->add('List-Unsubscribe' => $mdata->{'link_reject'});
	$msg->replace('X-Mailer' => "$mdata->{'host'} Mail Agent");

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
	my $where = "$init->{'__key'}='$init->{$init->{'__key'}}'";
	$dbh->do("UPDATE users SET _hash='$hash',_ustate='$init->{'_ustate'}' WHERE $where");

	return undef;
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
