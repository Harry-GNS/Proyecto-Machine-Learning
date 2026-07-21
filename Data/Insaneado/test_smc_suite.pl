#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::Liquidity;
use Market::Indicators::SMC_Structures;
use Market::Indicators::Strategy_Builder;
use Market::Overlays::SMC_Structures;
use Market::SMCConfig;

sub c {
    my ($i, $o, $h, $l, $cl, $v) = @_;
    return {
        time   => sprintf('2026-06-29T00:%02d:00', $i),
        open   => $o,
        high   => $h,
        low    => $l,
        close  => $cl,
        volume => $v // 1000,
    };
}

sub atr {
    my ($candles, $v) = @_;
    return [ map { $v // 1 } @$candles ];
}

my $structure_candles = [
    c(0,  9.5, 10,  9,  9.5, 1000),
    c(1, 10.5, 11, 10, 10.5, 1000),
    c(2, 11.5, 12, 11, 11.5, 1000),
    c(3, 14.0, 15, 12, 14.0, 1000),
    c(4, 11.0, 12, 10, 10.8, 1000),
    c(5, 10.0, 11,  9,  9.5, 1000),
    c(6,  9.0, 10,  8,  8.5, 1000),
    c(7, 14.0, 16, 13, 16.0, 4000),
    c(8, 13.0, 14, 12, 12.8, 1000),
    c(9, 12.0, 13, 11, 11.8, 1000),
    c(10, 9.0,  9.5, 6.5, 6.6, 4000),
    c(11, 8.0,  9,  7,  8.5, 1000),
];

my $smc = Market::Indicators::SMC_Structures->compute(
    candles           => $structure_candles,
    atr_series        => atr($structure_candles, 1),
    max_visible_index => $#$structure_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => {
        %{ Market::SMCConfig->defaults },
        externalStructureSensitivity => 3,
        internalStructureSensitivity => 1,
    },
);

ok(scalar(grep { $_->{kind} eq 'high' && defined $_->{label} && $_->{label} eq 'HH' && defined $_->{confirmed_time} } @{ $smc->{pivots} }), 'detecta swing high confirmado');
ok(scalar(grep { $_->{kind} eq 'low'  && defined $_->{label} && $_->{label} eq 'HL' && defined $_->{confirmed_time} } @{ $smc->{pivots} }), 'detecta swing low confirmado estilo Mxwll');
ok(scalar(grep { $_->{type} eq 'BOS' && $_->{direction} eq 'bearish' && ($_->{scope}//'') eq 'external' && defined $_->{confirmation_time} } @{ $smc->{structures} }), 'detecta BOS externo confirmado por cierre');
ok(scalar(grep { $_->{type} eq 'CHOCH' && ($_->{scope}//'') eq 'internal' && ($_->{display_type}//'') eq 'I-CHoCH' } @{ $smc->{structures} }), 'detecta I-CHoCH interno');
ok(scalar(grep { $_->{type} eq 'MSS' && ($_->{scope}//'') eq 'internal' } @{ $smc->{structures} }), 'deriva MSS desde CHoCH interno confirmado');
ok(@{ $smc->{premium_discount_zones} } >= 1, 'genera Premium/Discount desde rango estructural');
ok($smc->{trailing_extremes}
   && ($smc->{trailing_extremes}{high_classification} // '') =~ /^(?:strong|weak)_high$/
   && ($smc->{trailing_extremes}{low_classification} // '') =~ /^(?:strong|weak)_low$/,
   'mantiene un unico par trailing Strong/Weak vigente');
ok((Market::SMCConfig->defaults->{maxEventsPerRequest} // 0) > 0, 'config central expone maxEventsPerRequest');

my $atr_filter_candles = [
    c(0, 10.0, 10.0,  9.0,  9.5),
    c(1, 11.0, 12.0, 10.0, 11.5),
    c(2, 10.0, 11.0,  9.5, 10.5),
    c(3, 11.0, 12.4, 10.0, 11.8),
    c(4, 10.0, 11.9,  9.5, 10.8),
    c(5, 12.0, 13.8, 11.0, 13.0),
    c(6, 11.0, 12.5, 10.5, 12.0),
];
my $mxwll_fast_config = {
    %{ Market::SMCConfig->defaults },
    externalStructureSensitivity => 1,
    internalStructureSensitivity => 1,
};
my $mxwll_fast_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $atr_filter_candles,
    atr_series        => atr($atr_filter_candles, 1),
    max_visible_index => $#$atr_filter_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => $mxwll_fast_config,
);
my %high_pivot_by_index = map { $_->{index} => $_ }
    grep { ($_->{kind} // '') eq 'high' && ($_->{scope}//'') eq 'external' } @{ $mxwll_fast_smc->{pivots} };
is($high_pivot_by_index{3}{label}, 'HH', 'Mxwll etiqueta high estructural externo');
is($high_pivot_by_index{5}{label}, 'HH', 'Mxwll etiqueta siguiente HH al cambiar de low a high');
ok(scalar(grep { $_->{type} eq 'BOS' && $_->{direction} eq 'bullish' && ($_->{display_type}//'') eq 'BOS' && ($_->{pivot_index}//-1) == 3 && ($_->{break_index}//-1) == 5 } @{ $mxwll_fast_smc->{structures} }), 'BOS usa pivot roto y vela de ruptura correctos');
is(scalar @{ $mxwll_fast_smc->{fib_sets} }, 1, 'Auto Fib mantiene un unico set activo estilo Mxwll');
is($mxwll_fast_smc->{fib_sets}[0]{anchor_start_index}, 4, 'Fib ancla inicio en HL/base del tramo');
is($mxwll_fast_smc->{fib_sets}[0]{anchor_end_index}, 5, 'Fib ancla fin en HH del tramo');
is($mxwll_fast_smc->{fib_sets}[0]{direction}, 'bullish', 'Fib conserva direccion del tramo HL -> HH');

my $mxwll_shapes = Market::Overlays::SMC_Structures->build_shapes(
    pivots            => $mxwll_fast_smc->{pivots},
    structures        => $mxwll_fast_smc->{structures},
    trailing_extremes => $mxwll_fast_smc->{trailing_extremes},
    fvgs              => $mxwll_fast_smc->{fvgs},
    fib_sets          => $mxwll_fast_smc->{fib_sets},
    premium_discount_zones => $mxwll_fast_smc->{premium_discount_zones},
    max_visible_index => $#$atr_filter_candles,
    timeframe         => '1m',
);
ok(scalar(grep { ($_->{source_type}//'') eq 'fib' && ($_->{kind}//'') eq 'line' && ($_->{color_role}//'') eq 'fib_anchor_bullish' && ($_->{line_style}//'') eq 'dashed' && $_->{x1_index} != $_->{x2_index} && $_->{y1_price} != $_->{y2_price} } @$mxwll_shapes), 'overlay dibuja diagonal verde entrecortada no horizontal');
ok(scalar(grep { ($_->{source_type}//'') eq 'fib' && ($_->{kind}//'') eq 'fib_line' && ($_->{x1_index}//-1) == $mxwll_fast_smc->{fib_sets}[0]{anchor_end_index} } @$mxwll_shapes), 'niveles Fib arrancan desde el mismo anclaje final de la diagonal');

my $same_leg_relabel_candles = [
    c(0,  4.5,  5.0, 4.0,  4.8),
    c(1,  9.5, 10.0, 5.0,  9.7),
    c(2,  6.5,  7.0, 3.0,  4.0),
    c(3,  8.0,  8.5, 5.0,  8.1),
    c(4,  6.5,  7.0, 6.0,  6.8),
    c(5, 10.5, 11.0, 7.0, 10.8),
    c(6,  7.5,  8.0, 6.0,  7.0),
];
my $same_leg_config = {
    %{ Market::SMCConfig->defaults },
    externalStructureSensitivity => 1,
    internalStructureSensitivity => 1,
};
my $same_leg_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $same_leg_relabel_candles,
    atr_series        => atr($same_leg_relabel_candles, 1),
    max_visible_index => $#$same_leg_relabel_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => $same_leg_config,
);
my %same_leg_high_by_index = map { $_->{index} => $_ }
    grep { ($_->{kind} // '') eq 'high' && ($_->{scope}//'') eq 'external' } @{ $same_leg_smc->{pivots} };
is($same_leg_high_by_index{3}{label}, 'HH', 'Mxwll conserva el primer HH confirmado del cambio de estado');
is($same_leg_high_by_index{5}{label}, 'HH', 'Mxwll marca el siguiente HH confirmado del nuevo tramo');

my $fvg_candles = [
    c(0, 10.0, 10.0,  9.0,  9.5),
    c(1, 10.2, 10.8, 10.0, 10.6),
    c(2, 11.2, 12.0, 11.0, 11.8),
    c(3, 11.8, 12.2, 11.4, 12.0),
    c(4, 12.0, 12.4, 11.5, 12.1),
    c(5, 10.9, 11.3, 10.5, 10.8),
];
my $fvg_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $fvg_candles,
    atr_series        => atr($fvg_candles, 1),
    max_visible_index => $#$fvg_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
ok(scalar(grep { $_->{direction} eq 'bullish' && $_->{status} eq 'active' } @{ $fvg_smc->{fvgs} }), 'FVG bullish sigue pendiente ante llenado parcial');
ok(scalar(grep { $_->{direction} eq 'bullish' && ($_->{classification}//'') eq 'internal' && ($_->{start_index}//-1) == 1 && ($_->{end_index}//-1) == 2 && ($_->{gap_low}//0) == 10 && ($_->{gap_high}//0) == 11 } @{ $fvg_smc->{fvgs} }),
   'FVG bullish usa limites Pine y origen visual en la vela media');

my $fvg_filled_candles = [
    c(0, 10.0, 10.0,  9.0,  9.5),
    c(1, 10.2, 10.8, 10.0, 10.6),
    c(2, 11.2, 12.0, 11.0, 11.8),
    c(3, 11.8, 12.2, 11.4, 12.0),
    c(4, 12.0, 12.4, 11.5, 12.1),
    c(5, 10.9, 11.3,  9.8, 10.2),
];
my $fvg_filled_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $fvg_filled_candles,
    atr_series        => atr($fvg_filled_candles, 1),
    max_visible_index => $#$fvg_filled_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
ok(!scalar(grep { $_->{direction} eq 'bullish' } @{ $fvg_filled_smc->{fvgs} }), 'FVG bullish mitigado se elimina del estado final');

my $bear_fvg_candles = [
    c(0, 10.5, 11.0, 10.0, 10.7),
    c(1, 10.0, 10.4,  9.6,  9.8),
    c(2,  8.8,  9.0,  8.0,  8.4),
    c(3,  8.6,  9.5,  8.2,  8.7),
];
my $bear_fvg_partial = Market::Indicators::SMC_Structures->compute(
    candles           => $bear_fvg_candles,
    atr_series        => atr($bear_fvg_candles, 1),
    max_visible_index => $#$bear_fvg_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
ok(scalar(grep { $_->{direction} eq 'bearish' && $_->{status} eq 'active' } @{ $bear_fvg_partial->{fvgs} }), 'FVG bearish sigue pendiente ante llenado parcial');
push @$bear_fvg_candles, c(4, 8.8, 10.2, 8.4, 9.8);
my $bear_fvg_filled = Market::Indicators::SMC_Structures->compute(
    candles           => $bear_fvg_candles,
    atr_series        => atr($bear_fvg_candles, 1),
    max_visible_index => $#$bear_fvg_candles,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
ok(!scalar(grep { $_->{direction} eq 'bearish' } @{ $bear_fvg_filled->{fvgs} }), 'FVG bearish mitigado se elimina del estado final');

my $thin_bull_fvg = [
    c(0, 10.0, 10.00,  9.0,  9.5),
    c(1, 10.0, 10.40,  9.8, 10.2),
    c(2, 10.1, 10.60, 10.03, 10.4),
];
my $thin_bull_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $thin_bull_fvg,
    atr_series        => atr($thin_bull_fvg, 1),
    max_visible_index => $#$thin_bull_fvg,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
is(scalar @{ $thin_bull_smc->{fvgs} }, 1,
   'FVG bullish delgado se conserva cuando cumple la definicion Pine');

my $thin_bear_fvg = [
    c(0, 10.4, 11.0, 10.00, 10.7),
    c(1, 10.2, 10.5,  9.8,  9.95),
    c(2,  9.6,  9.97, 9.2,  9.5),
];
my $thin_bear_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $thin_bear_fvg,
    atr_series        => atr($thin_bear_fvg, 1),
    max_visible_index => $#$thin_bear_fvg,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 0 },
);
is(scalar @{ $thin_bear_smc->{fvgs} }, 1,
   'FVG bearish delgado se conserva cuando cumple la definicion Pine');

my $pine_threshold_smc = Market::Indicators::SMC_Structures->compute(
    candles           => $thin_bull_fvg,
    atr_series        => atr($thin_bull_fvg, 1),
    max_visible_index => $#$thin_bull_fvg,
    timeframe         => '1m',
    liquidity_events  => [],
    config            => { fairValueGapsAutoThreshold => 1 },
);
is(scalar @{ $pine_threshold_smc->{fvgs} }, 0,
   'filtro Auto Threshold del Pine descarta desplazamientos no significativos');

my $pending_fvg_shapes = Market::Overlays::SMC_Structures->build_shapes(
    pivots      => [],
    structures => [],
    fvgs        => [
        { id => 'FVG_BULL_ACTIVE', direction => 'bullish', start_index => 1, end_index => 3,
          gap_low => 10, gap_high => 11, status => 'active', opacity => 0.40, classification => 'internal' },
        { id => 'FVG_BEAR_ACTIVE', direction => 'bearish', start_index => 2, end_index => 4,
          gap_low => 20, gap_high => 21, status => 'active', opacity => 0.40, classification => 'external' },
        { id => 'FVG_USED', direction => 'bullish', start_index => 0, end_index => 2,
          gap_low => 8, gap_high => 9, status => 'mitigated', project_until_index => 5, opacity => 0.40 },
        { id => 'FVG_INVALID', direction => 'bearish', start_index => 0, end_index => 2,
          gap_low => 22, gap_high => 23, status => 'invalidated', project_until_index => 6, opacity => 0.40 },
    ],
    fib_sets          => [],
    premium_discount_zones => [],
    max_visible_index => 10,
    timeframe         => '1m',
);
my @visible_fvgs = grep { ($_->{source_type} // '') eq 'fvg' } @$pending_fvg_shapes;
is(scalar @visible_fvgs, 2, 'overlay FVG muestra exclusivamente gaps pendientes');
is_deeply(
    [ sort map { $_->{source_id} } @visible_fvgs ],
    [qw(FVG_BEAR_ACTIVE FVG_BULL_ACTIVE)],
    'FVG mitigados e invalidados no se envian al renderizador',
);
ok(!scalar(grep { ($_->{x2_index} // -1) != 10 } @visible_fvgs),
   'todos los FVG pendientes se extienden hasta la vela actual');
is_deeply(
    { map { $_->{source_id} => $_->{color_role} } @visible_fvgs },
    { FVG_BULL_ACTIVE => 'fvg_internal', FVG_BEAR_ACTIVE => 'fvg_external' },
    'overlay colorea FVG por clasificacion internal/external',
);
ok(!scalar(grep { defined $_->{text} && length $_->{text} } @visible_fvgs),
   'overlay FVG no envia etiquetas dentro de las cajas');

my $liq_candles = [
    c(0, 10, 10,   9,  9.5),
    c(1, 11, 11,  10, 10.5),
    c(2, 12, 12,  11, 11.5),
    c(3, 14, 15,  12, 14.5),
    c(4, 12, 12,  10, 10.8),
    c(5, 11, 11,   9,  9.8),
    c(6, 10, 10,   8,  9.0),
    c(7, 12, 14.8,10, 12.5),
    c(8, 14, 15.4,13, 14.8),
    c(9, 14, 14.5,12, 14.0),
    c(10,13, 13.5,11, 12.5),
    c(11,12, 12.5,10, 11.5),
    c(12,11, 16.0, 9, 15.0),
];
my $liq = Market::Indicators::Liquidity->compute(
    candles           => $liq_candles,
    atr_series        => atr($liq_candles, 10),
    equal_atr_series  => atr($liq_candles, 10),
    max_visible_index => $#$liq_candles,
    timeframe         => '1m',
);
ok(scalar(grep { $_->{type} eq 'BSL' } @{ $liq->{levels} }), 'detecta BSL');
ok(scalar(grep { $_->{type} eq 'EQH' } @{ $liq->{levels} }), 'detecta EQH');
ok(scalar(grep { ($_->{classification} // '') =~ /GRAB|SWEEP|RUN/ } @{ $liq->{events} }), 'emite evento de sweep/grab/run');

my $strategy = Market::Indicators::Strategy_Builder->compute(
    candles           => $structure_candles,
    atr_series        => atr($structure_candles, 1),
    liquidity_levels  => [],
    liquidity_events  => [],
    structure_events  => $smc->{structures},
    pivots            => $smc->{pivots},
    max_visible_index => $#$structure_candles,
    timeframe         => '1m',
);
ok(scalar(grep { $_->{validation} && $_->{validation}{structure_event_id} } @{ $strategy->{order_blocks} }), 'Order Block exige validacion estructural');
ok(scalar(grep { ($_->{derived_from} // '') =~ /order_block|displacement|liquidity_reaction/ } @{ $strategy->{supply_zones} }), 'Supply zones conservan origen derivado');
ok(scalar(grep { ($_->{derived_from} // '') =~ /order_block|displacement|liquidity_reaction/ } @{ $strategy->{demand_zones} }), 'Demand zones conservan origen derivado');

done_testing();
