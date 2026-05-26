package Market::Indicators::ATR;
use strict;
use warnings;
use List::Util qw(max);

sub new {
    my ($class, $period) = @_;
    my $self = {
        period => $period || 14,
        values => [], # Historial del ATR
        tr_history => [],
    };
    bless $self, $class;
    return $self;
}

sub update_last {
    my ($self, $market_data) = @_;
    my $index = $market_data->size() - 1;
    return if $index < 0;

    my $current = $market_data->get_candle($index);
    my $tr;

    if ($index == 0) {
        $tr = $current->{high} - $current->{low};
    } else {
        my $prev = $market_data->get_candle($index - 1);
        my $hl = $current->{high} - $current->{low};
        my $hc = abs($current->{high} - $prev->{close});
        my $lc = abs($current->{low} - $prev->{close});
        $tr = max($hl, $hc, $lc);
    }
    
    push @{$self->{tr_history}}, $tr;

    # Cálculo del ATR (Media Suavizada de Wilder)
    if ($index == 0) {
        push @{$self->{values}}, $tr;
    } else {
        my $prev_atr = $self->{values}->[-1];
        my $n = $self->{period};
        my $current_atr = (($prev_atr * ($n - 1)) + $tr) / $n;
        push @{$self->{values}}, $current_atr;
    }
}
