package Person;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;

use Carp qw(croak carp confess);

my $_reverse_owner_map_built = 0;

class_has 'Cache' =>
    ( is      => 'ro',
      isa     => 'HashRef',
      default => sub { {
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
          35 => 'FloraMarston',
          36 => 'Journal',
	  } }
    );
	class_has 'ReverseCache' =>
	    ( is      => 'ro',
	      isa     => 'HashRef',
	      default => sub { {} }
	    );

has id		=> (is => 'ro', isa => 'Int', );
has name 	=> (is => 'ro', isa => 'Str', );

around BUILDARGS => sub {
	my $orig  = shift;
	my $class = shift;

	if(!keys %{Person->ReverseCache}) {
		my %m = reverse %{Person->Cache};
		while ( my ($key, $val) = each %m) {
			Person->ReverseCache()->{$key} = $val;
		}
		$Person::_reverse_owner_map_built = 1;
	}
	if ( @_ == 1 ) {
		if (exists Person->Cache->{$_[0]}) {
			return $class->$orig(id=>$_[0], name => Person->Cache->{$_[0]});
        }
		if (exists Person->ReverseCache->{$_[0]}) {
			return $class->$orig(name=>$_[0], id => Person->ReverseCache->{$_[0]});
        }
		if ($_[0] eq "") {
			return $class->$orig(name=>"Unknown", id => 19);
		}
		return $class->$orig(name=>"Unknown", id => 19);
		#carp("Unknown person requested: $_[0]"); # TODO: confess or carp?
		#return $class->$orig(@_);
    }
    else {
		return $class->$orig(name=>"Unknown", id => 19);
#        return $class->$orig(@_);
    }
};


no Moose;
__PACKAGE__->meta->make_immutable;

return 1;
