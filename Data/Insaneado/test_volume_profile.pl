#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::Volume_Profile;
use Market::Overlays::Volume_Profile;

my @candles = (
    { time => '2026-01-01T09:30:00-05:00', open => 1, high => 10, low => 0, close => 9, volume => 100 },
    { time => '2026-01-01T09:31:00-05:00', open => 5, high => 6,  low => 4, close => 5, volume => 60 },
    { time => '2026-01-01T09:32:00-05:00', open => 8, high => 8,  low => 8, close => 8, volume => 50 },
);

my $vp = Market::Indicators::Volume_Profile->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    visible_start     => 0,
    timeframe         => '1m',
    settings          => {
        show                => 1,
        mode                => 'session',
        profiles_to_display => 1,
        number_of_bins      => 5,
        value_area_percent  => 70,
        min_bars            => 1,
    },
);

is(scalar @{ $vp->{profiles} }, 1, 'calcula un perfil de sesion');
is($vp->{method}, 'overlap_high_low_volume_distribution', 'declara distribucion por interseccion high-low/bin');

my $profile = $vp->{profiles}[0];
is(scalar @{ $profile->{bins} }, 5, 'crea el numero solicitado de bins');
is($profile->{total_volume}, 210, 'no duplica el volumen al atravesar multiples bins');

my @volumes = map { $_->{volume} } @{ $profile->{bins} };
is_deeply(\@volumes, [20, 20, 80, 20, 70], 'distribuye volumen proporcionalmente y maneja high == low');

my $manual_poc = 0;
for my $i (1 .. $#volumes) {
    $manual_poc = $i if $volumes[$i] > $volumes[$manual_poc];
}
is($profile->{poc_bin_index}, $manual_poc, 'POC corresponde al bin de mayor volumen');
is($profile->{poc_price}, 5, 'POC usa el centro del bin de mayor volumen');
is($profile->{poc_bar_index}, 1, 'POC conserva la vela con mayor contribucion al bin');
cmp_ok($profile->{value_area_percent_actual}, '>=', 70, 'value area cubre al menos el porcentaje objetivo');
is($profile->{val}, 4, 'VAL queda en el limite inferior del area de valor');
is($profile->{vah}, 10, 'VAH queda en el limite superior del area de valor');

my $poc = $vp->{pocs}[0];
is($poc->{anchor_index}, 1, 'contrato POC expone anchor_index para Anchored VWAP');
is($poc->{poc_time}, $candles[1]{time}, 'contrato POC expone anchor_time/poc_time sin mirar futuro');
like($poc->{temporal_criterion}, qr/bin POC/, 'contrato POC documenta criterio temporal');

my $fallback = Market::Indicators::Volume_Profile->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    visible_start     => 1,
    timeframe         => '1m',
    settings          => {
        show                => 1,
        mode                => 'structure',
        structure_event     => 'choch',
        profiles_to_display => 1,
        number_of_bins      => 5,
        min_bars            => 1,
    },
    structure_events => [],
);

is(scalar @{ $fallback->{profiles} }, 1, 'usa contingencia historica sin eventos BOS/CHoCH');
is($fallback->{profiles}[0]{profile_mode}, 'historical_fallback', 'marca el perfil de contingencia historica');
ok($fallback->{profiles}[0]{historical_fallback}, 'expone flag historical_fallback');

my $visible = Market::Indicators::Volume_Profile->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    visible_start     => 1,
    timeframe         => '1m',
    settings          => {
        show                => 1,
        mode                => 'visible_range',
        profiles_to_display => 1,
        number_of_bins      => 5,
        min_bars            => 1,
    },
);
is(scalar @{ $visible->{profiles} }, 1, 'calcula un unico perfil del rango visible');
is($visible->{profiles}[0]{profile_mode}, 'visible_range', 'el perfil visible usa rango propio del Volume Profile');
is($visible->{profiles}[0]{start_index}, 1, 'el rango visible inicia en visible_start');
is($visible->{profiles}[0]{end_index}, 2, 'el rango visible termina en la ultima vela visible');
is($visible->{profiles}[0]{total_volume}, 110, 'el rango visible ignora volumen fuera de la ventana');

