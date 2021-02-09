#! /usr/bin/perl
# Client operations
# 2021 (c) mac-t@yandex.ru
package Drive::Client;
use utf8;
use Encode;
use strict;
use warnings;
use Cwd 'abs_path';
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape);
use Time::HiRes qw( usleep );
use HTML::Template;

our $templates;
our $my_name = 'client';

use Data::Dumper;

#########################
sub checkin {		# 
#########################
my $self = shift;
	$self->logger->dump('Check call');
	$self->{'qdata'}->{'tags'}->{'page_title'} = "Under construction";
	my $stat = Dumper( $self->{'qdata'});
	$self->logger->dump($stat);
	$self->stash( html_code => "<pre>$stat</pre>" );
	$self->render( template => 'drive/main', status => $self->stash('http_state') );
}

1
