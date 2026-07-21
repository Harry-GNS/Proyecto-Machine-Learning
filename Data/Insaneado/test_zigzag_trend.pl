#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::ZigZagTrend;
use Market::Overlays::ZigZagTrend;

sub c {
    my ($i, $h, $l) = @_;
    return {
        time   => sprintf('2026-06-29T00:%02d:00', $i),
        open   => ($h + $l) / 2,
        high   => $h,
        low    => $l,
        close  => ($h + $l) / 2,
        volume => 1000,
    };
}

sub run_zz {
    my ($candles, %args) = @_;
    my $zz = Market::Indicators::ZigZagTrend->new(%args);
    for my $i (0 .. $#$candles) {
        $zz->update_candle($candles->[$i], $i);
    }
    return $zz;
}

my $candles = [
    c(0, 10, 5),
    c(1, 11, 6),
    c(2, 12, 7),
    c(3, 11, 8),
    c(4, 10, 4),
    c(5,  9, 5),
    c(6, 13, 6),
    c(7, 12, 7),
];

my $zz = run_zz($candles, swingLength => 3);
my $values = $zz->get_values;

is($values->[0]{swing_high}, 10, 'swingHigh incluye la vela actual');
is($values->[0]{swing_low},   5, 'swingLow incluye la vela actual');
is($values->[0]{trend}, 'bearish', 'primera vela queda bearish si high y low son extremos');
is($values->[0]{trend_changed}, 0, 'no hay evento contra estado previo indefinido');

is($values->[1]{trend}, 'bullish', 'nuevo maximo cambia tendencia a bullish');
is($values->[1]{trend_changed}, 1, 'detecta cambio bearish -> bullish');
is($values->[1]{low_pivot}{index}, 0, 'confirma pivot bajo en la barra anterior');
is($values->[1]{low_pivot}{price}, 5, 'pivot bajo usa low[1]');

is($values->[3]{high_pivot}{index}, 2, 'confirma pivot alto cuando la barra siguiente no extiende el maximo');
is($values->[3]{high_pivot}{price}, 7, 'pivot alto usa low[1] por fidelidad al original');
is($values->[3]{high_pivot}{price_source}, 'low[1]', 'expone fuente fiel low[1] para pivot alto');

is($values->[4]{trend}, 'bearish', 'nuevo minimo cambia tendencia a bearish');
is($values->[4]{trend_changed}, 1, 'detecta cambio bullish -> bearish');

is($values->[5]{low_pivot}{index}, 4, 'confirma nuevo pivot bajo tras rebote');
is($values->[5]{low_pivot}{price}, 4, 'precio de pivot bajo = low[1]');

is($values->[6]{trend}, 'bullish', 'nuevo maximo cambia tendencia de vuelta a bullish');
is($values->[6]{trend_changed}, 1, 'detecta cambio bearish -> bullish');

my $segments = $zz->completed_segments;
is(scalar @$segments, 2, 'guarda solo tramos completados');
is($segments->[0]{direction}, 'bullish', 'primer tramo completado es bullish');
is($segments->[0]{start_index}, 0, 'tramo bullish arranca en ultimo pivot bajo');
is($segments->[0]{start_price}, 5, 'tramo bullish conserva precio del pivot bajo');
is($segments->[0]{end_index}, 2, 'tramo bullish termina en ultimo pivot alto');
is($segments->[0]{end_price}, 7, 'tramo bullish termina con precio ChartPrime low[1]');
is($segments->[0]{completed_at}, 4, 'tramo bullish se cierra al cambiar a bearish');

is($segments->[1]{direction}, 'bearish', 'segundo tramo completado es bearish');
is($segments->[1]{start_index}, 2, 'tramo bearish arranca en ultimo pivot alto');
is($segments->[1]{end_index}, 4, 'tramo bearish termina en ultimo pivot bajo actualizado');
is($segments->[1]{end_price}, 4, 'tramo bearish actualiza extremo mientras sigue la tendencia');
is($segments->[1]{completed_at}, 6, 'tramo bearish se cierra al cambiar a bullish');

my $active = $zz->active_segment;
is($active->{direction}, 'bullish', 'mantiene tramo activo despues del ultimo cambio');
is($active->{end_index}, 6, 'tramo activo repaint: actualiza extremo con nuevo pivot alto');
is($active->{end_price}, 6, 'tramo activo usa low[1] tambien para pivot alto nuevo');
ok($active->{repaint_updates} >= 1, 'registra actualizaciones repaint del tramo activo');

