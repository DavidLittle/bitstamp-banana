package Account;

use Moose;
use Moose::Util::TypeConstraints;

use lib '.';
use Person;

enum 'Currency' => [qw( BCH BTC ETC ETH USD GBP EUR DASH)];

has idAccounts 	=> (is => 'ro', isa => 'Int');
has AccountRef 	=> (is => 'rw', isa => 'Str', required => 1,);
has AccountName 	=> (is => 'ro', isa => 'Str');
has Description	=> (is => 'ro', isa => 'Str');
has AccountOwner	=> (is => 'ro', isa => 'Str');
has Currency 	=> (is => 'ro', isa => 'Currency', required => 1,);
has AccountType 	=> (is => 'ro', isa => 'Str');
has Follow 	=> (is => 'rw', isa => 'Str');
has Accountable 	=> (is => 'ro', isa => 'Str');
has ShapeShift 	=> (is => 'ro', isa => 'Str');
has Source 	=> (is => 'ro', isa => 'Str');
has BananaCode 	=> (is => 'ro', isa => 'Str');
has Owner 	=> (is => 'rw', isa => 'Person');
has AccountRefUnique 	=> (is => 'rw', isa => 'Str');
has AccountRefShort	=> (is => 'rw', isa => 'Str');

sub BUILD {
	my ($self, $args) = @_;
    $self->Owner(Person->new($args->{AccountOwner}));
    $self->AccountRefUnique($args->{AccountRef});
    my $t = $args->{AccountRef};
    $t =~ s/-.*//;
    $self->AccountRef($t);
    $self->AccountRefShort(substr($args->{AccountRef},0,8));
	$self->{Follow} = 'N' unless $self->{Follow} eq 'Y';
}

no Moose;
__PACKAGE__->meta->make_immutable;

return 1;
