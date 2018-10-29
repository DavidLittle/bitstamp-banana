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

package Person;

use Class::Tiny qw(id name);

my $ownermap = {
	1 => 'Richard',
	2 => 'David',
	3 => 'Kevin',
	4 => 'ShapeShift',
	5 => 'SteveMarston',
	6 => 'Anna',
	7 => 'Helen',
	8 => 'Martin',
	9 => 'Bruce',
	10 => 'Mark',
	11 => 'Rosie',
	12 => 'Fran',
	13 => 'Avery',
	14 => 'William Medcalf',
	15 => 'ENS',
	16 => 'Kjellin',
	17 => 'ReplaySafeSplit',
	18 => 'TKN',
	19 => 'Unknown',
	20 => 'Kraken',
	21 => 'Marc Little',
	22 => 'Mark Howe',
	23 => 'Ether Contract',
	24 => 'Eth Genesis',
	25 => 'Philip',
	26 => 'Julia',
	27 => 'Bitstamp',
	28 => 'Solidity',
	29 => 'itBit',
	30 => 'Poloniex',
	31 => 'Terry',
	32 => 'Alice',
	33 => 'MtGox',
	34 => 'LocalBitcoins',
};
my $revownermap;
while (my ($key, $value) = each(%$ownermap)) {$revownermap->{$value} = $key};


sub BUILDARGS {
	my $self = shift;
	return {
	};
}


sub BUILD {
	my ($self, $args) = @_;
	while ( my ($key, $val) = each %$ownermap) {
		$revownermap->{$val} = $key;
	}
}

sub name {
	my ($self, $id) = @_;
	return $ownermap->{$id};
}
sub id {
	my ($self, $name) = @_;
	return $revownermap->{$name};
}

return 1;