my $external_shapes = Market::Overlays::ZigZagTrend->build_shapes(
    segments          => $zz->completed_segments,
    active_segment    => $zz->active_segment,
    values            => $zz->get_values,
    max_visible_index => $#$candles,
    timeframe         => '1m',
);
ok(scalar(grep { ($_->{kind} // '') eq 'line' } @$external_shapes) >= 1,
    'overlay externo conserva lineas de zigzag');
is(scalar(grep {
    ($_->{kind} // '') eq 'label'
        && ($_->{source_type} // '') eq 'zigzag_trend'
        && (($_->{text} // '') =~ /^ZZ\s[HL]$/)
} @$external_shapes), 0, 'overlay externo no emite etiquetas visuales ZZH/ZZL');

my $zz_bullish_fib = run_zz($candles, swingLength => 3, high_pivot_price_source => 'high');
my $bullish_fib_shapes = Market::Overlays::ZigZagTrend->build_shapes(
    segments            => $zz_bullish_fib->completed_segments,
    active_segment      => $zz_bullish_fib->active_segment,
    values              => $zz_bullish_fib->get_values,
    candles             => $candles,
    max_visible_index   => $#$candles,
    timeframe           => '1m',
    show_auto_fibonacci => 1,
);
my @bullish_fib_levels = grep {
    ($_->{source_type} // '') eq 'auto-external-zigzag-fibonacci'
        && ($_->{kind} // '') eq 'fib_line'
} @$bullish_fib_shapes;
is(scalar @bullish_fib_levels, 7, 'Fib automatico externo emite exactamente siete niveles');
is_deeply([ map { $_->{color} } @bullish_fib_levels ],
    ['#FF0000', '#FF7F00', '#FFD600', '#00C853', '#00BCD4', '#2962FF', '#8E24AA'],
    'Fib automatico externo usa paleta arcoiris clasica');
my %bullish_by_ratio = map { ($_->{fib_ratio} + 0) => $_ } @bullish_fib_levels;
is($bullish_by_ratio{0}{anchor_a_index}, 4, 'Fib alcista ancla A en ultimo minimo confirmado');
is($bullish_by_ratio{0}{anchor_a_price}, 4, 'Fib alcista 0% queda en precio A');
is($bullish_by_ratio{1}{anchor_b_index}, 6, 'Fib alcista ancla B en maximo provisional del tramo');
is($bullish_by_ratio{1}{anchor_b_price}, 13, 'Fib alcista 100% queda en precio B');
is(sprintf('%.3f', $bullish_by_ratio{0.5}{fib_price}), sprintf('%.3f', 8.5),
    'Fib alcista usa A + (B - A) * ratio');

my $zz_bearish_fib = run_zz([ @$candles[0 .. 5] ], swingLength => 3, high_pivot_price_source => 'high');
my $bearish_fib_shapes = Market::Overlays::ZigZagTrend->build_shapes(
    segments            => $zz_bearish_fib->completed_segments,
    active_segment      => $zz_bearish_fib->active_segment,
    values              => $zz_bearish_fib->get_values,
    candles             => [ @$candles[0 .. 5] ],
    max_visible_index   => 5,
    timeframe           => '1m',
    show_auto_fibonacci => 1,
);
my @bearish_fib_levels = grep {
    ($_->{source_type} // '') eq 'auto-external-zigzag-fibonacci'
        && ($_->{kind} // '') eq 'fib_line'
} @$bearish_fib_shapes;
is(scalar @bearish_fib_levels, 7, 'Fib bajista externo emite exactamente siete niveles');
my %bearish_by_ratio = map { ($_->{fib_ratio} + 0) => $_ } @bearish_fib_levels;
is($bearish_by_ratio{0}{anchor_a_index}, 2, 'Fib bajista ancla A en ultimo maximo confirmado');
is($bearish_by_ratio{0}{anchor_a_price}, 12, 'Fib bajista 0% queda en precio A');
is($bearish_by_ratio{1}{anchor_b_index}, 4, 'Fib bajista ancla B en minimo provisional del tramo');
is($bearish_by_ratio{1}{anchor_b_price}, 4, 'Fib bajista 100% queda en precio B');
is(sprintf('%.3f', $bearish_by_ratio{0.5}{fib_price}), sprintf('%.3f', 8),
    'Fib bajista usa A + (B - A) * ratio sin invertir anchors');

my $internal_shapes = Market::Overlays::ZigZagTrend->build_shapes(
    segments          => $zz->completed_segments,
    active_segment    => $zz->active_segment,
    values            => $zz->get_values,
    max_visible_index => $#$candles,
    timeframe         => '1m',
    source_type       => 'zigzag_trend_internal',
    color_prefix      => 'zigzag_internal',
    structure_scope   => 'internal',
    show_pivots       => 0,
    line_width        => 1.0,
);
ok(@$internal_shapes >= 1, 'overlay interno genera lineas de zigzag');
is($internal_shapes->[0]{source_type}, 'zigzag_trend_internal', 'overlay interno usa source_type propio');
like($internal_shapes->[0]{color_role}, qr/^zigzag_internal_/, 'overlay interno usa roles de color propios');
is($internal_shapes->[0]{structure_scope}, 'internal', 'overlay interno se marca como internal');
is(scalar(grep { ($_->{kind} // '') eq 'label' } @$internal_shapes), 0, 'overlay interno no emite etiquetas de pivote por defecto en UI');

my $zz_high_price = run_zz(
    [ @$candles[0 .. 3] ],
    swingLength => 3,
    high_pivot_price_source => 'high',
);
my $high_price_values = $zz_high_price->get_values;
is($high_price_values->[3]{high_pivot}{price}, 12, 'opcionalmente el pivot alto puede usar high[1]');
is($high_price_values->[3]{high_pivot}{price_source}, 'high[1]', 'expone fuente alternativa high[1]');

my $edge = run_zz(
    [
        c(0, 10, 5),
        c(1, 11, 6),
        c(2, 12, 4),
    ],
    swingLength => 3,
);
my $edge_values = $edge->get_values;
is($edge_values->[1]{trend}, 'bullish', 'prepara estado bullish antes del caso borde');
is($edge_values->[2]{swing_high}, 12, 'caso borde: high es swingHigh');
is($edge_values->[2]{swing_low},   4, 'caso borde: low es swingLow');
is($edge_values->[2]{trend}, 'bearish', 'si high y low son extremos en la misma barra, queda bearish');
is($edge_values->[2]{trend_changed}, 1, 'el caso borde emite cambio de tendencia si venia bullish');

done_testing();
