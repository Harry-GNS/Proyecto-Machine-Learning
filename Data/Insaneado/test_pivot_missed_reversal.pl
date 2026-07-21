#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::PivotMissedReversal;
use Market::Overlays::PivotMissedReversal;

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

my $regular_candles = [
    c(0, 10, 5),
    c(1, 11, 6),
    c(2, 15, 7),
    c(3, 12, 6),
    c(4, 11, 4),
    c(5, 10, 6),
    c(6, 14, 7),
    c(7, 13, 6),
    c(8, 12, 5),
];

my $regular = Market::Indicators::PivotMissedReversal->compute(
    candles           => $regular_candles,
    max_visible_index => $#$regular_candles,
    timeframe         => '1m',
    length            => 2,
    show_regular      => 1,
    show_missed       => 1,
);

is($regular->{pivot_length}, 2, 'usa longitud de pivote configurable');
is($regular->{regularPivots}[0]{type}, 'high', 'detecta Pivot High regular');
is($regular->{regularPivots}[0]{index}, 2, 'Pivot High queda en la vela real, no en confirmacion');
is($regular->{regularPivots}[0]{confirmed_at}, 4, 'Pivot High confirma length barras despues');
is($regular->{regularPivots}[0]{price}, 15, 'Pivot High usa high exacto');
is($regular->{regularPivots}[0]{label}, '▼', 'Pivot High regular usa etiqueta de Pine');
is($regular->{regularPivots}[1]{type}, 'low', 'detecta Pivot Low regular');
is($regular->{regularPivots}[1]{index}, 4, 'Pivot Low queda en la vela real');
is($regular->{regularPivots}[1]{confirmed_at}, 6, 'Pivot Low confirma length barras despues');
is($regular->{regularPivots}[1]{price}, 4, 'Pivot Low usa low exacto');
is($regular->{regularPivots}[1]{label}, '▲', 'Pivot Low regular usa etiqueta de Pine');

my $before_confirmation = Market::Indicators::PivotMissedReversal->compute(
    candles           => $regular_candles,
    max_visible_index => 3,
    timeframe         => '1m',
    length            => 2,
);
is(scalar @{ $before_confirmation->{regularPivots} }, 0,
    'no hay look-ahead: el pivot no existe antes de su vela de confirmacion');

my $at_confirmation = Market::Indicators::PivotMissedReversal->compute(
    candles           => $regular_candles,
    max_visible_index => 4,
    timeframe         => '1m',
    length            => 2,
);
is(scalar @{ $at_confirmation->{regularPivots} }, 1,
    'el pivot aparece exactamente al llegar la confirmacion');

my @missed_pairs = (
    [59,51], [54,48], [49,45], [50,49], [57,53], [57,54],
    [62,55], [66,54], [61,55], [65,60], [64,57], [63,57],
    [66,60], [62,56], [62,55], [58,52], [61,55], [61,58],
    [58,53], [61,54], [63,56], [62,58], [58,54], [58,53],
    [58,54], [60,52], [57,46], [50,49], [55,46], [52,45],
    [54,46],
);
my @missed_candles = map { c($_, @{ $missed_pairs[$_] }) } 0 .. $#missed_pairs;

my $missed = Market::Indicators::PivotMissedReversal->compute(
    candles           => \@missed_candles,
    max_visible_index => $#missed_candles,
    timeframe         => '1m',
    length            => 2,
    show_regular      => 1,
    show_missed       => 1,
);

