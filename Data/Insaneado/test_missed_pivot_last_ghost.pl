#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

# ============================================================
#  Regresion: el Anchored VWAP automatico debe anclarse
#  EXCLUSIVAMENTE al ultimo fantasma (mayor bar_index / pivotTime),
#  confirmado o provisional (barstate.islast), ignorando los previos.
# ============================================================

use Test::More;
use Market::Indicators::Anchored_VWAP;

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

sub auto {
    my (%extra) = @_;
    return Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
        candles           => \@candles,
        max_visible_index => 4,
        timeframe         => '1m',
        symbol            => 'BTCUSDT',
        settings          => { show => 1, source => 'hlc3' },
        %extra,
    );
}

sub confirmed_ghost {
    my (%o) = @_;
    return {
        id                => $o{id},
        kind              => 'missedPivot',
        status            => 'confirmed',
        confirmed         => 1,
        type              => $o{type},
        pivotType         => $o{type},
        index             => $o{index},
        pivotTime         => $candles[$o{index}]{time},
        confirmationIndex => $o{confirm},
        confirmationTime  => $candles[$o{confirm}]{time},
        price             => $o{price} // 12,
    };
}

sub provisional_ghost {
    my (%o) = @_;
    return {
        id        => $o{id} // ('pivotMissedReversal_provisional_' . $o{type} . '_' . $o{index} . '_9'),
        kind      => 'provisionalPivot',
        provisional => 1,
        confirmed => 0,
        type      => $o{type},
        pivotType => $o{type},
        index     => $o{index},
        pivotTime => $candles[$o{index}]{time},
        price     => $o{price} // 8,
    };
}

# ------------------------------------------------------------------
# A) Entre confirmados gana el de MAYOR bar_index aunque otro tenga
#    confirmationTime posterior (este es el bug reportado).
# ------------------------------------------------------------------
my $recent_pos  = confirmed_ghost(id => 'ghost-recent-pos',  type => 'low',  index => 3, confirm => 3);
my $late_confirm = confirmed_ghost(id => 'ghost-late-confirm', type => 'high', index => 1, confirm => 4);

my $a = auto(missed_pivot_events => [ $late_confirm, $recent_pos ]);
is($a->{visible}, 1, 'A: hay ancla visible');
is($a->{instances}[0]{anchorIndex}, 3, 'A: ancla al ghost de mayor bar_index, no al de confirmacion mas tardia');
is($a->{instances}[0]{sourceEventId}, 'ghost-recent-pos', 'A: selecciona por posicion del fantasma');
is($a->{debug}{selectedIsProvisional}, 0, 'A: el seleccionado es confirmado');

# ------------------------------------------------------------------
# B) El provisional (barstate.islast) gana si es el de mayor bar_index.
# ------------------------------------------------------------------
my $conf_old = confirmed_ghost(id => 'ghost-old', type => 'high', index => 1, confirm => 2);
my $prov4    = provisional_ghost(type => 'low', index => 4);

my $b = auto(missed_pivot_events => [ $conf_old ], provisional_pivot => $prov4);
is($b->{visible}, 1, 'B: provisional produce ancla visible');
is($b->{instances}[0]{anchorIndex}, 4, 'B: ancla al provisional (mayor bar_index)');
is($b->{instances}[0]{provisional}, 1, 'B: la instancia queda marcada como provisional');
is($b->{debug}{selectedIsProvisional}, 1, 'B: debug reporta seleccion provisional');
is($b->{debug}{provisionalGhostConsidered}, 1, 'B: debug reporta que se considero el provisional');
like($b->{instances}[0]{id}, qr/provisional-pivot/, 'B: id de instancia identifica origen provisional');

# ------------------------------------------------------------------
# C) El id del provisional es estable mientras su bar_index no cambie,
#    aunque avance max_visible_index (no debe re-anclar cada barra).
# ------------------------------------------------------------------
my $prov3 = provisional_ghost(type => 'low', index => 3);
my $c1 = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles => \@candles, max_visible_index => 3, timeframe => '1m',
    symbol => 'BTCUSDT', settings => { show => 1, source => 'hlc3' },
    provisional_pivot => $prov3,
);
my $c2 = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles => \@candles, max_visible_index => 4, timeframe => '1m',
    symbol => 'BTCUSDT', settings => { show => 1, source => 'hlc3' },
    provisional_pivot => $prov3,
);
is($c1->{instances}[0]{id}, $c2->{instances}[0]{id},
    'C: id provisional estable al avanzar max_visible_index sin mover el fantasma');

# ------------------------------------------------------------------
# D) En empate exacto de bar_index, el confirmado gana al provisional.
# ------------------------------------------------------------------
my $conf3 = confirmed_ghost(id => 'ghost-conf-3', type => 'low', index => 3, confirm => 4);
my $prov3b = provisional_ghost(type => 'low', index => 3);
my $d = auto(missed_pivot_events => [ $conf3 ], provisional_pivot => $prov3b);
is($d->{instances}[0]{sourceEventId}, 'ghost-conf-3', 'D: confirmado gana al provisional en igual bar_index');
is($d->{instances}[0]{provisional}, 0, 'D: la instancia elegida no es provisional');

# ------------------------------------------------------------------
# E) Sin confirmados, el provisional solo tambien ancla.
# ------------------------------------------------------------------
my $e = auto(missed_pivot_events => [], provisional_pivot => $prov4);
is($e->{visible}, 1, 'E: provisional sin confirmados tambien ancla');
is($e->{instances}[0]{anchorIndex}, 4, 'E: ancla al provisional');

# ------------------------------------------------------------------
# F) No-lookahead: un provisional fuera del rango visible se ignora.
# ------------------------------------------------------------------
my $f = Market::Indicators::Anchored_VWAP->compute_missed_pivot_auto(
    candles => \@candles, max_visible_index => 2, timeframe => '1m',
    symbol => 'BTCUSDT', settings => { show => 1, source => 'hlc3' },
    missed_pivot_events => [], provisional_pivot => $prov4,
);
is($f->{visible}, 0, 'F: provisional con bar_index > max_visible_index no se usa (sin lookahead)');

# ------------------------------------------------------------------
# G) Contexto: un provisional de otro symbol no cruza.
# ------------------------------------------------------------------
my $prov_eth = provisional_ghost(type => 'low', index => 4);
$prov_eth->{symbol} = 'ETHUSDT';
my $g = auto(missed_pivot_events => [], provisional_pivot => $prov_eth);
is($g->{visible}, 0, 'G: provisional de otro symbol no genera ancla');

done_testing;
