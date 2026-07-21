#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::Strategy_Builder;
use Market::Overlays::Strategy_Builder;

sub iso_min {
    my ($i) = @_;
    return Market::Indicators::Strategy_Builder::_add_minutes_iso('2026-06-29T00:00:00', $i);
}

sub channel_fixture {
    my (%args) = @_;
    my $count      = $args{count}      // 110;
    my $direction  = $args{direction}  // 'bullish';
    my $width      = $args{width}      // 5.0;
    my $slope      = $args{slope}      // 0.05;
    my $atr        = $args{atr}        // 5.0;
    my $break_idx  = $args{break_idx};
    my $break_dir  = $args{break_dir};
    my $time_mode  = $args{time_mode}  // 'iso';
    my $base_epoch = 1_783_036_800;
    my @candles;

    for my $i (0 .. $count - 1) {
        my $phase = $i % 20;
        my $leg = $phase <= 10 ? $phase / 10 : (20 - $phase) / 10;
        my ($lower, $upper, $price);
        if ($direction eq 'bearish') {
            $upper = 125 - $i * $slope;
            $lower = $upper - $width;
            $price = $upper - $width * $leg;
        }
        else {
            $lower = 100 + $i * $slope;
            $upper = $lower + $width;
            $price = $lower + $width * $leg;
        }

        my $close = $price;
        if (defined $break_idx && $i == $break_idx) {
            $close = $break_dir && $break_dir eq 'up'
                ? $upper + $atr * 0.55
                : $lower - $atr * 0.55;
            $price = $close;
        }
        elsif ($args{outside_from} && $i >= $args{outside_from} && $i <= ($args{outside_to} // $i)) {
            $close = $upper + $atr * 0.20;
        }

        if (defined $args{spike_index} && $i == $args{spike_index}) {
            $price = $upper + $atr * 9;
            $close = $upper - $width * 0.20;
        }

        my $time = $time_mode eq 'seconds' ? $base_epoch + $i * 60
                 : $time_mode eq 'millis'  ? ($base_epoch + $i * 60) * 1000
                 : iso_min($i);
        push @candles, {
            time   => $time,
            open   => $close,
            high   => $price + 0.05,
            low    => $price - 0.05,
            close  => $close,
            volume => 1000 + $i,
        };
    }

    return (\@candles, [ map { $atr } 1 .. $count ]);
}

sub detect_channels {
    my (%args) = @_;
    my ($candles, $atr) = channel_fixture(%args);
    my $res = Market::Indicators::Strategy_Builder->compute(
        candles           => $candles,
        atr_series        => $atr,
        pivots            => [],
        max_visible_index => $#$candles,
        timeframe         => '1m',
    );
    return ($res->{channels}, $candles);
}

sub first_channel {
    my (%args) = @_;
    my ($channels, $candles) = detect_channels(%args);
    return ($channels->[0], $channels, $candles);
}

{
    my ($ch, $channels) = first_channel(direction => 'bullish');
    ok($ch, 'detecta canal alcista valido con pivotes confirmados 3/3');
    is($ch->{type}, 'trend_channel', 'usa tipo dedicado');
    is($ch->{direction}, 'bullish', 'clasifica direccion alcista');
    cmp_ok($ch->{duration_minutes}, '>=', 60, 'canal alcista cumple 60 minutos reales');
    cmp_ok($ch->{lower_touches}, '>=', 2, 'canal alcista tiene contactos inferiores');
    cmp_ok($ch->{upper_touches}, '>=', 2, 'canal alcista tiene contactos superiores');
    cmp_ok($ch->{total_touches}, '>=', 4, 'canal alcista tiene cuatro contactos agrupados');
    cmp_ok($ch->{containment_ratio}, '>=', 0.85, 'canal alcista contiene la mayoria de cierres');
    cmp_ok($ch->{width_in_atr}, '>=', 0.75, 'ancho minimo normalizado por ATR');
    cmp_ok($ch->{width_in_atr}, '<=', 8.0, 'ancho maximo normalizado por ATR');
    ok(abs(($ch->{upper_y2} - $ch->{lower_y2}) - ($ch->{upper_y1} - $ch->{lower_y1})) < 0.0001,
       'lineas exteriores son paralelas');
    ok(abs($ch->{center_y1} - (($ch->{upper_y1} + $ch->{lower_y1}) / 2)) < 0.0001,
       'linea central esta exactamente al 50%');
    ok($ch->{anchor1}{confirmed} && $ch->{anchor2}{confirmed}, 'anclajes del canal estan confirmados');
    cmp_ok(scalar(@$channels), '<=', 3, 'deduplicacion limita canales visibles');
}

{
    my ($ch) = first_channel(direction => 'bearish');
    ok($ch, 'detecta canal bajista valido');
    is($ch->{direction}, 'bearish', 'clasifica direccion bajista');
    cmp_ok($ch->{duration_minutes}, '>=', 60, 'canal bajista cumple 60 minutos reales');
    cmp_ok($ch->{upper_touches}, '>=', 2, 'canal bajista tiene contactos en resistencia');
    cmp_ok($ch->{lower_touches}, '>=', 2, 'canal bajista tiene contactos inferiores');
}

{
    my ($ch) = first_channel(direction => 'bullish', break_idx => 96, break_dir => 'down');
    ok($ch, 'conserva canal alcista roto historicamente');
    is($ch->{status}, 'broken', 'ruptura cambia status a broken');
    is($ch->{breakout_direction}, 'down', 'ruptura inferior registrada');
    is($ch->{end_index}, 96, 'extension se detiene en cierre fuerte fuera');
}

{
    my ($ch) = first_channel(direction => 'bearish', break_idx => 96, break_dir => 'up');
    ok($ch, 'conserva canal bajista roto historicamente');
    is($ch->{status}, 'broken', 'ruptura superior cambia status a broken');
    is($ch->{breakout_direction}, 'up', 'ruptura superior registrada');
}

{
    my ($channels) = detect_channels(direction => 'bullish', count => 65);
    is(scalar(@$channels), 0, 'rechaza movimiento menor a 60 minutos reales');
}

{
    my ($channels) = detect_channels(direction => 'bullish', slope => 0);
    is(scalar(@$channels), 0, 'rechaza mercado lateral sin pendiente tendencial');
}

{
    my ($channels) = detect_channels(direction => 'bullish', outside_from => 55, outside_to => 90);
    is(scalar(@$channels), 0, 'rechaza canal con menos de 85% de contencion');
}

{
    my ($channels) = detect_channels(direction => 'bullish', width => 2.0, atr => 5.0);
    is(scalar(@$channels), 0, 'rechaza canal excesivamente estrecho');
}

{
    my ($channels) = detect_channels(direction => 'bullish', width => 45.0, atr => 5.0);
    is(scalar(@$channels), 0, 'rechaza canal excesivamente ancho');
}

{
    my ($ch) = first_channel(direction => 'bullish', spike_index => 50);
    ok($ch, 'una mecha anormal no impide elegir un canal valido');
    cmp_ok($ch->{width_in_atr}, '<=', 8.0, 'la mecha anormal no define un ancho invalido');
    isnt($ch->{opposite_index}, 50, 'la mecha anormal aislada no se usa como ancla opuesta');
}

{
    my @merged = Market::Indicators::Strategy_Builder::_merge_channel_contacts(
        [
            { index => 10, time_ms => 10 * 60_000, price => 1 },
            { index => 11, time_ms => 11 * 60_000, price => 1 },
            { index => 12, time_ms => 12 * 60_000, price => 1 },
            { index => 25, time_ms => 25 * 60_000, price => 1 },
        ],
        { contact_merge_bars => 3, contact_merge_minutes => 10 },
    );
    is(scalar(@merged), 2, 'contactos consecutivos se agrupan como un evento');
}

{
    my ($channels) = detect_channels(direction => 'bullish', time_mode => 'seconds');
    ok(scalar(@$channels) >= 1, 'normaliza timestamps Unix en segundos');
}

{
    my ($channels) = detect_channels(direction => 'bullish', time_mode => 'millis');
    ok(scalar(@$channels) >= 1, 'normaliza timestamps Unix en milisegundos');
}

{
    my ($candles, $atr) = channel_fixture(direction => 'bullish');
    $candles->[30]{time} = $candles->[29]{time};
    my $res = Market::Indicators::Strategy_Builder->compute(
        candles           => $candles,
        atr_series        => $atr,
        pivots            => [],
        max_visible_index => $#$candles,
        timeframe         => '1m',
    );
    is(scalar(@{ $res->{channels} }), 0, 'rechaza timestamps duplicados');
}

{
    my ($candles, $atr) = channel_fixture(direction => 'bullish');
    delete $candles->[20]{close};
    my $res = Market::Indicators::Strategy_Builder->compute(
        candles           => $candles,
        atr_series        => $atr,
        pivots            => [],
        max_visible_index => $#$candles,
        timeframe         => '1m',
    );
    is(scalar(@{ $res->{channels} }), 0, 'rechaza datos OHLCV faltantes');
}

{
    my ($ch, undef, $candles) = first_channel(direction => 'bullish');
    my $shapes = Market::Overlays::Strategy_Builder->build_shapes(
        strategy => { channels => [$ch] },
        max_visible_index => $#$candles,
        timeframe => '1m',
    );
    ok(scalar(grep { ($_->{kind} // '') eq 'trend_channel' && ($_->{color_role} // '') eq 'auto_trend_channel' } @$shapes),
       'overlay expone el canal como shape editable dedicado');
    my ($shape) = grep { ($_->{kind} // '') eq 'trend_channel' } @$shapes;
    is($shape->{status}, $ch->{status}, 'overlay conserva status del canal');
    is($shape->{score}, $ch->{score}, 'overlay conserva score normalizado');
}

done_testing();
