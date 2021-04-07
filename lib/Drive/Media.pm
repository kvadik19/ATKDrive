#! /usr/bin/perl
# Mediafiles operations
# 2021 (c) mac-t@yandex.ru
package Drive::Media;
use utf8;
use Encode;
use strict;
use warnings;
use Cwd 'abs_path';
use Mojo::Base 'Mojolicious::Controller';
use File::Path qw(make_path mkpath remove_tree rmtree);
# use Data::Dumper;

our $my_name = 'media';
our $sys = \%Drive::sys;

#################
sub operate {	# 
#################
my $self = shift;
my $action = shift;
	my $param = $self->{'qdata'}->{'http_params'};
	my $udata = $self->{'qdata'}->{'user_state'};

	my $out = {'code' => 0};
	my $filepath = $udata->{'query'};
	$filepath =~ s/^\/?$my_name//;


	if ( $self->{'qdata'}->{'method'} eq 'GET' ) {
		my $dir;
		unless ( $filepath =~ /([a-f0-9]{32})/i ) {
			$dir = $self->dbh->selectrow_arrayref("SELECT _uid FROM users WHERE _uid='$udata->{'cookie'}->{'uid'}'")->[0]
						if $udata->{'logged'} == 1;
		}
		$self->proxy("$Drive::sys_root$sys->{'user_dir'}/$dir$filepath");
		return;

	} elsif ( $self->{'qdata'}->{'method'} eq 'POST' && $param->{'code'} eq 'upload' ) {
		return $out unless $udata->{'fp'} eq $param->{'fp'};
		my $up_dir = "$Drive::sys_root$sys->{'user_dir'}/$param->{'session'}/$param->{'name'}";
		mkpath( $up_dir, { mode => 0775 } ) unless -d( $up_dir );		# Prepare storage, if need

		my $done = $self->getUpload($up_dir);
		if ( ref($done) eq 'ARRAY' ) {
			open( my $fh, "+>> $Drive::sys_root$sys->{'user_dir'}/$param->{'session'}/mime.types" );
			foreach my $frow ( @$done ) {			# Some postflights
				print $fh "$param->{'name'}/$frow->{'filename'}\t$frow->{'mime'}\n";
				$frow->{'field'} = $param->{'name'};
				$frow->{'url'} = "/$my_name/$param->{'session'}/$frow->{'field'}/$frow->{'filename'}";
			}
			close($fh);
			$out->{'data'} = $done ;
			$out->{'code'} = scalar(@$done);
		} else {
			$out->{'fail'} = $done;
		}
	}
	$self->render( type => 'application/json', json => $out );
}
#############################
sub admin_media {				# Mediafiles access for /drive/media/uid/mtype/media_id
#############################
my $self = shift;
	my (undef, undef, $uid, $media_role, $media_id) = @{$self->{'qdata'}->{'stack'}};
	my $where = "filename='$media_id'";
	$where = "id=$media_id" if $media_id =~ /^\d+$/;

	my $filedata = $self->dbh->selectrow_arrayref( "SELECT filename,mime FROM media WHERE $where" );
	my $filename = "$Drive::sys_root$sys->{'user_dir'}/$uid/$media_role/$filedata->[0]";
	return $self->proxy( $filename);
}
#############################
sub medialist {				# Read all from DB
#############################
my $self = shift;
my $init = { @_ };
	my $ret = [];
	my $got = $init->{'dbh'}->selectall_arrayref("SELECT * FROM media WHERE owner_table='users' AND owner_id=?",
											{Slice=>{}}, $init->{'qdata'}->{'user_state'}->{'cookie'}->{'uid'});
	foreach my $row ( @$got) {
		foreach my $fn ( qw(title filename) ) {
			$row->{$fn} = Drive::mysqlmask( $row->{$fn}, 1 );
		}
		push( @$ret, $row);
	}
	return $ret;
}
#############################
sub filesync {				# Sync uploaded/deleted to DB
#############################
my $self = shift;
my $init = { @_ };
	my $ret;
	my $now = time;

	my $param = $init->{'qdata'}->{'http_params'};
	my $udata = $init->{'qdata'}->{'user_state'};

	my $up_dir = "$Drive::sys_root$sys->{'user_dir'}";
	my $mimes;
	if ( -e("$up_dir/$param->{'data'}->{'session'}/mime.types") ) {
		open( my $fh, "< $up_dir/$param->{'data'}->{'session'}/mime.types" );
		$mimes = [<$fh>];
		close( $fh);
	}
	my $del_fs = [];
	my $del_db;
	my $upd_db = [];
	my $ins_flds = ['owner_id', 'ord,uptime', 'owner_field', 'title', 'filename', 'mime'];
	my $ins_vals;
	my $stored = $init->{'dbh'}->selectall_arrayref("SELECT * FROM media WHERE owner_table='users' "
													."AND owner_id='$udata->{'cookie'}->{'uid'}'",{Slice=>{}});

	my $cnt = 0;
	foreach my $file ( @{$param->{'data'}->{'files'}} ) {			# Move newly uploaded files onto place

		if ( $file->{'id'} > 0 && $file->{'deleted'} == 1 ) {			# Real Delete files/records
			push( @$del_fs, "$file->{'field'}/$file->{'name'}");
			$del_db .= " OR id='$file->{'id'}'";

		} elsif( $file->{'id'}) {
			my $idx = Drive::find_first( $stored, sub { my $row = shift; return $row->{'id'} == $file->{'id'}} );
			if ( $idx > -1 && $file->{'title'} ne $stored->[$idx]->{'title'} ) {
				push( @$upd_db, "UPDATE media SET title=SUBSTR('". Drive::mysqlmask($file->{'title'})
														."',1,255) WHERE id=$file->{'id'}");
			}

		} elsif ( -e( "$up_dir/$param->{'data'}->{'session'}/$file->{'field'}/$file->{'name'}" ) ) {	# Append from temp dir
			my $rfname = encode_utf8($file->{'name'});			# For use cyrillic in RegExp
			my $idx = Drive::find_first( $mimes, sub { my $fr = shift;
										return $fr =~ /^$file->{'field'}\/$rfname/;
									} );
			if ( $idx > -1 ) {				# Ignore files without mimetype
				chomp( $mimes->[$idx] );
				my $rowdata = [$udata->{'cookie'}->{'uid'}, $cnt, $now,
								"'$file->{'field'}'",
								"SUBSTR('".Drive::mysqlmask( $file->{'title'} )."',1,255)",
								"'".Drive::mysqlmask( $file->{'name'} )."'",
								"'".substr( $mimes->[$idx], rindex($mimes->[$idx], "\t")+1 )."'",
					];
				$ins_vals .= "(". join(',',@$rowdata) ."),";
				my $doc_dir = "$up_dir/$udata->{'cookie'}->{'uid'}/$file->{'field'}";
				mkpath( $doc_dir, { mode => 0775 } ) unless -d( $doc_dir );
				rename("$up_dir/$param->{'data'}->{'session'}/$file->{'field'}/$file->{'name'}",
									"$doc_dir/$file->{'name'}");
				$cnt++;
			}
		}
	}
	unlink( "$up_dir/$param->{'data'}->{'session'}/mime.types") if -e("$up_dir/$param->{'data'}->{'session'}/mime.types");

	if ( scalar( @$del_fs) ) {				# Have some to remove?
		$del_db =~ s/^ OR //;
		$del_db = "DELETE FROM media WHERE owner_id='$udata->{'cookie'}->{'uid'}' AND owner_table='users' AND ($del_db)";
		foreach my $fn ( @$del_fs ) {
			unlink( "$up_dir/$udata->{'cookie'}->{'uid'}/$fn" ) if -e("$up_dir/$udata->{'cookie'}->{'uid'}/$fn");
		}
		eval{ $init->{'dbh'}->do($del_db) };
		if ( $@ ) {
			$ret->{'warn'} = $@;
			$init->{'logger'}->dump("Media delete: $@", 2) if $init->{'logger'};
		}
	}

	if ( scalar( @$upd_db) ) {				# Have some to update?
		foreach my $sql ( @$upd_db ) {
			eval { $init->{'dbh'}->do($sql) };
			if ( $@ ) {
				$ret->{'fail'} = $@;
				$init->{'logger'}->dump("Media update: $@", 2) if $init->{'logger'};
				last;
			}
		}
	}

	if ( $ins_vals ) {				# Have something to store?
		$ins_vals =~ s/,$//;
		eval { $init->{'dbh'}->do("INSERT INTO media (". join(',', @$ins_flds) .") VALUES $ins_vals") };
		if ( $@ ) {
			$ret->{'fail'} = $@;
			$init->{'logger'}->dump("Media store: $@", 2) if $init->{'logger'};
		} else {
			rmtree("$up_dir/$param->{'data'}->{'session'}", {error => \my $rm_err} );
			$init->{'logger'}->dump( "rmtree : $up_dir/$param->{'data'}->{'session'}"
									.join(', ', @$rm_err) ) if scalar( @$rm_err) && $init->{'logger'};
		}
	}
	$self->cleanup_dir();
	return $ret;
}
#############################
sub getUpload {				# Decompose file uploads
#############################
my $self = shift;
my $path = shift;
my $res;
# $self->logger->dump("Upload into $path");

	if ( $self->req->{'finished'} ) {
		foreach my $part ( @{$self->req->content->parts} ) {
			my $finfo;
			my $descriptor = $part->headers->content_disposition;
			foreach my $data ( (split(/;/, $descriptor)) ) {
				next unless $data =~ /=/;
				my ($name, $value) = split(/=/, $data);
				$name =~ s/^\s+|\s+$//g;
				$value =~ s/^["']|["']$//g;
				$finfo->{$name} = decode_utf8($value);
			}

			if ( $finfo->{'filename'} ) {
				eval { $part->asset->move_to("$path/$finfo->{'filename'}") };
				if ( $@ ) {
					$res = $@;
					last;
				}
				chmod(0666, "$path/$finfo->{'filename'}");
				push( @$res, {'filename' => $finfo->{'filename'}, 'size'=> $part->asset->size(),
							'mime' => $part->headers->content_type} );
			}
		}		# For each parts

	} else {
		$res = "Upload not finished";
	}
	return $res;
}
#############################
sub cleanup_dir {				# Purge upload dir
#############################
my ($self, $udir ) = @_;
	$udir = "$Drive::sys_root$sys->{'user_dir'}" unless $udir;
	opendir( my $dh, $udir );				# Check outdated stuff
	my $list = [ grep {$_ =~ /^\w{32}$/} readdir($dh) ];
	closedir($dh);
	while ( my $old_stuff = shift( @$list ) ) {
		last if (stat( "$udir/$old_stuff"))[9] > time - (60*60*24*1);		# Remove old uploads
		rmtree( "$udir/$old_stuff" );
	}
	return;
}
#############################
sub proxy {				# Proxying mediafiles from directory
#############################
my ($self, $filename) = @_;

	my $ht_state = 404;
	my $ext = 'gif';
	my $idata = "GIF89a".
						"\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00".
						"\x21\xF9\x04\x01\x00\x00\x00\x00\x2C\x00\x00\x00".
						"\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3B";		# One-pixel transparent image
# $self->logger->dump("Proxy $filename");
	if ( -e($filename) && -f($filename) ) {
		open( my $ih, "< $filename");
		$idata = join('', <$ih>);
		close( $ih);
		$ht_state = 200;
		$ext = substr( $filename, rindex( $filename, '.')+1 );
	}
	$self->render( status => $ht_state, format => $ext, data => $idata);	# Reply one-pixel empty
}
1
