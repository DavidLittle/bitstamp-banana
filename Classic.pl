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
use lib '.';
use Account;
use AccountsList;
use Transaction;
use TransactionUtils;

# Ethereum Classic account tracker
# Serveral ETC block explorer - do they cover early history, do they have APIs
# gastracker.io - only post split, no API
# etherhub.io - only post split
# etcchain.com - broken
# minergate.com - broken
# etherx.com - broken

# Commandline args
GetOptions(
	'balances!' => \$opt{balances}, # Data Directory address
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'desc:s' => \$opt{desc}, #
	'g:s' => \$opt{g}, #
	'help' => \$opt{h}, #
	'key:s' => \$opt{key}, # API key to access etherscan.io
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'transCSV:s' => \$opt{trans}, # CSV file containing the transactions
	'trans:s' => \$opt{trans}, # datafile to save the classic transactions
);

# ETC transactions are copied/pasted into ClassicTransactions.csv from gastracker.io. Reformatted here and loaded into structure for printing etc.

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{transCSV} ||= "ClassicTransactions.csv"; # Used to input the transactions
$opt{trans} ||= "ClassicTransactions.dat"; # Used to save the transactions
#$opt{start} ||= "";

# Global variables
my %M = ('Jan'=>1,'Feb'=>2,"Mar"=>3,"Apr"=>4,"May"=>5,"Jun"=>6,"Jul"=>7,"Aug"=>8,"Sep"=>9,"Oct"=>10,"Nov"=>11,"Dec"=>12);


sub readClassicTransactions { # take an address return a pointer to array of hashes containing the transactions found on that address
	my ($transactions) = @_;
	state $processed;
	my $aoh = []; #Array of hashes

	my $f = "$opt{datadir}/$opt{transCSV}";
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
		# The following accounts were used in both ETC and ETH - we want accounts to be unique to the currency so for any dual use accounts we add etc to the end

		$tran->{to_account} = AccountsList->account($tran->{to} || 'Unknown');
		$tran->{from_account} = AccountsList->account($tran->{from} || 'Unknown');
		if(!defined $tran->{to_account} or !defined $tran->{from_account}) {
			say "Oops from_account $tran->{from}";
			say "Oops to_account $tran->{to}";
		}

		my ($d,$m,$y,$tim) = split(/ /, $tran->{Timestamp} );
		$y =~ s/,//;
		my ($h, $min) = split(/:/, $tim);
		$tran->{dt} = DateTime->new(year => $y, month => $M{$m}, day => $d, hour => $h, minute => $min, second => 0, time_zone  => "UTC");
		$tran->{source} = 'Gastrackr'; # to identify the source in Banana
		my ($val, $ccy) = split(/ /, $tran->{'Value'});
		$tran->{valueETC} = $val;
#		$tran->{valueSat} = $val * 1e18;
		$tran->{currency} = "ETC";
		# Following fields are for the printMySQLTransactions
		$tran->{tran_type} = "Transfer";
		$tran->{tran_subtype} = "Classic";
		$tran->{amount} = $tran->{valueETC}; # Should amount and value both be the same?
		$tran->{value} = $tran->{valueETC};

		my $T = Transaction->new($tran);

		push @$transactions, $T;
	}
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

AccountsList->new();
my $a = AccountsList->accounts('ETC');

my $transactions = [];
readClassicTransactions($transactions);

if ($opt{balances}) {
	TransactionUtils->printBalances($transactions);
}
elsif ($opt{quick}) {
	TransactionUtils->printTransactions($transactions);
}
else {
	TransactionUtils->printMySQLTransactions($transactions);
}
saveTransactions($transactions);
