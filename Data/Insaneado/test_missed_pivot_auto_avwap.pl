#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;
use Scalar::Util qw(looks_like_number);
use Market::Indicators::Anchored_VWAP;
use Market::Overlays::Anchored_VWAP;

sub candle {
    my ($min, $open, $high, $low, $close, $volume) = @_;
    return {
        time   => sprintf('2026-01-01T09:%02d:00-05:00', $min),
        open   => $open,
        high   => $high,
        low    => $low,
        close  => $close,
        volume => $volume,
    };
}

my @candles = (
    candle(30, 10, 12,  9, 11, 100),
    candle(31, 11, 15, 10, 14, 200),
    candle(32, 14, 16, 13, 15, 300),
    candle(33, 15, 17, 12, 13, 400),
    candle(34, 13, 14,  8,  9, 500),
);

my $high_event = {
    id                => 'pivotMissedReversal_missed_high_1_2_0',
    kind              => 'missedPivot',
    status            => 'confirmed',
    confirmed         => 1,
    eventType         => 'missedPivotHigh',
    type              => 'high',
    pivotType         => 'high',
    index             => 1,
    pivotTime         => $candles[1]{time},
    confirmationIndex => 2,
    confirmationTime  => $candles[2]{time},
    price             => 15,
};

my $low_event = {
    id                => 'pivotMissedReversal_missed_low_3_4_1',
    kind              => 'missedPivot',
    status            => 'confirmed',
    confirmed         => 1,
    eventType         => 'missedPivotLow',
    type              => 'low',
    pivotType         => 'low',
    index             => 3,
    pivotTime         => $candles[3]{time},
    confirmationIndex => 4,
    confirmationTime  => $candles[4]{time},
    price             => 12,
};

my $provisional = {
    id        => 'pivotMissedReversal_provisional_low_4_4',
    kind      => 'provisionalPivot',
    status    => 'temporary',
    confirmed => 0,
    type      => 'low',
    index     => 4,
    pivotTime => $candles[4]{time},
    price     => 8,
};

my $before = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 1,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event ],
);
is($before->{visible}, 0, 'no aparece antes de confirmationIndex');
is(scalar @{ $before->{instances} }, 0, 'no crea instancia antes de confirmar');

my $one = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 2,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event ],
);
is($one->{visible}, 1, 'missedPivotHigh confirmado crea Anchored VWAP');
is(scalar @{ $one->{instances} }, 1, 'crea una instancia automatica');
is($one->{instances}[0]{source}, 'missedPivotAuto', 'marca source automatico');
is($one->{instances}[0]{pivotType}, 'high', 'conserva tipo high');
is($one->{instances}[0]{anchorIndex}, 1, 'ancla en pivot index');
is($one->{instances}[0]{anchorTime}, $candles[1]{time}, 'ancla en pivotTime, no confirmationTime');
is($one->{instances}[0]{confirmationIndex}, 2, 'conserva confirmationIndex');

my $first_point = $one->{segments}[0]{points}[0];
is($first_point->{index}, 1, 'la serie comienza en la vela del ghost');
my $expected_hlc3 = ($candles[1]{high} + $candles[1]{low} + $candles[1]{close}) / 3;
cmp_ok(abs($first_point->{value} - $expected_hlc3), '<', 1e-8, 'reutiliza HLC3 del AVWAP existente');

my $band_settings = {
    show   => 1,
    source => 'hlc3',
    color  => '#2962FF',
    bands  => [
        { show => 1, multiplier => 1 },
        { show => 1, multiplier => 2 },
        { show => 1, multiplier => 3 },
    ],
};
my $auto_with_bands = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => $band_settings,
    missed_pivot_events => [ $high_event ],
);
my $manual_same_anchor = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => 4,
    timeframe         => '1m',
    settings          => {
        %$band_settings,
        anchor_type        => 'manual',
        manual_anchor_time => $high_event->{pivotTime},
    },
);
my $auto_points = $auto_with_bands->{segments}[0]{points};
my $manual_points = $manual_same_anchor->{segments}[0]{points};
is(scalar(@$auto_points), scalar(@$manual_points), 'auto y manual generan la misma cantidad de puntos');
for my $i (0 .. $#$manual_points) {
    is($auto_points->[$i]{time}, $manual_points->[$i]{time}, "punto $i usa el mismo tiempo en auto y manual");
    for my $field (qw(value upper1 lower1 upper2 lower2 upper3 lower3)) {
        cmp_ok(abs($auto_points->[$i]{$field} - $manual_points->[$i]{$field}), '<', 1e-8,
            "auto $field coincide con manual en punto $i");
    }
}

