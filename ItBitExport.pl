use feature qw(state say);
use English;
use strict;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Text::CSV_XS qw(csv);
use Storable qw(dclone store retrieve);
use vars qw(%opt);
use Getopt::Long;
use lib '.';
use Account;
use AccountsList;
use Person;
use Transaction;
use TransactionUtils;

# Process a itBitExport export CSV file so that it is conveniently usableas an import into an accounting system

# Commandline args
GetOptions(
	'balances!' => \$opt{balances}, # Data Directory address
	'datadir:s' => \$opt{datadir}, # Data Directory address
	'g:s' => \$opt{g}, #
	'help' => \$opt{h}, #
	'quick!' => \$opt{quick}, #
	'start:s' => \$opt{start}, # starting address
	'trans:s' => \$opt{trans}, # name of transactions CSV file
	'cablefile:s' => \$opt{cablefile}, # filename of CSV file with USD GBP rates
);

$opt{datadir} ||= "/home/david/Dropbox/Investments/Ethereum/Etherscan";
$opt{start} ||= "";
$opt{trans} ||= "ItBitTransactions.dat";

my $inputs = [
	{
		transactions => "ItBitExportDavid.csv",
		owner => "David",
	},
];

sub readItBitTransactions {
	my ($transactionfile, $owner) = @_;
	my $filename = "$opt{datadir}/$transactionfile";
	my $in = undef;
	my $data = [];
	my $aoh;
	if (-e $filename) {
		$aoh = csv( in => $filename, headers => "auto");
	}
	else {
		say "Missing file $filename";
	}

	my $line_number = 1;
	foreach my $rec (@$aoh) {
		$rec->{tran_type} = 'ItBit';
		$line_number++;
		$rec->{tran_subtype} = $rec->{transaction};
		$rec->{time} =~ s/ /T/; #Change 2017-02-08 14:53:27 to 2017-02-08T14:53:27
		$rec->{dt} = DateTime::Format::ISO8601->parse_datetime( $rec->{time} );
		my $type;
	    #$rec->{amount}; # From ItBit file
	    #$rec->{currency}; # From ItBit file
		$rec->{note} = $rec->{notes}; # from ItBit file
		$rec->{currency} =~ s/^XBT$/BTC/; # ItBit doesn't use convention
		my $currency = $rec->{currency};
		my $type = $rec->{transaction};
    	$rec->{value} = $rec->{amount};
    	$rec->{value_currency} = $rec->{currency};
	    $rec->{rate} = 1;
		$rec->{fee_currency} = $rec->{currency};
		$rec->{from_fee} = $rec->{to_fee} = 0; # We get no fee information from
		$rec->{hash} = "${transactionfile}-Line$line_number";
		my ($toprefix, $fromprefix) = (undef,undef);
		$fromprefix = '0x' if ($currency =~ /^(ETH|ETC)$/);
		$fromprefix = '3' if ($currency =~ /^(BTC|BCH)$/);
		$toprefix = '0x' if ($currency =~ /^(ETH|ETC)$/);
		$toprefix = '3' if ($currency =~ /^(BTC|BCH)$/);
	    if ($type eq "Deposit") {
			$rec->{tran_subtype} = $type;
			${toprefix} = ${fromprefix}; # On a withdrawal to and from are same CCY
	        $rec->{toaccount} = "${toprefix}ItBit${currency}Trading${owner}";
			$rec->{fromaccount} = "${fromprefix}ItBit${currency}Wallet$owner";
			$rec->{value_currency} = $rec->{currency}; # we don't get a value currency from Bitstamp for deposits
	    } elsif ($type eq "Withdrawal") {
			$rec->{tran_subtype} = $type;
			${toprefix} = ${fromprefix}; # On a withdrawal to and from are same CCY
			$rec->{toaccount} = "${toprefix}ItBit${currency}Wallet$owner";
			$rec->{fromaccount} = "${fromprefix}ItBit${currency}Trading$owner";
		} elsif ($type eq "Buy") {
			# Unfortunately ItBit doesn't provide information on Buy and Sell trades
	    } elsif ($type eq "Sell") {
			# Unfortunately ItBit doesn't provide information on Buy and Sell trades
	    }

		$rec->{from_account} = AccountsList->account($rec->{fromaccount});
		$rec->{to_account} = AccountsList->account($rec->{toaccount});

		if (! defined $rec->{from_account}) {
			say "From account undefined $rec->{fromaccount} ($type $currency)";
			next;
		}
		if (ref($rec->{from_account}) ne 'Account') {
			say "From account is not a proper account $rec->{fromaccount} ($type $currency)";
			next;
		}
		if (! defined $rec->{to_account}) {
			say "To account undefined $rec->{toaccount} ($type $currency)";
			next;
		}
		if (ref($rec->{to_account}) ne 'Account') {
			say "To account is not a proper account $rec->{toaccount} ($type $currency)";
			next;
		}

		my $T = Transaction->new($rec);

	    push @$data, $T;
	}
	return $data;
}

sub saveTransactions {
	my $trans = shift;
	store($trans, "$opt{datadir}/$opt{trans}");
}

# Main program
AccountsList->new();
my $data = [];
foreach my $files (@$inputs) {
	my $trans = readItBitTransactions($files->{transactions}, $files->{owner});
	push @$data, @$trans;
}

if($opt{balances}) {
	TransactionUtils->printBalances($data);
}
elsif($opt{quick}) {
	TransactionUtils->printTransactions($data);
}
else {
	TransactionUtils->printMySQLTransactions($data);
}
saveTransactions($data);
