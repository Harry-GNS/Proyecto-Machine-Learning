package Market::MarketData;
use strict;
use warnings;
sub new {
my ($class) = @_;
my $self = {
data => {},
};
bless $self, $class;
return $self;
}
sub get_data {
my ($self) = @_;
# TODO
}
sub add_candle {
my ($self, $candle) = @_;
# TODO
}
sub build_tf_candles {
my ($self, $tf) = @_;
# TODO
}
sub build_timeframes {
my ($self) = @_;
# TODO
}
sub set_timeframe {
my ($self, $tf) = @_;
# TODO
}
sub _active_array {