my $zigzag = Market::Indicators::Volume_Profile->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    visible_start     => 0,
    timeframe         => '1m',
    settings          => {
        show                => 1,
        mode                => 'zigzag',
        profiles_to_display => 2,
        number_of_bins      => 5,
        min_bars            => 1,
    },
    zigzag => {
        segments => [
            { start_index => 0, end_index => 1, completed_at => 2, direction => 'bullish', start_price => 0, end_price => 6 },
        ],
        active_segment => { start_index => 1, end_index => 2, direction => 'bearish', start_price => 6, end_price => 8 },
    },
);

is(scalar @{ $zigzag->{profiles} }, 2, 'conserva perfiles por tramos ZigZag');
is($zigzag->{profiles}[0]{profile_mode}, 'zigzag', 'modo ZigZag usa rangos de pivote/swing');

my @ghost_candles = (
    { time => '2026-01-01T09:30:00-05:00', open => 20, high => 21, low => 19, close => 20, volume => 999 },
    { time => '2026-01-01T09:31:00-05:00', open => 10, high => 12, low => 10, close => 12, volume => 100 },
    { time => '2026-01-01T09:32:00-05:00', open => 12, high => 12, low => 8,  close => 8,  volume => 50 },
);

my $anchored = Market::Indicators::Volume_Profile->compute(
    candles           => \@ghost_candles,
    max_visible_index => $#ghost_candles,
    timeframe         => '1m',
    settings          => {
        show           => 1,
        mode           => 'missed_pivot_auto',
        number_of_bins => 4,
        min_bars       => 2,
    },
    anchor_event => {
        id                => 'ghost_last',
        source            => 'missed',
        kind              => 'missedPivot',
        confirmed         => 1,
        index             => 1,
        confirmationIndex => 2,
        type              => 'high',
        price             => 12,
    },
);

is(scalar @{ $anchored->{profiles} }, 1, 'perfil anclado crea un unico perfil desde el ultimo ghost');
is($anchored->{profiles}[0]{profile_mode}, 'missed_pivot_auto', 'marca el modo automatico por ghost');
is($anchored->{profiles}[0]{start_index}, 1, 'inicio del perfil usa la vela del ghost');
is($anchored->{profiles}[0]{end_index}, 2, 'fin del perfil usa la ultima vela visible');
is($anchored->{profiles}[0]{total_volume}, 150, 'ignora volumen anterior al ghost');
is($anchored->{profiles}[0]{min_price}, 8, 'rango low-high empieza en minimo del tramo anclado');
is($anchored->{profiles}[0]{max_price}, 12, 'rango low-high termina en maximo del tramo anclado');

my ($buy_sum, $sell_sum) = (0, 0);
for my $bin (@{ $anchored->{profiles}[0]{bins} }) {
    $buy_sum += $bin->{buy_volume} // 0;
    $sell_sum += $bin->{sell_volume} // 0;
}
is($buy_sum, 100, 'aproximacion OHLCV acumula volumen comprador por bin');
is($sell_sum, 50, 'aproximacion OHLCV acumula volumen vendedor por bin');

my $no_anchor = Market::Indicators::Volume_Profile->compute(
    candles           => \@ghost_candles,
    max_visible_index => $#ghost_candles,
    timeframe         => '1m',
    settings          => {
        show           => 1,
        mode           => 'missed_pivot_auto',
        number_of_bins => 4,
        min_bars       => 2,
    },
);
is(scalar @{ $no_anchor->{profiles} }, 0, 'sin ghost no usa fallback historico para el perfil anclado');

