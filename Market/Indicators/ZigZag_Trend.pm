# This Perl code is a port of logic from:
#   "ZigZag Volume Profile [ChartPrime]" (Pine Script® v6)
#   Subject to the terms of the Mozilla Public License 2.0
#   https://mozilla.org/MPL/2.0/
#   © ChartPrime
#
# Port author: Proyecto-Machine-Learning
# Only the swing/pivot/trend-detection logic has been ported.
# Volume Profile, POC, swing channel and all drawing code are excluded.

package Market::Indicators::ZigZag_Trend;

use strict;
use warnings;
use List::Util qw(max min);

# =============================================================================
# CONSTRUCTOR
# =============================================================================
# Parámetros:
#   swing_length        => int   (default 150) — equivalente a swingLength del original
#   pivot_high_uses_low => bool  (default 1)   — 1 = precio del pivote alto es low[1]
#                                                (fiel al original ChartPrime)
#                                                0 = usa high[1] en su lugar
# =============================================================================
sub new {
    my ($class, %args) = @_;

    my $self = {
        # --- Parámetros configurables ---
        swing_length        => $args{swing_length}        // 150,
        pivot_high_uses_low => $args{pivot_high_uses_low} // 1,

        # --- Estado interno del indicador (streaming) ---
        _highs     => [],   # histórico de highs  (ventana deslizante)
        _lows      => [],   # histórico de lows   (ventana deslizante)
        _bar_count => 0,    # número de barras procesadas hasta ahora

        # --- Variables de estado equivalentes a las `var` de Pine Script ---
        _is_bullish => undef,   # bool | undef  — isBullish

        # Último pivote alto confirmado
        _bar_index_high => undef,
        _price_high     => undef,

        # Último pivote bajo confirmado
        _bar_index_low => undef,
        _price_low     => undef,

        # Tramo activo en curso (puede actualizarse barra a barra — REPAINT)
        _active_segment => undef,

        # Lista de tramos completados del zigzag
        _segments => [],

        # --- Salida por barra (array paralelo a las velas de MarketData) ---
        data => [],
    };

    bless $self, $class;
    return $self;
}

# =============================================================================
# INTERFAZ PÚBLICA ESTÁNDAR (compatible con IndicatorManager)
# =============================================================================

# update_last: procesa la barra más reciente en modo streaming.
# Solo utiliza datos hasta la barra actual inclusive (sin lookahead).
sub update_last {
    my ($self, $market_data) = @_;

    my $current_index = $market_data->last_index();
    return unless defined $current_index;

    my $candle = $market_data->get_candle($current_index);
    return unless defined $candle;

    my $prev_candle = ($current_index > 0)
        ? $market_data->get_candle($current_index - 1)
        : undef;

    $self->_process_bar($current_index, $candle, $prev_candle, $market_data);
}

# calculate_batch: recalcula todas las barras desde cero.
sub calculate_batch {
    my ($self, $market_data) = @_;
    $self->reset();

    my $size = $market_data->size();
    for my $i (0 .. $size - 1) {
        my $candle      = $market_data->get_candle($i);
        my $prev_candle = ($i > 0) ? $market_data->get_candle($i - 1) : undef;
        $self->_process_bar($i, $candle, $prev_candle, $market_data);
    }
}

# get_values: devuelve el array de resultados, un hashref por barra.
sub get_values {
    my ($self) = @_;
    return $self->{data};
}

# reset: limpia todo el estado interno para recalcular desde cero.
sub reset {
    my ($self) = @_;
    $self->{_highs}          = [];
    $self->{_lows}           = [];
    $self->{_bar_count}      = 0;
    $self->{_is_bullish}     = undef;
    $self->{_bar_index_high} = undef;
    $self->{_price_high}     = undef;
    $self->{_bar_index_low}  = undef;
    $self->{_price_low}      = undef;
    $self->{_active_segment} = undef;
    $self->{_segments}       = [];
    $self->{data}            = [];
}

