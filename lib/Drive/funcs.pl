###################  DO'NT CHANGE ENCODING koi8-r OF THIS FILE  ########################
#
#  written by Crazy at Jan 2006-2014
#  Function library for some scripts
#  usage: require funcs.pl
# use POSIX;
# use CGI;
###########################################

use Fcntl qw(:flock SEEK_END);
use Time::HiRes;
use Encode;
use XML::XML2JSON;
use File::Copy;
use Mojo::JSON qw(j decode_json encode_json);
use Mojo::Util qw(url_escape url_unescape b64_encode  trim md5_sum);

##################################
sub fork_proc {		# Fork process
##################
	my $pid;

	FORK: {
		if ( defined($pid = fork) ) {
			return $pid;
# 		} elsif ( $! =~ /No more process/ ) {
# 			sleep 10;
# 			redo FORK;
		} else {
			die "Can't fork: $!";
		}
	}
}
#########################
sub reopen_std {			# Reopen to /dev/null
#########################
	open(STDIN,  "+>/dev/null") or die "Can't open STDIN: $!";
	open(STDOUT, "+>&STDIN") or die "Can't open STDOUT: $!";
	open(STDERR, "+>&STDIN") or die "Can't open STDERR: $!";
};
#################
sub upper_dir {					#  Calculate absolute path from ../ ones
#################
my $path = shift;
	while ( $path =~ /^(.*)\/\w+\/\.\.(\/.*)$/g ) {
		$path =~ s/^(.*)\/\w+\/\.\.(\/.*)$/$1$2/;
	}
	return $path;
}
#################
sub renew {					#  Read file content if no content of file updated
#################
my ( $content, $filename, $utf8 ) = @_;
	if ( -e( $filename ) ) {
		if ( !$content || ( -M( $filename ) < 0 ) ) {
			open( my $fh, "< $filename" ) || return $content;
			$content = join('', <$fh>);
			close $fh;
			if ( $utf8 ) {		# Normalize UTF8
				my $ref = decode_json( encode_json( \@{[$content,]} ));
				$content = $$ref[0];
			}
		}
	}
	return $content;
}
#################
sub hash_eq {					#  Compare hashes
#################
my ($master, $slave) = @_;
my $equals = 0;
	while ( my ($key, $val) = each( %$master ) ) {
		if ( exists( $slave->{$key}) ) {
			if ( $val eq $slave->{$key} ) {
				$equals = 1;
			}
		} else {
			$equals = 0;
			last;
		}
	}
	return $equals;
}
#################
sub timestr {					#  Make string from serial date number
#################
my ($datetime, $gmt) = @_;

	$datetime = $datetime || Time::HiRes::time();
	$datetime = sprintf( '%.2f', $datetime );

	my @date = localtime( $datetime );		#  Further need
	@date = gmtime( $datetime ) if $gmt;		#  GMT

	$date[6] = substr($datetime,index($datetime, '.')+1) if $datetime =~ /\./;

	$date[5]+=1900;
	$date[4]++;
	map { $date[$_] = sprintf('%02d', $date[$_]) } (0, 1, 2, 3, 4);

	return ($date[5], $date[4], $date[3],$date[2],$date[1],$date[0],$date[6]) if wantarray();
	return "$date[3]-$date[4]-$date[5] $date[2]:$date[1]:$date[0].$date[6]";
}
################################
sub bytes {
################################	Transform number into "bytes" format (Kb/Mb/b)
my $number = shift;
	if ($number > 1073741824) {			#  Make Size string
		$number = (int($number/10737418.24)/100).' Gb';
	} elsif ($number > 1048576) {			#  Make Size string
		$number = (int($number/10485.76)/100).' Mb';
	} elsif ($number > 1024) {
		$number = (int($number/10.24)/100).' Kb';
	} else {
		$number = "$number b";
	}
	return $number;
}
#####################
sub mysqlmask {		# Quote some characters that can't be stored in MySQL table
#####################
my ($value, $unmask) = @_;
	if ( $unmask ) {
		$value =~ s/%(\w{2})/pack( 'H*', $1)/gei;
	} else {
		$value =~ s/([\'\"\\\%;])/'%'.unpack( 'H*', $1 )/eg;
	}
	return $value;
}

###############
sub dateformat {
###############  Formatting date from serial number like MySQL
my ($time, $string, $gmt) = @_;
	my @date = localtime( $time );
	@date = gmtime( $time ) if $gmt;
	$date[5]+=1900;
	$date[4]++;
	my %mask = ('%e'=> $date[3],											# day, no leadibg
				'%d'=> ("0" x ( 2 - length( $date[3] ) ) . $date[3]),		# day, leading 0
				'%c'=> $date[4],											# month number
				'%m'=> ("0" x ( 2 - length( $date[4] ) ) . $date[4]),		# month number, leading 0
				'%y'=> ( substr($date[5], 2)),								# year, no century
				'%Y'=> $date[5],											# year 4-digit
				'%h'=> $date[2],											# hour, leading 0, 12-hrs
				'%H'=> ("0" x ( 2 - length( $date[2] ) ) . $date[2]),		# hour, leading 0, 24-hrs
				'%i'=> ("0" x ( 2 - length( $date[1] ) ) . $date[1]),		# minutes, leading 0
				'%s'=> $date[0],											# seconds
				'%S'=> ("0" x ( 2 - length( $date[0] ) ) . $date[0]),		# seconds too
				'%t'=> ("0"x(2-length($date[2])).$date[2]).':'.("0"x(2-length($date[1])).$date[1]),	# time HH:MM:ss
				'%T'=> ("0"x(2-length($date[2])).$date[2]).':'.("0"x(2-length($date[1])).$date[1]).':'.("0"x(2-length($date[0])).$date[0]),
			);
	while ( my ($key, $mask) = each( %mask ) ) {
		$string =~ s/$key/$mask/g;
	}
	return $string
}
###############
sub purehtml {
###############  Cleanup HTML Code
my $text = shift;
my $ret = $text;
	if ( $text =~ /\n/ ) {
		$ret =  '';
		foreach my $str ( split(/\n/, $text) ) {
			$ret .= "<p>$str</p>"
		}
	} elsif( $text =~ /\S+/ ) {
		$ret = "<p>$text</p>";
	}
	return $ret;
}
###############
sub dehtml {		#  Clear any html tags from text (zap=1) or Clear only linebreaks
##############		#  Also returns last occurience of line break (if wantarray)
my ($ret,) = @_;
	return '' unless $ret;
	my $breaker = [
			'<img.+?>',
			'</?center>',
			'</?div.*?>',
			'<hr.*?>',
			'</?h\d*>',
			'</?table.*?>',
			'</?td.*?>',
			'</?tr.*?>',
			'</?th.*?>',
			'</?p.*?>',
			'</?br>',
			'</?li.*?>',
			'</?style.*?>',
		];

	$ret =~ s/\n//gi;
	my $break = join('|', @$breaker );
	$ret =~ s/$break/\n/gi;
	$ret =~ s/<.+?>//gi;						# Kill any tag
	$ret =~ s/\x0D|\x0D\x0A|\x0A/\n/g;				# Translate all of type <CRs>
	$ret =~ s/&\w{1,2}?quo\w?\;/\"/gi;			# restore other "
	$ret =~ s/&\wt\;/"/gi;			# Some double quotes
	$ret =~ s/&apos\;/'/gi;			# change apostrof
	$ret =~ s/&((#8212)|(\wdash))\;/-/gi;	# change m/n-dash to dash
	$ret =~ s/&nbsp\;/ /gi;			# change nobr-space to space
	$ret =~ s/&\w{1,5}\;//g;
	return $ret;
}
#############################
sub text_html {					# Masking illegal symbols
#############################
my ($str, $portion ) = @_;
# 	$str = encode_utf8($str);
	$str =~ s/&/&amp;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	$str =~ s/["'`](.+?)["'`]/&laquo;$1&raquo\;/gim;		# change quoted mark
	$str =~ s/ - / &ndash; /g;					# change dash to m-dash
	$str =~ s/'/&apos;/g;
	$str =~ s/"/&quot;/g;
	$str =~ s/\n/<br>/g;
	$str =~ s/\xC2?\xAB/&laquo;/g;
	$str =~ s/\xC2?\xBB/&raquo;/g;
	$str =~ s/(\d)\s+(\S)/$1&nbsp;$2/g;
	$str =~ s/(https?:\/\/[^\s^<]+)/<a href="$1" target="_blank">$1<\/a>/gi;
	if ( $portion > 0 && length($str) > $portion ) {
		$str = substr( $str, 0, index( $str, "\n", $portion));
				# Shorten string to folowing paragraph
	}
	return $str;
# 	return decode_utf8($str);
}
##############
sub readcnf {
###############  Read some configuration file
my ($fpref, $cnf) = @_;

	return {} unless -e( $fpref );
	open( my $hfpref, "< $fpref" );			#  Read .conf file
	my @pref = grep { ( /\S+/ ) && ( $_ !~ /^\s*[;#]/) } ( <$hfpref> );
	close $hfpref;

	chomp( @pref );				#  Trailing cr, etc. zapping
	my %confs = ();
	my $pstring = '';
	my $pname = '';

	my $conft = join("\n", @pref);			# Plain text from file array

	my $cnt = 0;
	while ( $conft =~ m/\s*[\w\/\-]+\s*\{[\n\s]*.*?[\n\s]*\}/gms ) {
		$pname = $pstring = $&;
				#  Get portion of .conf like < parameter{his_value} >
		$pstring =~ s/\s*([\w\/\-]+)\s*\{[\n\s]*(.*)?[\n\s]*\}/$2/gms;		#  Remove param name from portion
		$pname = $1;									#  But store it separatelly
		$pstring =~ s/\&\#123/{/g;
		$pstring =~ s/\&\#125/}/g;		# Restore curlies
		$pstring =~ s/([^\\])?;$/$1/gs;		# Cut last semicolon (backward compat.)
		$pstring =~ s/[\n\s]$//gs;		# Cutting last linebreak

		$confs{$pname} = $pstring;
	}
	if ( ref($cnf) eq 'HASH' ) {		# Also fill reference
		while (my ($key, $val) = each( %confs ) ) {
			$cnf->{$key} = $val;
		}
	}
	return %confs;
}
##############
sub xml_mask {
###############  Mask formatted text for save into XML::Simple
	my $text = shift;
	my $umask = shift;		# To decode?
	my $out;
	if ( $umask ) {
		$out = decode_json( encode_utf8("{\"a\":\"$text\"}") );
		$out = $out->{'a'};
	} else {
		$out = encode_json( {'a' => $text } );
		$out =~ s/^\{"a":"|"\}$//g;
	}
	return $out
}
#################
sub add_xml {	#  Append xml content to existing hash
#################
my ($hashref, $xml_file, $root) = @_;
	my $xml = read_xml($xml_file, $root);
	while (my ($key, $val) = each( %$xml) ) {
		$hashref->{$key} = $val;
	}
	return $hashref;
}
#############################
sub read_xml {				# Read XML file
#############################
my ($xml_file, $root, $enc ) = @_;
	my $hash;
	unless ($root) {
		$root = substr( $xml_file, rindex($xml_file, '/')+1 );
		$root = substr( $root, 0, index($root, '.'));
	}
	if ( -e( $xml_file ) ) {
		my $x2 = XML::XML2JSON->new( attribute_prefix=>'', pretty=>1, content_key=>'value' );
		open(my $fh, "< $xml_file");
		my $xml = join('',<$fh>);
		$xml = encode_utf8( $xml ) if $enc;
		close( $fh );
		
		my $sig_die = $SIG{'__DIE__'};
		undef $SIG{'__DIE__'};
		eval{ $hash = $x2->xml2obj($xml) };
		$SIG{'__DIE__'} = $sig_die;
		return {'_xml_fail' => $@} if $@;
		return $hash->{$root};
	}
	return $hash;
}
#############################
sub write_xml {				# Store XML file
#############################
my ($hash, $xml_file, $root) = @_;
	unless ($root) {
		$root = substr( $xml_file, rindex($xml_file, '/')+1 );
		$root = substr( $root, 0, index($root, '.'));
	}
	my $res;
	if ( -e( $xml_file ) ) {
		copy( $xml_file, "$xml_file.bkup" );
	}

	my $x2 = XML::XML2JSON->new( attribute_prefix=>'', pretty=>1, content_key=>'value' );		#, force_array=>1
	my $out = $x2->obj2json( { $root => $hash }) ;

	my $sig_die = $SIG{'__DIE__'};
	undef $SIG{'__DIE__'};
	eval{ $out = $x2->json2xml($out) };
	$SIG{'__DIE__'} = $sig_die;
	return $@ if $@;

	my $buffered = $|; $| = 1;					# Set unbuffered
	open( my $fh, "+>> $xml_file" ) || warn "Open $!";
	flock( $fh, LOCK_EX ) || warn "Lock $!";
	truncate( $fh, 0 );				# Resect file contents

	print $fh $out;
	chmod( 0600, $fh);
	flock( $fh, LOCK_UN ) || warn "UNLock $!";
	close $fh;
	$res = $! if $!;
	$| = $buffered;		# Restore buffer mode
	return $res;
}
#############################
sub write_json {					# Store JSON file
#############################
my ($hashref, $filename) = @_;
# 	copy( "$filename.bkup", "$filename.bkup.0" ) if -e( "$filename.bkup");
	copy( $filename, "$filename.bkup" ) if -e( $filename);
	my $buffered = $|; $| = 1;					# Set unbuffered
	open( my $fh, "+>> $filename" ) || return "JSON $filename Open : $!";
	flock( $fh, LOCK_EX ) || return "JSON $filename  Lock : $!";
	truncate( $fh, 0 );				# Reset file contents
	eval { print $fh encode_json( $hashref ) };
	return "$filename JSON Encode : $@" if $@;
	chmod( 0600, $fh);
	flock( $fh, LOCK_UN );
	close $fh;
	$| = $buffered;		# Restore buffer mode
	return;
}
#############################
sub read_json {					# Read JSON file
#############################
my ($filename ) = @_;
my $hash;

	if ( -e( $filename ) ) {
		open( my $fh, "< $filename" ) || return "JSON $filename Open : $!";
		my $content = join('', <$fh>);
		close( $fh );
		my $sig_die = $SIG{'__DIE__'};
		undef $SIG{'__DIE__'};
		eval{ $hash = decode_json( $content ) };
		$SIG{'__DIE__'} = $sig_die;
		return "$filename : $@" if $@;
	}
	return $hash;
}
###############
#########################
sub find_first {				#	Find first occurience if something in array
#########################
my ( $array, $test, @args ) = @_;
	my $cnt = 0;
	foreach my $item ( @$array ) {
		return $cnt if $test->( $item, @args );
		$cnt++;
	}
	return -1;
}
#########################
sub find_hash {				#	Find hash element by condition
#########################
my ( $hash, $test, @args ) = @_;
	while ( my($k, $val) = each( %$hash ) ) {
		return $k if $test->( $k, @args );
	}
	return undef;
}
#########################
sub ipton {				#	Translate IP address to long
#########################
	my $ip = shift;
	$ip = '127.0.0.1' if (!$ip) || $ip eq ':::1';		# 127.0.0.1-localhost
	my @a = split( /\./, $ip );
	return int($a[0])*256**3+int($a[1])*256**2+int($a[2])*256+int($a[3]);
}
#########################
sub ntoip {				#	Translate long to IP address
#########################
	my $intip = shift;
	$intip = 2130706433 unless $intip;		# 127.0.0.1-localhost
	my $d = $intip % 256; $intip -= $d; $intip /= 256;
	my $c = $intip % 256; $intip -= $c; $intip /= 256;
	my $b = $intip % 256; $intip -= $b; $intip /= 256;
	return "$intip.$b.$c.$d";
}
##############
sub set_case {
##############			# Converts numbering token form by number
my ( $num, $cases ) = @_;
my @group = ( '1', '234', '567890');
$num = ( length($num) > 2 ) ? substr( $num, length($num)-2 ) : $num;		# Get only last 2 digits
$num = ( $num > 10 && $num < 15 ) ? 5 : $num;		# Correct 11...14 form
my $dig = substr( $num, length($num)-1 );

my $cnt = 0;
	foreach my $digtest (@group) {
		last if $digtest =~ /$dig/;
		$cnt++;
	}
	$cnt = $#{$cases} if $cnt > $#{$cases};
	return $cases->[$cnt];
}
###############
sub round {
###############  Classic "round" operation, backward compatible
my ( $num, $prc ) = @_;			# Number, precision
	return sprintf( '%.'.$prc.'f', $num );
}
##########################
1
########################### <EOF> funcs.pl ########################