my $band_shapes = Market::Overlays::Anchored_VWAP->build_shapes(
    anchored_vwap     => $auto_with_bands,
    max_visible_index => 4,
    timeframe         => '1m',
);
for my $role (qw(
    anchored_vwap
    anchored_vwap_band_1_upper anchored_vwap_band_1_lower
    anchored_vwap_band_2_upper anchored_vwap_band_2_lower
    anchored_vwap_band_3_upper anchored_vwap_band_3_lower
)) {
    ok(scalar(grep { ($_->{color_role} // '') eq $role } @$band_shapes) > 0, "renderer comun emite $role");
}
my %band_color = map { ($_->{color_role} // '') => ($_->{color} // '') } @$band_shapes;
is($band_color{anchored_vwap_band_1_upper}, '#43A047', 'banda 1 usa verde');
is($band_color{anchored_vwap_band_2_upper}, '#FDD835', 'banda 2 usa amarillo');
is($band_color{anchored_vwap_band_3_upper}, '#00B8D4', 'banda 3 usa turquesa');
is($band_shapes->[0]{x1_index}, 1, 'la primera shape central comienza en la vela ancla');
is(scalar(grep { ($_->{x1_index} // 0) < 1 || ($_->{x2_index} // 0) < 1 } @$band_shapes), 0,
    'no hay shapes antes de la vela ancla');

my $dup = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event, $high_event ],
);
is(scalar @{ $dup->{instances} }, 1, 'procesar el mismo missedPivotId no duplica');

my $two = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event, $low_event, $provisional ],
);
is(scalar @{ $two->{instances} }, 1, 'un nuevo ghost confirmado reemplaza el automatico anterior');
is($two->{instances}[0]{pivotType}, 'low', 'missedPivotLow confirmado crea el automatico activo');
is($two->{instances}[0]{sourceEventId}, $low_event->{id}, 'conserva solo el evento confirmado mas reciente');
is(scalar(grep { ($_->{sourceEventId} // '') eq ($provisional->{id} // '') } @{ $two->{instances} }), 0,
    'provisionalPivot no genera VWAP automatico');
is($two->{debug}{totalGhosts}, 2, 'debug cuenta solo ghosts confirmados validos');
is($two->{debug}{selectedGhostId}, $low_event->{id}, 'debug reporta el ghost confirmado mas reciente');
is($two->{debug}{selectedPivotTime}, $low_event->{pivotTime}, 'debug reporta pivotTime seleccionado');
is($two->{debug}{selectedConfirmationTime}, $low_event->{confirmationTime}, 'debug reporta confirmationTime seleccionado');
is($two->{debug}{anchorIndex}, 3, 'debug reporta indice de ancla por pivotTime');
is($two->{debug}{activeAutoAvwapCount}, 1, 'debug confirma un solo auto AVWAP activo');
is(scalar(grep { ($_->{source_id} // '') ne $low_event->{id} } @{ $two->{segments} }), 0,
    'todos los segmentos automaticos pertenecen al ultimo ghost');

my %ids = map { $_->{id} => 1 } @{ $two->{instances} };
is(scalar(keys %ids), 1, 'solo existe un id automatico activo por symbol/timeframe');
like($two->{instances}[0]{id}, qr/^auto-avwap:BTCUSDT:1m:/, 'id incluye symbol y timeframe');

my $out_of_order = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $low_event, $high_event ],
);
is($out_of_order->{instances}[0]{sourceEventId}, $low_event->{id},
    'selecciona por confirmationTime aunque el array llegue desordenado');

my $late_by_time = {
    %$low_event,
    id                => 'late-by-confirmation-time',
    confirmationIndex => 2,
    confirmationTime  => $candles[4]{time},
};
my $late_by_index = {
    %$high_event,
    id                => 'late-by-confirmation-index',
    confirmationIndex => 4,
    confirmationTime  => $candles[2]{time},
};
my $time_priority = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $late_by_index, $late_by_time ],
);
is($time_priority->{instances}[0]{sourceEventId}, $late_by_time->{id},
    'confirmationTime manda sobre confirmationIndex para elegir el ultimo ghost');

my $tie_older_pivot = {
    %$high_event,
    id                => 'same-confirmation-older-pivot',
    confirmationIndex => 4,
    confirmationTime  => $candles[4]{time},
};
my $tie_break = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $low_event, $tie_older_pivot ],
);
is($tie_break->{instances}[0]{sourceEventId}, $low_event->{id},
    'si confirmationTime empata, gana el pivotTime mas reciente');

my $wrong_index = {
    %$low_event,
    id    => 'pivot-time-beats-wrong-index',
    index => 0,
};
my $time_anchor = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $wrong_index ],
);
is($time_anchor->{instances}[0]{anchorIndex}, 3,
    'la vela ancla se localiza por pivotTime aunque index venga incorrecto');
is($time_anchor->{segments}[0]{points}[0]{time}, $candles[3]{time},
    'el primer punto renderizable comienza exactamente en pivotTime');

my $missing_pivot_time = {
    %$low_event,
    id => 'missing-pivot-time',
    time => $low_event->{pivotTime},
};
delete $missing_pivot_time->{pivotTime};
delete $missing_pivot_time->{pivot_time};
my $missing_pivot_time_result = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $missing_pivot_time ],
);
is($missing_pivot_time_result->{visible}, 0, 'ignora missedPivot sin pivotTime aunque exista time');

my $missing_confirmation_time = {
    %$low_event,
    id => 'missing-confirmation-time',
};
delete $missing_confirmation_time->{confirmationTime};
my $missing_time_result = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $missing_confirmation_time ],
);
is($missing_time_result->{visible}, 0, 'ignora missedPivot sin confirmationTime');

