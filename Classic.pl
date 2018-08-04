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


# Ethereum Classic account tracker
# Serveral ETC block explorer - do they cover early history, do they have APIs
# gastracker.io - only post split, no API
# etherhub.io - only post split
# etcchain.com - broken
# minergate.com - broken
# etherx.com - broken

# Commandline args
GetOptions('d:s' => \$opt{datadir}, # Data Directory address
			'g:s' => \$opt{g}, # 
			'h' => \$opt{h}, # 
			'key:s' => \$opt{key}, # API key to access etherscan.io
			'o:s' => \$opt{owner}, # 
			'start:s' => \$opt{start}, # starting address
			'trans:s' => \$opt{trans}, # starting address
);

# ETC transactions are copied/pasted into ClassicTransactions.csv from gastracker.io. Reformatted here and loaded into structure for printing etc.

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{desc} ||= "AddressDescriptions.dat";
$opt{trans} ||= "ClassicTransactions.dat";
#$opt{key} ||= ''; # from No API key available
#$opt{owner} ||= "David"; # Owner of the Bitstamp account. Could be Richard, David, Kevin, etc - used in the mapping of Banana account codes.
#$opt{start} ||= "";

# Global variables
my %M = ('Jan'=>1,'Feb'=>2,"Mar"=>3,"Apr"=>4,"May"=>5,"Jun"=>6,"Jul"=>7,"Aug"=>8,"Sep"=>9,"Oct"=>10,"Nov"=>11,"Dec"=>12);

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub addressDesc {
	my ($address, $field) = @_;
	$field ||= 'Desc'; #  default is to return the description for the given address
	state $desc = undef; # Descriptions keyed on address
	$address = lc $address; # force lowercase for lookups
	if (not defined $desc) {
		my $ad  = csv( in => "$opt{datadir}/$opt{desc}", headers => "auto", filter => {1 => sub {length > 1} } );
		foreach my $rec (@$ad) {
			$rec->{Address} = lc $rec->{Address}; # force lowercase
			$desc->{$rec->{Address}} = $rec;
#			$desc->{$rec->{Address}} = $rec->{Desc};
#			if ($rec->{Follow} eq 'N') {
#				$done->{$rec->{Address}} = 1 ; # pretend we've already done and therefore processed this address
#			}
		}
	}
	return $desc->{$address}{$field};
}


sub readClassicTransactions { # take an address return a pointer to array of hashes containing the transactions found on that address
	my ($transactions) = @_;
	state $processed;
	my $aoh = [];

	my $f = "$opt{datadir}/ClassicTransactions.csv";
	if (-e $f) {
		$aoh = csv( in => $f, headers => "auto");
	}
	else {
		say "Missing file $f ";
	}
	
	foreach my $tran (@$aoh) {
		next if $tran->{Block} eq ''; # Ignore blank lines
		$tran->{'hash'} = $tran->{'Tx Hash'};
		next if $processed->{$tran->{hash}} == 1; # Frequently get same transaction from both sides
		$processed->{$tran->{hash}} = 1;
		my ($to, $from);
		if ($tran->{Type} eq 'OUT') {
			$tran->{to} = lc $tran->{'To / From'};
			$tran->{from} = lc $tran->{'Source address in gastracker'};
		}
		elsif ($tran->{Type} eq 'IN') {
			$tran->{from} = lc $tran->{'To / From'};
			$tran->{to} = lc $tran->{'Source address in gastracker'};
		}
		else {
			die "Unexpected Type: $tran->{type};";
		}
		$tran->{to} =~ s/\W//g; # remove any spaces or special characters that got pasted in
		$tran->{from} =~ s/\W//g; # remove any spaces or special characters that got pasted in
		my ($d,$m,$y,$tim) = split(/ /, $tran->{Timestamp} );
		$y =~ s/,//;
		my ($h, $min) = split(/:/, $tim);
		my $dt = DateTime->new(year => $y, month => $M{$m}, day => $d, hour => $h, minute => $min, second => 0, time_zone  => "UTC");
		$tran->{source} = 'Gastrackr'; # to identify the source in Banana
		$tran->{T} = $dt->dmy("/") . " " . $dt->hms();
		$tran->{timeStamp} = $dt->epoch();
		$tran->{toDesc} = addressDesc($tran->{to}) || "Unknown";
		$tran->{fromDesc} = addressDesc($tran->{from}) || "Unknown";
		$tran->{toS} = substr($tran->{to},0,6);
		$tran->{fromS} = substr($tran->{from},0,6);
		my ($val, $ccy) = split(/ /, $tran->{'Value'});
		$tran->{Value} = $val;
		$tran->{value} = $val * 1e18;
		$tran->{ccy} = $ccy eq "ether" ? "ETC" : "Unknown";
		$tran->{toDesc} .= $tran->{to} if $tran->{toDesc} eq 'Unknown'; # to check on shapeshift
		push @$transactions, $tran;
	}
}

sub printTransactions {
	my ($transactions,$address) = @_;
	my $processed;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		next if $address and $t->{from} ne $address and $t->{to} ne $address;
		print "$t->{T} $t->{fromS} $t->{fromDesc} $t->{'value'} $t->{ccy} $t->{toS} $t->{toDesc} $t->{to}\n";
	}
}

sub calcBalances {
	my $transactions = shift;
	my $processed;
	my $balances;
	foreach my $t (sort {$a->{timeStamp} <=> $b->{timeStamp}} @$transactions) {
		next if $processed->{$t->{hash}};
		$processed->{$t->{hash}} = 1;
		#$balances->{'txnFee'} += $t->{'txnFee'};
		#$balances->{$t->{from}} -= $t->{'txnFee'}; # process tx fee even if this is an error transaction
		#next if $t->{isError}; # Typically out of gas (make sure fees are processed but principal is not.
		$balances->{$t->{from}} -= $t->{'Value'};
		$balances->{$t->{to}} += $t->{'Value'};
	}
	return $balances;
}

sub printBalances {
	my $balances = shift;
	foreach my $address (sort keys %$balances) {
		next if addressDesc($address,'Follow') eq 'N';
		my $bal1 = $balances->{$address};
		say "$address $bal1 " . addressDesc($address);
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

addressDesc();
my $transactions = [];
readClassicTransactions($transactions);
#say Dumper $transactions;
printTransactions($transactions);
my $b = calcBalances($transactions);
printBalances($b);
saveTransactions($transactions);