my $shapes = Market::Overlays::Volume_Profile->build_shapes(
    volume_profile    => $vp,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => {
        show                 => 1,
        show_poc             => 0,
        show_value_area      => 0,
        show_value_area_fill => 1,
        profile_width        => 3,
    },
);
is(
    scalar(grep { ($_->{color_role} // '') ne 'volume_profile_bin' } @$shapes),
    0,
    'si Value Area y POC estan desactivados solo dibuja bins'
);
my @bin_shapes = grep { ($_->{color_role} // '') eq 'volume_profile_bin' } @$shapes;
ok(
    scalar(grep { ($_->{kind} // '') eq 'rectangle' } @bin_shapes) == scalar(@bin_shapes),
    'los bins se dibujan como rectangulos rellenos'
);
ok(
    scalar(grep { ($_->{y1_price} // 0) < ($_->{y2_price} // 0) } @bin_shapes) == scalar(@bin_shapes),
    'cada rectangulo ocupa el rango de precio del bin'
);
ok(!scalar(grep { !$_->{volume_profile_row} || !$_->{right_aligned} } @bin_shapes),
    'los bins se exportan como filas alineadas al borde derecho de la escala');
ok(!scalar(grep { ($_->{right_edge} // '') ne 'price_scale_left' } @bin_shapes),
    'todas las filas declaran el mismo borde derecho junto a la escala de precios');
ok(!scalar(grep { ($_->{x1_index} // -1) != 0 || ($_->{x2_index} // -1) != 2 } @bin_shapes),
    'x1/x2 solo conservan el rango de calculo, no codifican el ancho de cada fila');
my @ratios = sort { $a <=> $b } map { $_->{normalized_volume} // $_->{volume_ratio} // 0 } @bin_shapes;
cmp_ok($ratios[-1], '<=', 1.000001, 'el volumen normalizado nunca supera el ancho maximo');
ok($ratios[-1] > $ratios[0], 'el ancho visual se deriva del volumen normalizado');

my $anchored_shapes = Market::Overlays::Volume_Profile->build_shapes(
    volume_profile    => $anchored,
    max_visible_index => $#ghost_candles,
    timeframe         => '1m',
    settings          => {
        show                 => 1,
        show_profile         => 1,
        show_poc             => 0,
        show_value_area      => 0,
        show_value_area_fill => 0,
        profile_opacity      => 0.42,
    },
);
my @anchored_rows = grep { $_->{volume_profile_row} } @$anchored_shapes;
ok(@anchored_rows > 0, 'perfil anclado genera filas especiales de histograma');
ok(!scalar(grep { ($_->{x1_index} // -1) != 1 || ($_->{x2_index} // -1) != 2 } @anchored_rows),
    'todas las filas del perfil anclado comparten ancla y borde derecho');
is($anchored_rows[0]{buy_color}, '#2098A8', 'color comprador usa cian TradingView');
is($anchored_rows[0]{sell_color}, '#B5345F', 'color vendedor usa magenta TradingView');
ok(!scalar(grep { ($_->{y1_price} // 0) >= ($_->{y2_price} // 0) } @anchored_rows),
    'cada fila anclada conserva un intervalo vertical de precio valido');

my $poc_only = Market::Overlays::Volume_Profile->build_shapes(
    volume_profile    => $vp,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => {
        show                 => 1,
        show_profile         => 0,
        show_poc             => 1,
        poc_line_width       => 4,
        show_value_area      => 0,
        show_value_area_fill => 0,
    },
);
is_deeply(
    [ sort keys %{ { map { ($_->{color_role} // '') => 1 } @$poc_only } } ],
    ['volume_profile_poc'],
    'POC puede mostrarse sin histogramas'
);
is(($poc_only->[0]{line_width} // 0), 4, 'POC Width controla el grosor del POC');

my $swing_only = Market::Overlays::Volume_Profile->build_shapes(
    volume_profile    => $zigzag,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => {
        show                 => 1,
        show_profile         => 0,
        show_poc             => 0,
        show_swing_channel   => 1,
        swing_channel_width  => 2,
        show_value_area      => 0,
        show_value_area_fill => 0,
    },
);
is_deeply(
    [ sort keys %{ { map { ($_->{color_role} // '') => 1 } @$swing_only } } ],
    ['volume_profile_swing_channel'],
    'Swing Channel puede mostrarse sin bins ni POC'
);
ok(
    scalar(grep {
        ($_->{color_role} // '') eq 'volume_profile_swing_channel'
            && ($_->{y1_price} // '') ne ($_->{y2_price} // '')
    } @$swing_only) > 0,
    'Swing Channel conserva diagonal entre pivotes'
);

done_testing();