# =============================================================================
# LÓGICA INTERNA — PROCESAMIENTO DE UNA BARRA
# =============================================================================
# Traducción directa del Pine Script de ChartPrime, bloque por bloque.
# Las referencias al original se anotan con comentarios Pine: ...
# =============================================================================
sub _process_bar {
    my ($self, $bar_idx, $candle, $prev_candle, $market_data) = @_;

    my $n = $self->{swing_length};

    # ------------------------------------------------------------------
    # 1. Mantener ventanas deslizantes de highs y lows
    #    Equivalente a ta.highest(high, N) y ta.lowest(low, N) de Pine.
    #    Pine incluye la barra actual en el cálculo ("last N bars including
    #    current bar"), por lo que primero añadimos la vela actual y luego
    #    truncamos la ventana a N elementos.
    # ------------------------------------------------------------------
    push @{ $self->{_highs} }, $candle->{high};
    push @{ $self->{_lows}  }, $candle->{low};

    # Limitar la ventana a N elementos (la más antigua sale por la izquierda)
    if (scalar @{ $self->{_highs} } > $n) {
        shift @{ $self->{_highs} };
        shift @{ $self->{_lows}  };
    }

    # swingHigh = ta.highest(N)   — máximo de los últimos N highs incl. actual
    # swingLow  = ta.lowest(N)    — mínimo de los últimos N lows  incl. actual
    my $swing_high = max(@{ $self->{_highs} });
    my $swing_low  = min(@{ $self->{_lows}  });

    # ------------------------------------------------------------------
    # 2. Valores de la barra anterior para comparaciones [1]
    # ------------------------------------------------------------------
    # En Pine, swingHigh[1] es el ta.highest calculado en la barra anterior.
    # Lo almacenamos en el slot data[$bar_idx - 1] que ya existe.
    my $prev_swing_high = undef;
    my $prev_swing_low  = undef;
    my $prev_is_bullish = $self->{_is_bullish};  # isBullish[1]

    if ($bar_idx > 0 && defined $self->{data}->[$bar_idx - 1]) {
        $prev_swing_high = $self->{data}->[$bar_idx - 1]{swing_high};
        $prev_swing_low  = $self->{data}->[$bar_idx - 1]{swing_low};
    }

    # ------------------------------------------------------------------
    # 3. Actualización de tendencia
    #    Pine original:
    #      if swingHigh == high → isBullish := true
    #      if swingLow  == low  → isBullish := false
    #    Si ambas condiciones se cumplen en la misma barra, el segundo
    #    if sobreescribe al primero → queda false (bajista). Fiel al original.
    # ------------------------------------------------------------------
    my $is_bullish = $self->{_is_bullish};  # heredar estado previo

    if ($candle->{high} == $swing_high) {
        $is_bullish = 1;   # bullish
    }
    if ($candle->{low} == $swing_low) {
        $is_bullish = 0;   # bearish  (evalúa después → sobreescribe si ambas)
    }

    $self->{_is_bullish} = $is_bullish;

    # ------------------------------------------------------------------
    # 4. Detección de pivote ALTO confirmado
    #    Pine original:
    #      if high[1] == swingHigh[1] and high < swingHigh
    #          barIndexHigh := bar_index[1]
    #          priceHigh    := low[1]   ← OJO: es low[1], no high[1]
    #
    #    El parámetro pivot_high_uses_low controla esto:
    #      1 (default) → precio = low[barra anterior]   (fiel al original)
    #      0           → precio = high[barra anterior]  (alternativa intuitiva)
    # ------------------------------------------------------------------
    if (defined $prev_candle && defined $prev_swing_high
        && $prev_candle->{high} == $prev_swing_high
        && $candle->{high} < $swing_high)
    {
        $self->{_bar_index_high} = $bar_idx - 1;
        $self->{_price_high}     = $self->{pivot_high_uses_low}
            ? $prev_candle->{low}   # fiel al original ChartPrime
            : $prev_candle->{high}; # alternativa cuando pivot_high_uses_low=0
    }

    # ------------------------------------------------------------------
    # 5. Detección de pivote BAJO confirmado
    #    Pine original:
    #      if low[1] == swingLow[1] and low > swingLow
    #          barIndexLow := bar_index[1]
    #          priceLow    := low[1]
    # ------------------------------------------------------------------
    if (defined $prev_candle && defined $prev_swing_low
        && $prev_candle->{low} == $prev_swing_low
        && $candle->{low} > $swing_low)
    {
        $self->{_bar_index_low} = $bar_idx - 1;
        $self->{_price_low}     = $prev_candle->{low};
    }

    # ------------------------------------------------------------------
    # 6. Cambio de tendencia → cierra tramo y abre uno nuevo
    #    Pine original:
    #      if isBullish != isBullish[1] and isBullish     → tramo bajista→alcista
    #      if isBullish != isBullish[1] and not isBullish → tramo alcista→bajista
    # ------------------------------------------------------------------
    my $trend_changed = 0;

    if (defined $is_bullish && defined $prev_is_bullish
        && $is_bullish != $prev_is_bullish)
    {
        $trend_changed = 1;

        # Cerrar el tramo activo y guardarlo en la lista de completados
        if (defined $self->{_active_segment}) {
            my $seg = $self->{_active_segment};

            # Actualizar el extremo final del tramo cerrado con el último
            # pivote conocido antes del cambio de tendencia
            if ($is_bullish) {
                # Acabamos de girar a alcista: el tramo que se cierra era bajista
                # Pine: zigzagLine := line.new(barIndexLow, priceLow, barIndexHigh, priceHigh)
                $seg->{to_bar}   = $self->{_bar_index_high} // $bar_idx;
                $seg->{to_price} = $self->{_price_high}     // $candle->{high};
            } else {
                # Acabamos de girar a bajista: el tramo que se cierra era alcista
                # Pine: zigzagLine := line.new(barIndexHigh, priceHigh, barIndexLow, priceLow)
                $seg->{to_bar}   = $self->{_bar_index_low} // $bar_idx;
                $seg->{to_price} = $self->{_price_low}     // $candle->{low};
            }

            push @{ $self->{_segments} }, {%$seg};  # copia inmutable al historial
        }

        # Abrir nuevo tramo activo
        if ($is_bullish) {
            # Nuevo tramo alcista: parte desde el pivote bajo hacia el pivote alto
            $self->{_active_segment} = {
                from_bar   => $self->{_bar_index_low} // $bar_idx,
                from_price => $self->{_price_low}     // $candle->{low},
                to_bar     => $self->{_bar_index_high} // $bar_idx,
                to_price   => $self->{_price_high}     // $candle->{high},
                direction  => 'bullish',
            };
        } else {
            # Nuevo tramo bajista: parte desde el pivote alto hacia el pivote bajo
            $self->{_active_segment} = {
                from_bar   => $self->{_bar_index_high} // $bar_idx,
                from_price => $self->{_price_high}     // $candle->{high},
                to_bar     => $self->{_bar_index_low} // $bar_idx,
                to_price   => $self->{_price_low}     // $candle->{low},
                direction  => 'bearish',
            };
        }
    }

    # ------------------------------------------------------------------
    # 7. Actualización del extremo del tramo en curso (REPAINT)
    #    Pine original:
    #      if isBullish and priceHigh != priceHigh[1]
    #          zigzagLine.set_xy2(barIndexHigh, priceHigh)
    #      if not isBullish and priceLow != priceLow[1]
    #          zigzagLine.set_xy2(barIndexLow, priceLow)
    #
    #    REPAINT: el extremo "to" del tramo activo se mueve con cada nuevo
    #    pivote confirmado, exactamente igual que en TradingView. Esta es
    #    la fuente del comportamiento "repaint" del zigzag original.
    #    El tramo solo queda fijo cuando se emite al historial (_segments).
    # ------------------------------------------------------------------
    if (defined $self->{_active_segment} && !$trend_changed) {
        if ($is_bullish) {
            # REPAINT: actualizar extremo superior del tramo alcista activo
            if (defined $self->{_bar_index_high} && defined $self->{_price_high}) {
                $self->{_active_segment}{to_bar}   = $self->{_bar_index_high};
                $self->{_active_segment}{to_price} = $self->{_price_high};
            }
        } elsif (defined $is_bullish && !$is_bullish) {
            # REPAINT: actualizar extremo inferior del tramo bajista activo
            if (defined $self->{_bar_index_low} && defined $self->{_price_low}) {
                $self->{_active_segment}{to_bar}   = $self->{_bar_index_low};
                $self->{_active_segment}{to_price} = $self->{_price_low};
            }
        }
    }

    # ------------------------------------------------------------------
    # 8. Guardar resultado de esta barra
    # ------------------------------------------------------------------
    $self->{data}[$bar_idx] = {
        # Estado de tendencia
        trend         => (defined $is_bullish ? ($is_bullish ? 'bullish' : 'bearish') : undef),
        trend_changed => $trend_changed,

        # Swing extremes de esta barra (equivalentes a swingHigh/swingLow en Pine)
        swing_high => $swing_high,
        swing_low  => $swing_low,

        # Último pivote alto confirmado (inmutable hasta que se confirme otro)
        pivot_high => (defined $self->{_bar_index_high} ? {
            bar_index => $self->{_bar_index_high},
            price     => $self->{_price_high},
        } : undef),

        # Último pivote bajo confirmado
        pivot_low => (defined $self->{_bar_index_low} ? {
            bar_index => $self->{_bar_index_low},
            price     => $self->{_price_low},
        } : undef),

        # Instantánea de los tramos completados hasta esta barra
        # (referencia al mismo array; el consumidor puede usar scalar @$segments)
        segments => [ @{ $self->{_segments} } ],

        # Tramo activo en curso (puede cambiar en barras futuras — REPAINT)
        active_segment => (defined $self->{_active_segment}
            ? {%{ $self->{_active_segment} }}
            : undef),
    };
}

1;