my @missed_high = grep { ($_->{type} // '') eq 'high' } @{ $missed->{missedPivots} };
my @missed_low  = grep { ($_->{type} // '') eq 'low'  } @{ $missed->{missedPivots} };
ok(@missed_high >= 1, 'detecta Missed Pivot High usando estado Pine');
ok(@missed_low  >= 1, 'detecta Missed Pivot Low usando estado Pine');
is($missed_high[0]{label}, '👻', 'Missed Pivot High usa marca fantasma');
is($missed_low[0]{label},  '👻', 'Missed Pivot Low usa marca fantasma');
is($missed_high[1]{index}, 7, 'Missed High conserva indice del extremo omitido');
is($missed_low[0]{index}, 25, 'Missed Low conserva indice del extremo omitido');

ok(scalar(grep { ($_->{line_style} // '') eq 'solid' } @{ $missed->{segments} }) >= 1,
    'genera segmentos solidos para movimientos regulares');
ok(scalar(grep { ($_->{line_style} // '') eq 'dashed' } @{ $missed->{segments} }) >= 1,
    'genera segmentos discontinuos para missed/reversion omitida');

is(scalar @{ $missed->{ghostLevels} }, 4, 'crea niveles ghost tras missed pivots');
is($missed->{ghostLevels}[-1]{active}, 1, 'mantiene un unico ghost level activo');
is($missed->{ghostLevels}[-1]{endIndex}, $#missed_candles, 'ghost level activo se extiende hasta la ultima vela');
ok(!scalar(grep { $_->{active} && $_ ne $missed->{ghostLevels}[-1] } @{ $missed->{ghostLevels} }),
    'no acumula multiples ghost levels activos');

ok($missed->{provisionalPivot}, 'genera pivote fantasma provisional');
is($missed->{provisionalPivot}{type}, 'low', 'provisional busca minimo si el ultimo estado es High');
is($missed->{provisionalPivot}{segment}{line_style}, 'dashed', 'provisional usa linea discontinua');
is($missed->{provisionalPivot}{ghostLevel}{endIndex}, $#missed_candles,
    'nivel horizontal provisional llega a la ultima vela');

my @extended = (@missed_candles, c(31, 53, 44));
my $extended = Market::Indicators::PivotMissedReversal->compute(
    candles           => \@extended,
    max_visible_index => $#extended,
    timeframe         => '1m',
    length            => 2,
);
is(ref($extended->{provisionalPivot}), 'HASH', 'la actualizacion conserva una sola estructura provisional');
is($extended->{provisionalPivot}{index}, 31, 'el provisional se recalcula y reemplaza al extremo anterior');

my $no_missed = Market::Indicators::PivotMissedReversal->compute(
    candles           => \@missed_candles,
    max_visible_index => $#missed_candles,
    timeframe         => '1m',
    length            => 2,
    show_regular      => 1,
    show_missed       => 0,
);
is(scalar @{ $no_missed->{missedPivots} }, 0, 'show_missed desactiva missed pivots');
is(scalar @{ $no_missed->{ghostLevels} }, 0, 'show_missed desactiva ghost levels historicos');

my $short = Market::Indicators::PivotMissedReversal->compute(
    candles           => [ @$regular_candles[0 .. 3] ],
    max_visible_index => 3,
    timeframe         => '5m',
    length            => 2,
);
is(scalar @{ $short->{regularPivots} }, 0, 'menos de 2*length+1 velas no confirma pivotes');
ok(!defined $short->{provisionalPivot}, 'sin pivot confirmado no genera provisional');

my $equal_highs = [ c(0, 10, 5), c(1, 12, 6), c(2, 12, 7), c(3, 11, 6) ];
my $eqh = Market::Indicators::PivotMissedReversal->compute(
    candles           => $equal_highs,
    max_visible_index => $#$equal_highs,
    timeframe         => '1m',
    length            => 1,
);
my @eqh_high = grep { $_->{type} eq 'high' } @{ $eqh->{regularPivots} };
is(scalar @eqh_high, 1, 'maximos iguales no duplican pivotes high');
is($eqh_high[0]{index}, 2, 'empate high usa el extremo derecho confirmado');

my $equal_lows = [ c(0, 10, 5), c(1, 11, 4), c(2, 10, 4), c(3, 12, 6) ];
my $eql = Market::Indicators::PivotMissedReversal->compute(
    candles           => $equal_lows,
    max_visible_index => $#$equal_lows,
    timeframe         => '1m',
    length            => 1,
);
my @eql_low = grep { $_->{type} eq 'low' } @{ $eql->{regularPivots} };
is(scalar @eql_low, 1, 'minimos iguales no duplican pivotes low');
is($eql_low[0]{index}, 2, 'empate low usa el extremo derecho confirmado');

my $detector = Market::Indicators::PivotMissedReversal->new(length => 2);
$detector->compute(candles => \@missed_candles, max_visible_index => $#missed_candles, timeframe => '1m');
my $isolated_candles = [ @$regular_candles[0 .. 3] ];
my $isolated = $detector->compute(candles => $isolated_candles, max_visible_index => $#$isolated_candles, timeframe => '15m');
is(scalar @{ $isolated->{regularPivots} }, 0, 'compute sobre instancia resetea estado entre ejecuciones/timeframes');

my $shapes = Market::Overlays::PivotMissedReversal->build_shapes(
    pivot_missed_reversal => $missed,
    timeframe             => '1m',
);
ok(scalar(grep { ($_->{source_type} // '') eq 'pivot_missed_reversal' } @$shapes) == scalar(@$shapes),
    'overlay usa source_type dedicado');
ok(scalar(grep { ($_->{kind} // '') eq 'label' && ($_->{text} // '') eq '▼' } @$shapes),
    'overlay dibuja labels de Pivot High regular');
ok(scalar(grep { ($_->{kind} // '') eq 'label' && ($_->{text} // '') eq '▲' } @$shapes),
    'overlay dibuja labels de Pivot Low regular');
ok(scalar(grep { ($_->{kind} // '') eq 'label' && ($_->{text} // '') eq '👻' } @$shapes),
    'overlay dibuja labels de Missed Pivot');

for my $sh (@$shapes) {
    for my $field (qw(x1_index x2_index y1_price y2_price)) {
        next unless exists $sh->{$field};
        ok(defined $sh->{$field}, "shape $sh->{id} tiene $field definido");
        ok($sh->{$field} == $sh->{$field}, "shape $sh->{id} no tiene NaN en $field");
    }
}

done_testing();
