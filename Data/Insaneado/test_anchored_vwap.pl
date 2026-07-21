#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;
use Market::Indicators::Anchored_VWAP;

my @candles = (
    { time => '2026-01-01T09:30:00-05:00', open => 10, high => 12, low => 9,  close => 11, volume => 100 },
    { time => '2026-01-01T09:31:00-05:00', open => 11, high => 13, low => 10, close => 12, volume => 200 },
    { time => '2026-01-02T09:30:00-05:00', open => 20, high => 22, low => 19, close => 21, volume => 300 },
    { time => '2026-01-02T09:31:00-05:00', open => 21, high => 23, low => 20, close => 22, volume => 400 },
);

my $r = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => {
        show        => 1,
        anchor_type => 'session_start',
        source      => 'hlc3',
        bands       => [ { show => 1, multiplier => 1 }, { show => 0 }, { show => 0 } ],
    },
);

is(scalar @{ $r->{segments} }, 2, 'Session Start separa segmentos por fecha');
is($r->{segments}[0]{anchor_index}, 0, 'primer segmento ancla en primera vela');
is($r->{segments}[1]{anchor_index}, 2, 'segundo segmento reinicia en nueva sesion');

my $src0 = (12 + 9 + 11) / 3;
my $src1 = (13 + 10 + 12) / 3;
my $manual = (($src0 * 100) + ($src1 * 200)) / 300;
cmp_ok(abs($r->{segments}[0]{points}[1]{value} - $manual), '<', 1e-8, 'VWAP usa suma precio*volumen / volumen');
ok(defined $r->{segments}[0]{points}[1]{upper1}, 'calcula banda superior ponderada');
ok(defined $r->{segments}[0]{points}[1]{lower1}, 'calcula banda inferior ponderada');

my $bos = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => { show => 1, anchor_type => 'confirmed_bos', source => 'close', structure_scope => 'external' },
    structure_events  => [
        { id => 'S1', type => 'BOS', scope => 'external', status => 'confirmed', confirmation_index => 2, confirmation_time => $candles[2]{time} },
    ],
);
is($bos->{segments}[1]{anchor_index}, 2, 'BOS confirmado reinicia en confirmation_index');
is($bos->{segments}[1]{points}[0]{value}, 21, 'source Close se aplica sin duplicar calculo');

my $poc = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => { show => 1, anchor_type => 'volume_profile_poc', source => 'hlc3' },
    poc_events        => [
        { id => 'P1', anchor_index => 1, anchor_time => $candles[1]{time}, poc_price => 12, poc_volume => 200 },
    ],
);
is($poc->{segments}[1]{anchor_index}, 1, 'POC consume anchor_index expuesto por Volume Profile');

my $manual_anchor = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => $#candles,
    timeframe         => '1m',
    settings          => {
        show               => 1,
        anchor_type        => 'manual',
        manual_anchor_time => $candles[1]{time},
        source             => 'hlc3',
        bands              => [ { show => 1, multiplier => 1 }, { show => 0 }, { show => 0 } ],
    },
);
is(scalar @{ $manual_anchor->{segments} }, 1, 'Manual crea un unico segmento');
is($manual_anchor->{segments}[0]{anchor_index}, 1, 'Manual ancla en la vela seleccionada');
is(scalar(grep { $_->{index} < 1 } @{ $manual_anchor->{segments}[0]{points} }), 0, 'Manual no emite puntos antes del ancla');
cmp_ok(abs($manual_anchor->{segments}[0]{points}[0]{value} - $src1), '<', 1e-8, 'Primer punto manual usa solo la vela anclada');

my $manual_hidden = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@candles,
    max_visible_index => 0,
    timeframe         => '1m',
    settings          => {
        show               => 1,
        anchor_type        => 'manual',
        manual_anchor_time => $candles[1]{time},
        source             => 'hlc3',
    },
);
is($manual_hidden->{visible}, 0, 'Manual queda oculto si replay esta antes del ancla');
like($manual_hidden->{warning}, qr/ancla manual/, 'Manual informa ancla no visible antes del corte');

my @tf5 = (
    { time => '2026-01-01T09:30:00', open => 10, high => 13, low => 9, close => 12, volume => 300 },
    { time => '2026-01-01T09:35:00', open => 12, high => 15, low => 11, close => 14, volume => 500 },
);
my $manual_tf = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@tf5,
    max_visible_index => $#tf5,
    timeframe         => '5m',
    settings          => {
        show               => 1,
        anchor_type        => 'manual',
        manual_anchor_time => '2026-01-01T09:31:00-05:00',
        source             => 'hlc3',
    },
);
is($manual_tf->{segments}[0]{anchor_index}, 0, 'Manual conserva timestamp dentro de la vela agregada del nuevo timeframe');

my @zero = map { { %$_, volume => 0 } } @candles;
my $z = Market::Indicators::Anchored_VWAP->compute(
    candles           => \@zero,
    max_visible_index => $#zero,
    timeframe         => '1m',
    settings          => { show => 1, anchor_type => 'session_start', source => 'hlc3' },
);
is($z->{visible}, 0, 'no dibuja si no hay volumen valido');
like($z->{warning}, qr/volumen/, 'advierte volumen invalido');

done_testing;
