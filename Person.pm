package Person;

use Moose;
use Moose::Util::TypeConstraints;

use Carp qw(croak carp confess);

my $ownermap;
my $revownermap;

has id		=> (is => 'rw', isa => 'Int', );
has name 	=> (is => 'rw', isa => 'Str', );

around BUILDARGS => sub {
	my $orig  = shift;
	my $class = shift;
	$ownermap = {
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

	if ( @_ == 1 ) {
		if (exists $ownermap->{$_[0]}) {
			return $class->$orig(id=>$_[0], name => $ownermap->{$_[0]});
        }
		while ( my ($key, $val) = each %$ownermap) {
			$revownermap->{$val} = $key;
		}
		if (exists $revownermap->{$_[0]}) {
			return $class->$orig(name=>$_[0], id => $revownermap->{$_[0]});
        }
		if ($_[0] eq "") {
			return $class->$orig(name=>"Unknown", id => 19);
		}
		confess("Unknown person requested: $_[0]");
    }
    else {
        return $class->$orig(@_);
    }
};


no Moose;
__PACKAGE__->meta->make_immutable;

return 1;