my $future_confirmation_time = {
    %$high_event,
    id                => 'future-confirmation-time',
    confirmationIndex => 1,
    confirmationTime  => $candles[4]{time},
};
my $replay_guard = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 2,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $future_confirmation_time ],
);
is($replay_guard->{visible}, 0, 'replay no usa un ghost con confirmationTime futuro');

my $wrong_context = {
    %$low_event,
    id        => 'wrong-symbol-context',
    symbol    => 'ETHUSDT',
    timeframe => '1m',
};
my $context_filter = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $wrong_context ],
);
is($context_filter->{visible}, 0, 'no cruza automaticos entre simbolos si el evento trae symbol');

my $limited = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    max_instances       => 20,
    missed_pivot_events => [ $high_event, $low_event ],
);
is(scalar @{ $limited->{instances} }, 1, 'ignora acumulacion historica aunque se solicite un limite mayor');
is($limited->{instances}[0]{sourceEventId}, $low_event->{id}, 'conserva siempre la mas reciente confirmada');

my $manual = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => 4,
    timeframe         => '1m',
    settings          => {
        show               => 1,
        anchor_type        => 'manual',
        manual_anchor_time => $candles[2]{time},
        source             => 'hlc3',
    },
);
is(scalar @{ $manual->{segments} }, 1, 'manual sigue funcionando');
is($manual->{segments}[0]{anchor_index}, 2, 'manual conserva su ancla');

my $off = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 0, source => 'hlc3' },
    missed_pivot_events => [ $high_event, $low_event ],
);
is($off->{visible}, 0, 'desactivar AVWAP oculta automaticos sin tocar manuales');

my $hidden_daily = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => 'D',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, hide_on_1d_or_above => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event ],
);
is($hidden_daily->{visible}, 0, 'hide 1D o superior tambien oculta automaticos');
like($hidden_daily->{warning}, qr/1D/, 'mantiene warning de ocultamiento diario');

my $symbol_a = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event ],
);
my $symbol_b = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@candles,
    max_visible_index   => 4,
    timeframe           => '5m',
    symbol              => 'ETHUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $high_event ],
);
isnt($symbol_a->{instances}[0]{id}, $symbol_b->{instances}[0]{id}, 'symbol/timeframe aislan ids automaticos');

my @zero_anchor = (
    { %{ $candles[0] }, volume => 0 },
    { %{ $candles[1] }, volume => 200 },
    { %{ $candles[2] }, volume => 300 },
);
my $zero_event = {
    %$high_event,
    id                => 'zero-volume-anchor',
    index             => 0,
    pivotTime         => $zero_anchor[0]{time},
    confirmationIndex => 1,
    confirmationTime  => $zero_anchor[1]{time},
    price             => 12,
};
my $zero = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles             => \@zero_anchor,
    max_visible_index   => 2,
    timeframe           => '1m',
    symbol              => 'BTCUSDT',
    settings            => { show => 1, source => 'hlc3' },
    missed_pivot_events => [ $zero_event ],
);
is($zero->{segments}[0]{points}[0]{index}, 1, 'vela ancla sin volumen se salta igual que el AVWAP actual');

for my $seg (@{ $two->{segments} }) {
    for my $pt (@{ $seg->{points} }) {
        ok(looks_like_number($pt->{value}), 'sin valores NaN/undefined en value');
        ok(!defined($pt->{stdev}) || looks_like_number($pt->{stdev}), 'sin valores NaN/undefined en stdev');
    }
}

my $shapes = Market::Overlays::Anchored_VWAP->build_shapes(
    anchored_vwap     => $two,
    max_visible_index => 4,
    timeframe         => '1m',
);
ok(@$shapes > 0, 'overlay genera shapes para automaticos');
is(scalar(grep { ($_->{source} // '') eq 'missedPivotAuto' } @$shapes), scalar(@$shapes),
    'shapes automaticos conservan source missedPivotAuto');
is(scalar(grep { ($_->{sourceEventId} // '') ne $low_event->{id} } @$shapes), 0,
    'shapes automaticos visibles corresponden solo al ultimo ghost');
like($shapes->[0]{tooltip} // '', qr/Origen: Missed Pivot/, 'tooltip expone origen missed pivot');

done_testing;
