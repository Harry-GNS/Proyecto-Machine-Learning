#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::InternalZigZag;

sub c {
    my ($i, $h, $l, $o, $cl) = @_;
    $o  = ($h + $l) / 2 unless defined $o;
    $cl = ($h + $l) / 2 unless defined $cl;
    return {
        time   => sprintf('2026-06-29T00:%02d:00', $i),
        open   => $o,
        high   => $h,
        low    => $l,
        close  => $cl,
        volume => 1000,
    };
}

sub atr {
    my ($candles, $value) = @_;
    return [ map { $value } @$candles ];
}

my $candles = [
    c(0, 10,  9),
    c(1, 12, 10),
    c(2, 14, 11),
    c(3, 13, 10),
    c(4, 12,  9),
    c(5, 11,  7),
    c(6, 12,  9),
    c(7, 13, 10),
    c(8, 16, 12),
    c(9, 15, 11),
    c(10,14, 10),
    c(11,13,  6),
    c(12,14,  8),
    c(13,15,  9),
];

my $zz = Market::Indicators::InternalZigZag->compute(
    candles           => $candles,
    atr_series        => atr($candles, 1),
    max_visible_index => $#$candles,
    timeframe         => '1m',
    pivot_length      => 2,
    min_leg_bars      => 2,
    atr_multiplier    => 1,
);

my $pivots = $zz->{pivots};
ok(@$pivots >= 3, 'detecta pivotes estructurales internos confirmados');
is_deeply([ map { $_->{type} } @$pivots ], [qw(HIGH LOW HIGH LOW)], 'los pivotes alternan HIGH LOW');
is($pivots->[0]{index}, 2, 'primer swing high en indice real');
is($pivots->[0]{price}, $candles->[2]{high}, 'swing high usa high real');
is($pivots->[1]{index}, 5, 'swing low en indice real');
is($pivots->[1]{price}, $candles->[5]{low}, 'swing low usa low real');
ok($pivots->[0]{confirmed_at} <= $#$candles, 'pivot confirmado dentro del max visible');

my $debug = $zz->{debug_pivots};
is($debug->[0]{type}, 'HIGH', 'debug expone tipo HIGH');
is($debug->[0]{confirmed}, 1, 'debug expone confirmed');

my $early = Market::Indicators::InternalZigZag->compute(
    candles           => $candles,
    atr_series        => atr($candles, 1),
    max_visible_index => 3,
    timeframe         => '1m',
    pivot_length      => 2,
    min_leg_bars      => 2,
    atr_multiplier    => 1,
);
is(scalar @{ $early->{pivots} }, 0, 'no confirma pivot antes de tener velas derechas suficientes');

my $same_leg = [
    c(0, 10, 8),
    c(1, 12, 9),
    c(2, 14, 11),
    c(3, 13, 10),
    c(4, 15, 12),
    c(5, 14, 11),
    c(6, 13, 7),
    c(7, 12, 8),
];
my $same = Market::Indicators::InternalZigZag->compute(
    candles           => $same_leg,
    atr_series        => atr($same_leg, 1),
    max_visible_index => $#$same_leg,
    timeframe         => '1m',
    pivot_length      => 1,
    min_leg_bars      => 2,
    atr_multiplier    => 1,
);
is($same->{pivots}[0]{type}, 'HIGH', 'arranca con high');
is($same->{pivots}[0]{index}, 4, 'reemplaza high de la misma pierna por el mas extremo');
is($same->{pivots}[0]{price}, 15, 'conserva el precio high mas extremo');

my $atr_filtered = Market::Indicators::InternalZigZag->compute(
    candles           => $candles,
    atr_series        => atr($candles, 10),
    max_visible_index => $#$candles,
    timeframe         => '1m',
    pivot_length      => 2,
    min_leg_bars      => 2,
    atr_multiplier    => 2,
);
ok(scalar(@{ $atr_filtered->{pivots} }) < scalar(@$pivots), 'filtro ATR elimina swings sin desplazamiento suficiente');

my $segments = $zz->{segments};
ok(@$segments >= 1, 'genera segmentos completados');
ok($zz->{active_segment}, 'mantiene ultimo tramo como activo/provisional');
is($zz->{active_segment}{start_index}, $pivots->[-2]{index}, 'tramo activo inicia en penultimo pivot');
is($zz->{active_segment}{end_index}, $pivots->[-1]{index}, 'tramo activo termina en ultimo pivot');

done_testing();
