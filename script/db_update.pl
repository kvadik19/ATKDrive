#!/usr/bin/env perl

use 5.18.0;
use strict;
use Cwd 'abs_path';
use DBI;
use utf8;
use Encode;
use FindBin;

require "$FindBin::Bin/../lib/Drive/funcs.pl";

my $upd_dir = shift;
unless ($upd_dir) {
	say "Apply DB updates from .sql files";
	say "Usage: $0 <update_directory or file>";
	exit 1;
}

die "Source '$upd_dir' not found!" unless -e( $upd_dir );

my %sys = readcnf("$FindBin::Bin/../lib/Drive/sysd.conf");
my ($db_user, $db_pass) = split(/:/, $sys{'db_user'});
my $dbh = DBI->connect("DBI:mysql:atk:localhost:3306", $db_user, $db_pass,
						{mysql_enable_utf8 => 1,PrintError => 0, RaiseError => 1});

trace( $upd_dir );

####################
sub trace {
####################
	my $dir = shift;
	my $list;

	if ( -d($dir) ) {
		opendir( my $dh, $dir );
		$list = [ sort( grep { $_ =~ /^\d+$|\.sql$/ } readdir($dh) ) ];
		closedir( $dh );
	} else {
		$list = [ substr($dir, rindex($dir, '/')+1) ];
		$dir = substr($dir, 0, rindex($dir, '/'));
	}
	foreach my $item ( @$list ) {
		say $item;
		if ( -d("$dir/$item") ) {
			trace("$dir/$item");
		} else {
			my $sql = '';
			open( my $fh, "< $dir/$item" ) || die 'Can not open file!';
			while ( my $str = <$fh> ) {
				$str =~ s/^\s+|[\n\r]$//g;
				next unless $str;
				$sql .= " $str";
				if ( $str =~ /;$/ ) {
					apply( $sql );
					$sql = '';
				}
			}
			close( $fh );
		}
	}
	return;
}
####################
sub apply {
####################
	my $sql = shift;
	$sql =~ s/^\s+|[\n\r;]$//g;
	if ( $sql =~ /^insert\s+into\s+(\S+)\s+\(([^\)]+)\).+values\s+\((.+)\)$/i ) {
		my ($tbl, $fld, $val) = ($1, $2, $3);
		$fld = [ split( /,/, $fld ) ];
		$val = [ split( /,/, $val ) ];
		my $fc = 0;
		my $where;
		foreach my $field ( @$fld ) {
			$where .= " AND $field=$val->[$fc]";
			$fc++;
		}
		$where =~ s/^ AND //;
		my $check_sql = "SELECT COUNT(*) FROM $tbl WHERE $where";
		eval {
			undef $sql if $dbh->selectrow_arrayref($check_sql)->[0] > 0;
			};
		if ( $@ ) {
			say "\t$dbh->{'mysql_error'}\n$check_sql";
			undef $sql;
		}
	}

	if ( $sql ) {
		say $sql;
		eval { $dbh->do( $sql ) };
		say "\t$dbh->{'mysql_error'}" if $@;
	}
	return;
}
