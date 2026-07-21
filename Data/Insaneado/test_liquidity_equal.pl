#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::Liquidity;
use Market::Overlays::Liquidity;

sub time_at {
    my ($i) = @_;
    return sprintf('2026-06-29T%02d:%02d:00', int($i / 60), $i % 60);
}

sub candle {
    my ($i, %overrides) = @_;
    return {
        time   => time_at($i),
        open   => 99.20,
        high   => 99.60,
        low    => 98.80,
        close  => 99.20,
        volume => 100,
        %overrides,
    };
}

sub point {
    my ($kind, $idx, $price, $candles, $confirmed_at) = @_;
    $confirmed_at //= $idx + 3;
    return {
        kind           => $kind,
        index          => $idx,
        price          => $price,
        time           => $candles->[$idx]{time},
        confirmed_at   => $confirmed_at,
        confirmed_time => $candles->[$confirmed_at]{time},
        scope          => 'external',
    };
}

sub candles_with_points {
    my ($count, $points, $overrides) = @_;
    my @candles = map { candle($_) } 0 .. ($count - 1);
    for my $p (@$points) {
        if ($p->{kind} eq 'high') {
            $candles[$p->{index}]{high} = $p->{price};
        }
        else {
            $candles[$p->{index}]{low} = $p->{price};
        }
    }
    for my $idx (keys %{ $overrides // {} }) {
        $candles[$idx] = { %{ $candles[$idx] }, %{ $overrides->{$idx} } };
    }
    return \@candles;
}

sub equal_leg_seed {
    my ($type, $pairs) = @_;
    my $kind = $type eq 'EQH' ? 'high' : 'low';
    my @seed = map { +{ kind => $kind, index => $_->[0], price => $_->[1] } } @$pairs;
    return @seed unless @$pairs >= 2;

    if ($type eq 'EQH') {
        my $first_idx = $pairs->[0][0];
        push @seed, { kind => 'low', index => $first_idx > 1 ? $first_idx - 2 : 0, price => 97.90 };
        for my $i (1 .. $#$pairs) {
            my $mid = int(($pairs->[$i - 1][0] + $pairs->[$i][0]) / 2);
            push @seed, { kind => 'low', index => $mid, price => 98.00 + $i * 0.01 };
        }
    }
    else {
        for my $i (1 .. $#$pairs) {
            my $mid = int(($pairs->[$i - 1][0] + $pairs->[$i][0]) / 2);
            push @seed, { kind => 'high', index => $mid, price => 100.80 + $i * 0.01 };
        }
    }

    return @seed;
}

sub augment_equal_leg_seed {
    my ($pivot_specs) = @_;
    my @seed = map { +{ kind => $_->{kind}, index => $_->{index}, price => $_->{price} } } @$pivot_specs;
    for my $kind (qw(high low)) {
        my @same = sort { $a->{index} <=> $b->{index} }
            grep { ($_->{kind} // '') eq $kind && defined $_->{index} && defined $_->{price} } @$pivot_specs;
        my %seen_idx;
        @same = grep { !$seen_idx{ $_->{index} }++ } @same;
        next unless @same >= 2;
        push @seed, equal_leg_seed(
            $kind eq 'high' ? 'EQH' : 'EQL',
            [ map { [ $_->{index}, $_->{price} ] } @same ],
        );
    }
    return @seed;
}

sub liquidity_context {
    my ($candles) = @_;
    my $liq = Market::Indicators::Liquidity->new;
    $liq->{_vol_avg} = [ map { 100 } @$candles ];
    $liq->{_candles} = $candles;
    $liq->{_timeframe} = '1m';
    $liq->{_equal_level_threshold} = 0.10;
    $liq->{_minimum_tick} = 0.01;
    $liq->{_minimum_tick_distance} = 1;
    $liq->{_minimum_bars_between_pivots} = 4;
    $liq->{_sweep_buffer_atr_factor} = 0.02;
    return $liq;
}

sub direct_equal_levels {
    my ($type, $prices) = @_;
    my @seed = map {
        +{ kind => $type eq 'EQH' ? 'high' : 'low', index => $_->[0], price => $_->[1] }
    } @$prices;
    my $candles = candles_with_points(24, \@seed, {});
    my $atr = [ map { 1 } @$candles ];
    my $liq = liquidity_context($candles);
    my $points = [
        map { point($type eq 'EQH' ? 'high' : 'low', $_->[0], $_->[1], $candles) } @$prices
    ];
    Market::Indicators::Liquidity::_create_equal_levels(
        $liq, $points, $type, $candles, $atr, '1m', [],
    );
    return grep { ($_->{type} // '') eq $type } @{ $liq->{levels} };
}

my @eqh_valid = direct_equal_levels('EQH', [[3, 100.00], [8, 100.06]]);
is(scalar @eqh_valid, 1, 'EQH valido entre highs dentro de tolerancia');
is($eqh_valid[0]{firstPivotPrice}, 100.00, 'EQH conserva precio real del primer high');
is($eqh_valid[0]{lastPivotPrice}, 100.06, 'EQH conserva precio real del segundo high');
cmp_ok($eqh_valid[0]{tolerance}, '==', 0.10, 'EQH usa tolerancia ATR * threshold');

my $eqh_shapes = Market::Overlays::Liquidity->build_shapes(
    levels => \@eqh_valid, events => [], max_visible_index => 20,
);
my ($eqh_line) = grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'eqh' } @$eqh_shapes;
is($eqh_line->{y1_price}, 100.00, 'linea EQH inicia en el high real');
is($eqh_line->{y2_price}, 100.06, 'linea EQH termina en el high real');
isnt($eqh_line->{y1_price}, $eqh_line->{y2_price}, 'linea EQH no se fuerza horizontal');

my @eqh_far = direct_equal_levels('EQH', [[3, 100.00], [8, 100.25]]);
is(scalar @eqh_far, 0, 'no genera EQH si los highs superan la tolerancia');

my @eql_valid = direct_equal_levels('EQL', [[3, 95.00], [8, 94.94]]);
is(scalar @eql_valid, 1, 'EQL valido entre lows dentro de tolerancia');
my $eql_shapes = Market::Overlays::Liquidity->build_shapes(
    levels => \@eql_valid, events => [], max_visible_index => 20,
);
my ($eql_line) = grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'eql' } @$eql_shapes;
is($eql_line->{y1_price}, 95.00, 'linea EQL inicia en el low real');
is($eql_line->{y2_price}, 94.94, 'linea EQL termina en el low real');

my @eql_far = direct_equal_levels('EQL', [[3, 95.00], [8, 94.70]]);
is(scalar @eql_far, 0, 'no genera EQL si los lows superan la tolerancia');

my @eqh_third = direct_equal_levels('EQH', [[3, 100.00], [8, 100.06], [13, 100.03]]);
is(scalar @eqh_third, 2, 'tercer toque genera pares EQH consecutivos como el Pine');
my @eqh_third_sorted = sort { ($a->{lastPivotIndex} // 0) <=> ($b->{lastPivotIndex} // 0) } @eqh_third;
is_deeply([ map { $_->{index} } @{ $eqh_third_sorted[0]{pivots} } ], [3, 8],
          'primer par EQH conserva los dos primeros pivotes');
is_deeply([ map { $_->{index} } @{ $eqh_third_sorted[1]{pivots} } ], [8, 13],
          'segundo par EQH usa el pivote previo guardado por el Pine');
my $third_shapes = Market::Overlays::Liquidity->build_shapes(
    levels => \@eqh_third, events => [], max_visible_index => 20,
);
is(scalar(grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'eqh' } @$third_shapes), 2,
   'tercer toque genera dos lineas EQH historicas, una por par consecutivo');
is(scalar(grep { ($_->{kind} // '') eq 'label' && ($_->{color_role} // '') eq 'eqh' } @$third_shapes), 2,
   'tercer toque genera dos etiquetas EQH historicas');
my ($third_line) = sort { ($b->{x2_index} // 0) <=> ($a->{x2_index} // 0) }
    grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'eqh' } @$third_shapes;
is($third_line->{x2_index}, 13, 'ultimo par EQH termina en el tercer pivote');
is($third_line->{y2_price}, 100.03, 'ultimo par conserva su precio real');
my ($third_label) = sort { ($b->{x1_index} // 0) <=> ($a->{x1_index} // 0) }
    grep { ($_->{kind} // '') eq 'label' && ($_->{color_role} // '') eq 'eqh' } @$third_shapes;
is($third_label->{x1_index}, 11, 'etiqueta EQH se centra entre los pivotes del par');
is($third_label->{y1_price}, 100.03, 'etiqueta EQH usa el precio del segundo pivote');

my @consecutive = direct_equal_levels('EQH', [[3, 100.00], [5, 100.01]]);
is(scalar @consecutive, 1, 'el Pine no aplica filtro de separacion minima entre pivotes EQH');

{
    my @seed = equal_leg_seed('EQH', [[3, 100.00], [8, 100.04]]);
    my $candles = candles_with_points(24, \@seed, {});
    my $atr = [ map { 1 } @$candles ];
    my $liq = Market::Indicators::Liquidity->compute(
        candles           => $candles,
        atr_series        => $atr,
        equal_atr_series  => $atr,
        max_visible_index => $#$candles,
        timeframe         => '1m',
        structure_pivots  => [
            { %{ point('high', 3, 100.00, $candles) }, scope => 'external' },
            { %{ point('high', 8, 100.04, $candles) }, scope => 'internal' },
        ],
        config            => {
            equalHighLowAtrTolerance => 0.10,
            minimumTick              => 0.01,
            minimumTickDistance      => 1,
            minimumBarsBetweenPivots => 4,
        },
    );
    my ($eqh) = grep { ($_->{type} // '') eq 'EQH' } @{ $liq->{levels} };
    ok($eqh, 'EQH usa la maquina leg(3) aunque los pivotes SMC tengan scopes distintos');
    is($eqh->{createdAt}, 11, 'EQH se confirma en la barra actual que detecta el pivote Pine');
}

{
    my @seed = equal_leg_seed('EQH', [[3, 100.00], [8, 100.06]]);
    my $candles = candles_with_points(24, \@seed, {});
    my $atr = [ map { 0.5 } @$candles ];
    my $liq = liquidity_context($candles);
    $liq->{_minimum_tick} = 1;
    my $points = [
        map { point('high', $_->{index}, $_->{price}, $candles) } @seed
    ];
    Market::Indicators::Liquidity::_create_equal_levels(
        $liq, $points, 'EQH', $candles, $atr, '1m', [],
    );
    is(scalar(grep { ($_->{type} // '') eq 'EQH' } @{ $liq->{levels} }), 0,
       'EQH usa ATR * threshold sin piso por tick');
}

{
    my @seed = (
        { kind => 'low', index => 3, price => 95.00 },
        { kind => 'low', index => 8, price => 94.99 },
    );
    my $candles = candles_with_points(24, \@seed, {});
    my $atr = [ map { undef } @$candles ];
    my $liq = liquidity_context($candles);
    my $points = [
        map { point('low', $_->{index}, $_->{price}, $candles) } @seed
    ];
    Market::Indicators::Liquidity::_create_equal_levels(
        $liq, $points, 'EQL', $candles, $atr, '1m', [],
    );
    is(scalar(grep { ($_->{type} // '') eq 'EQL' } @{ $liq->{levels} }), 0,
       'EQL no se genera con ATR incompleto');
}

{
    my @seed = equal_leg_seed('EQH', [[3, 100.00], [8, 100.06]]);
    my $candles = candles_with_points(24, \@seed, {});
    my $atr = [ map { 1 } @$candles ];
    my $late_structure_pivots = [
        point('high', 3, 100.00, $candles, 20),
        point('high', 8, 100.06, $candles, 21),
    ];
    my $liq = Market::Indicators::Liquidity->compute(
        candles           => $candles,
        atr_series        => $atr,
        equal_atr_series  => $atr,
        max_visible_index => 11,
        timeframe         => '1m',
        structure_pivots  => $late_structure_pivots,
        config            => {
            equalHighLowAtrTolerance   => 0.10,
            equalHighLowConfirmationBars => 3,
            minimumBarsBetweenPivots   => 4,
        },
    );
    my ($eqh) = grep { ($_->{type} // '') eq 'EQH' } @{ $liq->{levels} };
    ok($eqh, 'EQH no depende de pivotes estructurales externos de 50 barras');
    is($eqh->{createdAt}, 11, 'EQH aparece al confirmar el segundo swing de 3 barras');
}

sub compute_with_structure_pivots {
    my ($type, $pairs, $overrides, $max_idx) = @_;
    my @seed = equal_leg_seed($type, $pairs);
    my $candles = candles_with_points(24, \@seed, $overrides);
    my $atr = [ map { 1 } @$candles ];
    my $pivots = [
        map { point($type eq 'EQH' ? 'high' : 'low', $_->[0], $_->[1], $candles) } @$pairs
    ];
    return Market::Indicators::Liquidity->compute(
        candles           => $candles,
        atr_series        => $atr,
        equal_atr_series  => $atr,
        max_visible_index => $max_idx // $#$candles,
        timeframe         => '1m',
        structure_pivots  => $pivots,
        config            => {
            equalHighLowAtrTolerance => 0.10,
            minimumTick              => 0.01,
            minimumTickDistance      => 1,
            minimumBarsBetweenPivots => 4,
            sweepBufferAtrFactor     => 0.02,
        },
    );
}

sub compute_liquidity_with_pivots {
    my ($pivot_specs, $overrides, $max_idx, $extra) = @_;
    $extra //= {};
    my @seed = augment_equal_leg_seed($pivot_specs);
    my $candles = candles_with_points(24, \@seed, $overrides);
    my $atr = [ map { 1 } @$candles ];
    my $pivots = [
        map {
            my $p = point($_->{kind}, $_->{index}, $_->{price}, $candles, $_->{confirmed_at});
            $p->{id} = $_->{id} if defined $_->{id};
            $p->{scope} = $_->{scope} if defined $_->{scope};
            $p;
        } @$pivot_specs
    ];
    my $liq = Market::Indicators::Liquidity->compute(
        candles           => $candles,
        atr_series        => $atr,
        equal_atr_series  => $atr,
        max_visible_index => $max_idx // $#$candles,
        timeframe         => '1m',
        structure_pivots  => $pivots,
        config            => {
            equalHighLowAtrTolerance => 0.10,
            minimumTick              => 0.01,
            minimumTickDistance      => 1,
            minimumBarsBetweenPivots => 4,
            liquidityMarginFactor    => 0.02,
            minimumMarginTicks       => 2,
            sweepBufferAtrFactor     => 0.02,
            sweepBufferTicks         => 1,
            showInternalLiquidity    => 0,
            %{ $extra->{config} // {} },
        },
        structure_events  => $extra->{structure_events} // [],
    );
    return ($liq, $candles);
}

{
    my ($liq) = compute_liquidity_with_pivots([
        { id => 'SH_3', kind => 'high', index => 3, price => 100.00 },
    ]);
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    ok($bsl, 'BSL individual se crea desde Swing High confirmado');
    is($bsl->{basePrice}, 100.00, 'BSL usa el high real como basePrice');
    is($bsl->{zoneBottom}, 100.00, 'BSL deja el borde interno en el Swing High');
    cmp_ok($bsl->{zoneTop}, '>', 100.00, 'BSL extiende la zona solo por encima');
    is($bsl->{status}, 'ACTIVE', 'BSL individual inicia ACTIVE');
}

{
    my ($liq) = compute_liquidity_with_pivots([
        { id => 'SL_3', kind => 'low', index => 3, price => 95.00 },
    ]);
    my ($ssl) = grep { ($_->{type} // '') eq 'SSL' } @{ $liq->{levels} };
    ok($ssl, 'SSL individual se crea desde Swing Low confirmado');
    is($ssl->{basePrice}, 95.00, 'SSL usa el low real como basePrice');
    is($ssl->{zoneTop}, 95.00, 'SSL deja el borde interno en el Swing Low');
    cmp_ok($ssl->{zoneBottom}, '<', 95.00, 'SSL extiende la zona solo por debajo');
    is($ssl->{status}, 'ACTIVE', 'SSL individual inicia ACTIVE');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_CLOSE_DIFF', kind => 'high', index => 3, price => 100.00 }],
        { 3 => { high => 100.00, close => 99.50 } },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    is($bsl->{basePrice}, 100.00, 'BSL no usa el cierre como precio del swing');
}

{
    my ($liq) = compute_liquidity_with_pivots([
        { id => 'SH_DUP', kind => 'high', index => 3, price => 100.00 },
        { id => 'SH_DUP', kind => 'high', index => 3, price => 100.00 },
    ]);
    is(scalar(grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} }), 1,
       'el mismo Swing High procesado dos veces no duplica BSL');
}

{
    my ($liq) = compute_liquidity_with_pivots([
        { id => 'SH_A', kind => 'high', index => 3, price => 100.00 },
        { id => 'SH_B', kind => 'high', index => 8, price => 100.04 },
    ]);
    my @bsl = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my @eqh = grep { ($_->{type} // '') eq 'EQH' } @{ $liq->{levels} };
    is(scalar @bsl, 1, 'EQH absorbe BSL individuales en una sola BSL agrupada');
    is($bsl[0]{sourceType}, 'EQUAL_HIGHS', 'BSL agrupada marca sourceType EQUAL_HIGHS');
    is($bsl[0]{strength}, 2, 'BSL agrupada incrementa fortaleza');
    is($bsl[0]{basePrice}, 100.04, 'BSL agrupada usa el high mas extremo como base');
    is(scalar @eqh, 1, 'EQH continua visible como nivel propio');
    my $shapes = Market::Overlays::Liquidity->build_shapes(
        levels => $liq->{levels}, events => [], max_visible_index => 20,
    );
    is(scalar(grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'bsl' } @$shapes), 1,
       'overlay no dibuja dos lineas BSL superpuestas para el cluster');
    is(scalar(grep { ($_->{kind} // '') eq 'line' && ($_->{color_role} // '') eq 'eqh' } @$shapes), 1,
       'overlay mantiene la linea EQH del cluster');
}

{
    my ($liq) = compute_liquidity_with_pivots([
        { id => 'SL_A', kind => 'low', index => 3, price => 95.00 },
        { id => 'SL_B', kind => 'low', index => 8, price => 94.96 },
    ]);
    my @ssl = grep { ($_->{type} // '') eq 'SSL' } @{ $liq->{levels} };
    my @eql = grep { ($_->{type} // '') eq 'EQL' } @{ $liq->{levels} };
    is(scalar @ssl, 1, 'EQL absorbe SSL individuales en una sola SSL agrupada');
    is($ssl[0]{sourceType}, 'EQUAL_LOWS', 'SSL agrupada marca sourceType EQUAL_LOWS');
    is($ssl[0]{basePrice}, 94.96, 'SSL agrupada usa el low mas extremo como base');
    is(scalar @eql, 1, 'EQL continua visible como nivel propio');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_SWEEP', kind => 'high', index => 3, price => 100.00 }],
        { 8 => { high => 100.20, close => 99.90 } },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $bsl->{id} } @{ $liq->{events} };
    is($bsl->{status}, 'GRABBED', 'BSL queda GRABBED si la mecha toma liquidez y el cierre rechaza');
    is($ev->{classification}, 'BIG_GRAB', 'pivot externo rechazado clasifica como BIG_GRAB');
    is($bsl->{end_index}, 8, 'BSL tomada termina en la vela del grab');
    my $shapes = Market::Overlays::Liquidity->build_shapes(
        levels => $liq->{levels}, events => $liq->{events}, max_visible_index => 20,
    );
    ok(scalar(grep { ($_->{color_role} // '') eq 'big_grab' && ($_->{kind} // '') eq 'rectangle' } @$shapes),
       'Big Grab dibuja zona semitransparente entre pivote y mecha');
    ok(scalar(grep { ($_->{color_role} // '') eq 'big_grab' && ($_->{kind} // '') eq 'line' } @$shapes),
       'Big Grab dibuja linea horizontal desde el pivote');
    ok(scalar(grep { ($_->{color_role} // '') eq 'big_grab' && ($_->{text} // '') eq '$$$' } @$shapes),
       'Big Grab dibuja etiqueta $$$');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_BREAK', kind => 'high', index => 3, price => 100.00 }],
        { 8 => { high => 100.20, close => 100.10 } },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $bsl->{id} } @{ $liq->{events} };
    is($bsl->{status}, 'SWEPT', 'BSL queda SWEPT si el cierre acepta por encima del pivote');
    is($ev->{classification}, 'SWEEP', 'cierre por encima del pivot high clasifica como SWEEP');
    my $shapes = Market::Overlays::Liquidity->build_shapes(
        levels => $liq->{levels}, events => $liq->{events}, max_visible_index => 20,
    );
    ok(scalar(grep { ($_->{color_role} // '') eq 'sweep_up' && ($_->{kind} // '') eq 'line' } @$shapes),
       'Sweep dibuja linea horizontal desde el pivote');
    ok(scalar(grep { ($_->{color_role} // '') eq 'sweep_up' && ($_->{text} // '') eq 'SSS' } @$shapes),
       'Sweep dibuja etiqueta SSS');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_RUN', kind => 'high', index => 3, price => 100.00 }],
        {
            8  => { open => 99.80,  high => 100.30, low => 99.70,  close => 100.10 },
            9  => { open => 100.10, high => 100.40, low => 100.05, close => 100.20 },
            10 => { open => 100.20, high => 100.45, low => 100.10, close => 100.30 },
        },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $bsl->{id} } @{ $liq->{events} };
    is($bsl->{status}, 'RUN', 'BSL queda RUN con tres cierres consecutivos sobre el nivel');
    is($ev->{classification}, 'RUN', 'aceptacion sostenida sobre BSL clasifica como RUN');
    is($ev->{swept_index}, 8, 'Run conserva como swept_index la vela de ruptura');
    is($ev->{resolved_index}, 10, 'Run se confirma en la tercera vela consecutiva');
    is($ev->{run_close_count}, 3, 'Run alcista registra tres cierres consecutivos');
    is($ev->{run_confirmation_bars}, 3, 'Run usa 3 velas de confirmacion por defecto');
    my $shapes = Market::Overlays::Liquidity->build_shapes(
        levels => $liq->{levels}, events => $liq->{events}, max_visible_index => 20,
    );
    ok(scalar(grep { ($_->{color_role} // '') eq 'run' && ($_->{kind} // '') eq 'line' } @$shapes),
       'Run dibuja linea azul de extension');
    ok(scalar(grep { ($_->{color_role} // '') eq 'run' && ($_->{text} // '') eq 'LQ RUN' } @$shapes),
       'Run dibuja etiqueta LQ RUN');
    ok(!scalar(grep { ($_->{color_role} // '') eq 'run' && (($_->{text} // '') eq '$$$' || ($_->{text} // '') eq 'SSS') } @$shapes),
       'Run no reutiliza etiquetas $$$ ni SSS');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_RUN_TWO', kind => 'high', index => 3, price => 100.00 }],
        {
            8 => { open => 99.80,  high => 100.30, low => 99.70,  close => 100.10 },
            9 => { open => 100.10, high => 100.40, low => 100.05, close => 100.20 },
        },
        9,
    );
    ok(!scalar(grep { ($_->{classification} // '') eq 'RUN' } @{ $liq->{events} }),
       'dos cierres consecutivos sobre BSL no confirman Run con default 3');
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    is($bsl->{status}, 'ACCEPTANCE', 'nivel queda pendiente mientras faltan cierres de Run');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_RUN_FAIL', kind => 'high', index => 3, price => 100.00 }],
        {
            8  => { open => 99.80,  high => 100.30, low => 99.70,  close => 100.10 },
            9  => { open => 100.10, high => 100.40, low => 100.05, close => 100.20 },
            10 => { open => 100.20, high => 100.25, low => 99.60,  close => 99.90 },
        },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $bsl->{id} } @{ $liq->{events} };
    is($ev->{classification}, 'SWEEP', 'si se pierde aceptacion antes de N, el evento queda como Sweep');
    is($ev->{swept_index}, 8, 'Sweep fallido de Run conserva la vela de ruptura original');
    ok(!scalar(grep { ($_->{classification} // '') eq 'RUN' } @{ $liq->{events} }),
       'un contador interrumpido no deja Run duplicado');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_RUN_TWO_CFG', kind => 'high', index => 3, price => 100.00 }],
        {
            8 => { open => 99.80,  high => 100.30, low => 99.70,  close => 100.10 },
            9 => { open => 100.10, high => 100.40, low => 100.05, close => 100.20 },
        },
        undef,
        { config => { runConfirmationCandles => 2 } },
    );
    my ($ev) = grep { ($_->{classification} // '') eq 'RUN' } @{ $liq->{events} };
    ok($ev, 'runConfirmationCandles permite confirmar Run con 2 cierres');
    is($ev->{resolved_index}, 9, 'Run configurable se confirma al cierre N configurado');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SL_SWEEP', kind => 'low', index => 3, price => 95.00 }],
        { 8 => { low => 94.80, close => 95.10 } },
    );
    my ($ssl) = grep { ($_->{type} // '') eq 'SSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $ssl->{id} } @{ $liq->{events} };
    is($ssl->{status}, 'GRABBED', 'SSL queda GRABBED si la mecha toma liquidez y el cierre rechaza');
    is($ev->{classification}, 'BIG_GRAB', 'pivot low externo rechazado clasifica como BIG_GRAB');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SL_BREAK', kind => 'low', index => 3, price => 95.00 }],
        { 8 => { low => 94.80, close => 94.90 } },
    );
    my ($ssl) = grep { ($_->{type} // '') eq 'SSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $ssl->{id} } @{ $liq->{events} };
    is($ssl->{status}, 'SWEPT', 'SSL queda SWEPT si el cierre acepta por debajo del pivote');
    is($ev->{classification}, 'SWEEP', 'cierre por debajo del pivot low clasifica como SWEEP');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SL_RUN', kind => 'low', index => 3, price => 95.00 }],
        {
            8  => { open => 95.20, low => 94.70, high => 95.25, close => 94.90 },
            9  => { open => 94.90, low => 94.60, high => 94.95, close => 94.80 },
            10 => { open => 94.80, low => 94.50, high => 94.85, close => 94.70 },
        },
    );
    my ($ssl) = grep { ($_->{type} // '') eq 'SSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $ssl->{id} } @{ $liq->{events} };
    is($ssl->{status}, 'RUN', 'SSL queda RUN con tres cierres consecutivos bajo el nivel');
    is($ev->{classification}, 'RUN', 'aceptacion sostenida bajo SSL clasifica como RUN');
    is($ev->{resolved_index}, 10, 'Run bajista se confirma en la tercera vela consecutiva');
    is($ev->{run_close_count}, 3, 'Run bajista registra tres cierres consecutivos');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_INTERNAL_GRAB', kind => 'high', index => 3, price => 100.00, scope => 'internal' }],
        { 8 => { high => 100.20, close => 99.90 } },
        undef,
        { config => { showInternalLiquidity => 1 } },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    my ($ev) = grep { ($_->{level_id} // '') eq $bsl->{id} } @{ $liq->{events} };
    is($ev->{classification}, 'GRAB', 'pivot interno rechazado clasifica como GRAB');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_STRUCT', kind => 'high', index => 3, price => 100.00 }],
        { 8 => { high => 100.20, close => 100.10 } },
        undef,
        {
            structure_events => [
                { id => 'BOS_1', type => 'BOS', pivot_id => 'SH_STRUCT', break_index => 8 },
            ],
        },
    );
    my ($bsl) = grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} };
    ok(!scalar(grep { ($_->{classification} // '') eq 'SWEEP' } @{ $liq->{events} }),
       'un BOS sobre el mismo pivote no se etiqueta tambien como SWEEP');
    is($bsl->{status}, 'BROKEN', 'el nivel usado por estructura queda BROKEN');
}

{
    my ($liq) = compute_liquidity_with_pivots(
        [{ id => 'SH_PENDING', kind => 'high', index => 3, price => 100.00 }],
        {},
        5,
    );
    is(scalar(grep { ($_->{type} // '') eq 'BSL' } @{ $liq->{levels} }), 0,
       'no crea BSL antes de confirmar el Swing High');
}

{
    my ($full) = compute_liquidity_with_pivots([
        { id => 'SH_NR_A', kind => 'high', index => 3, price => 100.00 },
        { id => 'SH_NR_B', kind => 'high', index => 8, price => 100.04 },
    ]);
    my ($replayed) = compute_liquidity_with_pivots([
        { id => 'SH_NR_A', kind => 'high', index => 3, price => 100.00 },
        { id => 'SH_NR_B', kind => 'high', index => 8, price => 100.04 },
    ], {}, 23);
    is_deeply(
        [ map { [ $_->{type}, $_->{sourceType} // '', $_->{firstPivotIndex} // '', $_->{lastPivotIndex} // '', $_->{status} // '' ] }
          sort { ($a->{type} cmp $b->{type}) || (($a->{id} // '') cmp ($b->{id} // '')) } @{ $replayed->{levels} } ],
        [ map { [ $_->{type}, $_->{sourceType} // '', $_->{firstPivotIndex} // '', $_->{lastPivotIndex} // '', $_->{status} // '' ] }
          sort { ($a->{type} cmp $b->{type}) || (($a->{id} // '') cmp ($b->{id} // '')) } @{ $full->{levels} } ],
        'procesar el mismo dataset produce los mismos niveles y estados deterministas',
    );
}

my $eqh_swept = compute_with_structure_pivots(
    'EQH',
    [[3, 100.00], [8, 100.06]],
    {
        12 => { high => 100.12, close => 100.00 },
        13 => { high => 100.02, close => 99.95 },
        14 => { high => 100.01, close => 99.90 },
    },
);
my ($swept_level) = grep { ($_->{type} // '') eq 'EQH' } @{ $eqh_swept->{levels} };
is($swept_level->{status}, 'GRABBED', 'EQH queda consumido como grab si la mecha supera y el cierre rechaza');
ok(!$swept_level->{active}, 'EQH tomado deja de estar activo');

my $eqh_broken = compute_with_structure_pivots(
    'EQH',
    [[3, 100.00], [8, 100.06]],
    {
        12 => { high => 100.14, close => 100.12 },
        13 => { high => 100.15, close => 100.13 },
        14 => { high => 100.16, close => 100.14 },
        15 => { high => 100.17, close => 100.15 },
    },
);
my ($broken_level) = grep { ($_->{type} // '') eq 'EQH' } @{ $eqh_broken->{levels} };
is($broken_level->{status}, 'SWEPT', 'EQH queda SWEPT si el cierre acepta encima');

my $eql_swept = compute_with_structure_pivots(
    'EQL',
    [[3, 95.00], [8, 94.94]],
    {
        12 => { low => 94.88, close => 95.05 },
        13 => { low => 94.98, close => 95.10 },
        14 => { low => 95.00, close => 95.15 },
    },
);
my ($eql_swept_level) = grep { ($_->{type} // '') eq 'EQL' } @{ $eql_swept->{levels} };
is($eql_swept_level->{status}, 'GRABBED', 'EQL queda consumido como grab si la mecha perfora y el cierre rechaza');

my $before_confirmation = compute_with_structure_pivots('EQH', [[3, 100.00], [8, 100.06]], {}, 10);
is(scalar(grep { ($_->{type} // '') eq 'EQH' } @{ $before_confirmation->{levels} }), 0,
   'no aparece EQH antes de confirmar el segundo pivote');
my $at_confirmation = compute_with_structure_pivots('EQH', [[3, 100.00], [8, 100.06]], {}, 11);
my ($confirmed_level) = grep { ($_->{type} // '') eq 'EQH' } @{ $at_confirmation->{levels} };
is($confirmed_level->{createdAt}, 11, 'EQH aparece en la confirmacion del segundo pivote');
is($confirmed_level->{firstPivotIndex}, 3, 'no repaint: primer pivote confirmado conserva su indice');
is($confirmed_level->{lastPivotIndex}, 8, 'no repaint: segundo pivote confirmado conserva su indice');

my $legacy_shapes = Market::Overlays::Liquidity->build_shapes(
    levels => [
        { id => 'EQH_ACTIVE', type => 'EQH', timeframe => '1m', price => 100,
          start_index => 2, active => 1,
          pivots => [ { index => 1, price => 100.00 }, { index => 6, price => 100.05 } ] },
        { id => 'EQL_ACTIVE', type => 'EQL', timeframe => '1m', price => 90,
          start_index => 3, active => 1,
          pivots => [ { index => 2, price => 90.00 }, { index => 7, price => 89.96 } ] },
        { id => 'EQH_DONE', type => 'EQH', timeframe => '1m', price => 101,
          start_index => 4, end_index => 8, active => 0,
          pivots => [ { index => 4, price => 101.00 }, { index => 8, price => 101.04 } ] },
        { id => 'EQL_DONE', type => 'EQL', timeframe => '1m', price => 89,
          start_index => 5, end_index => 9, active => 0,
          pivots => [ { index => 5, price => 89.00 }, { index => 9, price => 88.97 } ] },
        { id => 'BSL_DONE', type => 'BSL', timeframe => '1m', price => 102,
          start_index => 1, end_index => 7, active => 0 },
    ],
    events            => [],
    max_visible_index => 12,
);
is(scalar(grep { ($_->{color_role} // '') =~ /^(?:eqh|eql)$/ } @$legacy_shapes), 8,
   'overlay mantiene EQH/EQL activos y resueltos cuando tienen pivotes');
is(scalar(grep { ($_->{source_id} // '') =~ /^EQ[HL]_DONE$/ && ($_->{opacity} // 0) >= 0.9 } @$legacy_shapes), 4,
   'EQH/EQL historicos conservan opacidad estilo Pine');
is(scalar(grep { ($_->{source_id} // '') eq 'BSL_DONE' } @$legacy_shapes), 2,
   'el cambio visual no altera BSL/SSL');

my $many_shapes = Market::Overlays::Liquidity->build_shapes(
    levels => [
        map {
            +{ id => "EQH_OLD_$_", type => 'EQH', timeframe => '1m', price => 100 + $_,
               start_index => $_, end_index => $_ + 1, active => 0,
               pivots => [ { index => $_, price => 100 + $_ }, { index => $_ + 1, price => 100 + $_ + 0.02 } ] }
        } 1 .. 9
    ],
    events            => [],
    max_visible_index => 20,
);
is(scalar(grep { ($_->{color_role} // '') eq 'eqh' } @$many_shapes), 18,
   'overlay mantiene todos los EQH historicos del payload');

done_testing();
