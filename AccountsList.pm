package AccountsList;

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
use Person;
use Account;

use Carp qw(carp croak confess);

use Class::Tiny qw(datadir file address addresses);

my $addresses;
my $accounts;

sub BUILDARGS {
	my $self = shift;
	my $datadir = shift || "/home/david/Dropbox/Investments/Ethereum/Etherscan";
	my $file = shift || "AccountsListV3.csv";
	return {
		datadir => $datadir,
		file => $file,
	};
}

#sub new {
#	my $class = shift;
#
#	my $self = {};
#	bless $self, $class;
#
#	$self->_initialise();
#
#	return $self;
#}

sub BUILD {
	my ($self, $args) = @_;
	my $datadir = $self->{datadir};
	my $file = $self->{file};
	my $in = "$datadir/$file";
	my $ad  = Text::CSV_XS::csv( in => $in, headers => "auto", filter => {2 => sub {length >= 1} } );
	foreach my $rec (@$ad) {
		$rec->{AccountRef} = lc $rec->{AccountRef} if $rec->{AccountRef} =~ /^0x/; # force lowercase for lookups on Ethereum type addresses
		if (exists $addresses->{$rec->{AccountRef}}) {
			say Dumper $rec;
			say Dumper $addresses->{$rec->{Address}};
			croak "Duplicate address: $rec->{Address}";
		}
		$addresses->{$rec->{AccountRef}} = $rec;
		my $a = Account->new($rec);
		$accounts->{$rec->{AccountRef}} = $a;
	}
	#say ref($self) . "BUILD initialised";
}

# addressDesc returns the description for an address as loaded from the AddressDescriptions.dat file
sub address {
	my ($self, $address, $field) = @_;
	$address = lc $address if $address =~ /^0x/; # force lowercase for lookups on Ethereum type addresses
	return $addresses->{$address}{$field} if defined $field;
	return $addresses->{$address};
}

sub addresses {
	my ($self, $currency) = @_;
	my $res;
	while ( my ($key, $val) = each %$addresses) {
		next if defined $currency and $val->{Currency} ne $currency;
		if ($currency eq 'BCH') {
			$val->{AccountRefUnique} = $val->{AccountRef}; # AccountRefUnique will hold key-bch
			$val->{AccountRef} =~ s/-bch//; # WHat to do with these if all currencies are requested - there will be name clashes with BTC addresses
			$res->{$key} = $val; # key it on both key and key-bch
			$key =~ s/-bch//;
		}
		if ($currency eq 'ETC') {
			$val->{AccountRefUnique} = $val->{AccountRef}; # AccountRefUnique will hold key-bch
			$val->{AccountRef} =~ s/-etc//; # WHat to do with these if all currencies are requested - there will be name clashes with BTC addresses
			$res->{$key} = $val; #key it on both key and key-etc
			$key =~ s/-etc//;
		}
		$res->{$key} = $val;
	}
	$addresses = $res; # A bit controversial! After running this the AccountsList only knows about addresses for this currency.
						# Required by BCH and ETC processing. Otherwise subsequent calls to AccountsList->address() return the wrong address
						# Will be fixed (and can be removed when all programs converted to use AccountRef and AccountRefUnique)
	return $res;
}

sub accounts {
	my ($self, $currency) = @_;
	my $res;
	if (defined $currency) {
		while ( my ($key, $val) = each %$accounts) {
			next if $val->{Currency} ne $currency;
			# AccountRefUnique may hold key-etc or key-bch if this key is used in more than one blockchain
			$res->{$val->{AccountRefUnique}} = $val; #key it on both key and key-etc
			$res->{$val->{AccountRef}} = $val; # If they are the same we just set it twice
		}
		$accounts = $res; # A bit controversial! After running this the AccountsList only knows about addresses for this currency.
						# Required by BCH and ETC processing. Otherwise subsequent calls to AccountsList->address() return the wrong address
						# Will be fixed (and can be removed when all programs converted to use AccountRef and AccountRefUnique)
	}
	return $accounts;
}

sub account {
	my ($self, $address, $field) = @_;
	$address = lc $address if $address =~ /^0x/; # force lowercase for lookups on Ethereum type addresses
	return $accounts->{$address}{$field} if defined $field;
	return $accounts->{$address};
}

sub backCompatible { # Create the old AddressDEscription fields. Can be removed after all programs converted to use Accounts
	my $self = shift;
	while( my ($key, $val) = each %$addresses ) {
		$val->{Address} = $val->{AccountRef};
		$val->{Desc} = $val->{Description};
		$val->{ownerId} = $val->{AccountOwner};
		$val->{Owner} = Person->new($val->{AccountOwner});
	}
}

return 1;
