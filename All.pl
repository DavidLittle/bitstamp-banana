use feature qw(state say);
#use warnings;
use English;
use strict;
use DateTime;
# https://github.com/DavidLittle/bitstamp-banana.git
use Text::CSV_XS qw(csv);
use Data::Dumper;
use Storable qw(dclone store retrieve);
use JSON::Parse qw(parse_json json_file_to_perl);
use LWP::Simple;
use vars qw(%opt);
use Getopt::Long;

# Commandline args
GetOptions('d:s' => \$opt{datadir}, # Data Directory address
			'g:s' => \$opt{g}, # 
			'h' => \$opt{h}, # 
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'o:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address

			'bitstamp:s' => \$opt{bitstamp}, # starting address
			'classic:s' => \$opt{classic}, # starting address
			'ether:s' => \$opt{ether}, # starting address
			'shapeshift:s' => \$opt{shapeshift}, # starting address
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{desc} ||= "AddressDescriptions.dat";
$opt{key} ||= ''; # from etherscan.io
$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.

$opt{bitstamp} ||= "BitstampTransactions.dat";
$opt{classic} ||= "ClassicTransactions.dat";
$opt{ether} ||= "EtherTransactions.dat";
$opt{shapeshift} ||= "ShapeshiftTransactions.dat";

# Global variables

#Shapeshift transactions have minimal data. Therefore enrich with data from the same transaction captured elsewhere
sub enrichShapeShiftTransactions { 
	my ($st,$all) = @_;
	my (%hdict, %adict);
	my $enriched;
	
	# create dictionary of transactions keyed on txhash
	foreach my $a (@$all) {
		if ($a->{to} eq '0x85a9962fbc35549afec891c285b3fe057ec334cc') { say "Found it 0x85a9962fbc35549afec891c285b3fe057ec334cc"};
		$hdict{lc($a->{hash})} = $a;
		$adict{lc($a->{to})} = $a;
		$adict{lc($a->{from})} = $a;
	}
#	print Dumper $adict{'0x85a9962fbc35549afec891c285b3fe057ec334cc'};
	
	# enrich shapeshit transactions from the dict
	my %count;
	foreach my $t (@$st) {
		if ($t->{address} eq '0x85a9962fbc35549afec891c285b3fe057ec334cc') { say "Found IT 0x85a9962fbc35549afec891c285b3fe057ec334cc"};
		$count{all}++;
		$count{"Status $t->{status}"}++; 
		if ($t->{status} eq 'error') {
			next;
		}
		$count{"OutgoingType $t->{outgoingType}"}++; 
		$count{"IncomingType $t->{incomingType}"}++; 
		if ($t->{outgoingType} eq 'BTC') {
#			next;
		}
		
		my $h = lc($t->{transaction});
		if ($h and $t->{outgoingType} =~ /ET[CH]/) {
			$h = "0x$h";
			$h =~ s/0x0x/0x/;
		}
		if ($h and $hdict{$h}) {
			$t->{T} = $hdict{$h}->{T};
			$t->{timeStamp} = $hdict{$h}->{timeStamp};
			$t->{to} = $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapesHit';
			$count{h}++;
			push @$enriched, $t;
			next;
		}
		$h = substr($h,0,9); # hashes from Gastracker.io (ETC) have truncated transaction hashes
		if ($h and $hdict{$h}) {
			$t->{T} = $hdict{$h}->{T};
			$t->{timeStamp} = $hdict{$h}->{timeStamp};
			$t->{to} = $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapesHIT';
			$count{shorthash}++;
			push @$enriched, $t;
			next;
		}
		my $a = lc($t->{address}); #ss deposit address
		if ($a) {
			$a = "0x$a";
			$a =~ s/0x0x/0x/;
		}
		if ($a and $adict{$a}) {
			$t->{T} = $adict{$a}->{T};
			$t->{timeStamp} = $adict{$a}->{timeStamp};
			$t->{to} = $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShApeshit';
			$count{a}++;
			push @$enriched, $t;
			next;
		}
		my $w = lc($t->{withdraw}); #ss withdrawal address
		if ($w) {
			$w = "0x$w";
			$w =~ s/0x0x/0x/;
		}
		if ($w and $adict{$w}) {
			$t->{T} = $adict{$w}->{T};
			$t->{timeStamp} = $adict{$w}->{timeStamp};
			$t->{to} = $t->{withdraw};
			$t->{toS} = substr($t->{to},0,6);
			$t->{toDesc} = $t->{outgoingType};
			$t->{from} = $t->{address};
			$t->{fromS} = substr($t->{from},0,6);
			$t->{fromDesc} = $t->{incomingType};
			$t->{Value} = $t->{incomingCoin};
			$t->{ccy} = $t->{incomingType};
			$t->{source} = 'ShapeshiW';
			$count{w}++;
			push @$enriched, $t;
			next;
		}
		$count{none}++;	
	}
	print Dumper \%count;		
	return $enriched;
}

sub printTransactions {
	my ($transactions,$sstransactions) = @_;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		print "$t->{source} $t->{T} $t->{fromS} $t->{amount} $t->{fromDesc} $t->{'Value'} $t->{ccy} $t->{toS} $t->{toDesc}\n";
	}
}
#Main Program

my ($bt, $ct, $et, $st) = ([],[],[],[]);
#$bt = retrieve("$opt{datadir}/$opt{bitstamp}");
$ct = retrieve("$opt{datadir}/$opt{classic}");
$et = retrieve("$opt{datadir}/$opt{ether}");
$st = retrieve("$opt{datadir}/$opt{shapeshift}");

my $all = [];
push(@$all, @$bt, @$ct, @$et);
my $richer = enrichShapeShiftTransactions($st, $all);
push(@$all, @$richer);
printTransactions($richer);
#foreach my $i (@$st) {
#	print Dumper $i if $i->{address} eq '0x85a9962fbc35549afec891c285b3fe057ec334cc';
#}

