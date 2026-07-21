#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::ZonaInterna;
use Market::Overlays::ZonaInterna;

sub zigzag_hash {
    my (%args) = @_;
    return {
        segments => [
            {
                direction   => 'bullish',
                start_index => 0,
                start_price => 100,
                end_index   => 10,
                end_price   => 110,
            },
            {
                direction   => 'bearish',
                start_index => 10,
                start_price => 110,
                end_index   => 20,
                end_price   => 100,
            },
        ],
        active_segment => {
            direction   => 'bullish',
            start_index => 20,
            start_price => 100,
            end_index   => 30,
            end_price   => $args{current_price},
        },
    };
}

my $zona = Market::Indicators::ZonaInterna->compute(
    zigzag            => zigzag_hash(current_price => 120),
    max_visible_index => 30,
    timeframe         => '1m',
    mintick           => 0.01,
);

is($zona->{direction}, 'bullish', 'detecta direccion desde el tramo actual del zigzag');
is($zona->{base_price}, 100, 'base = zigzag[2]');
is($zona->{diff}, 10, 'diff = zigzag[4] - zigzag[2]');
is($zona->{anchor_point}{index}, 10, 'x1 usa el indice zigzag[5]');
is(scalar @{ $zona->{levels} }, 8, 'genera niveles hasta el primer cruce y corta en la siguiente iteracion');
is($zona->{levels}[0]{ratio}, 0.618, 'primer ratio opcional 0.618');
is($zona->{levels}[1]{ratio}, 0.786, 'segundo ratio opcional 0.786');
is($zona->{levels}[2]{ratio}, 1, 'luego agrega extension 1');
is(sprintf('%.2f', $zona->{levels}[0]{price}), '106.18', 'precio = base + diff * ratio');
is($zona->{levels}[0]{text}, '0.618(106.18)', 'texto replica ratio(precio redondeado)');
is($zona->{levels}[0]{x1_index}, 10, 'linea inicia en anchor anterior-anterior');
is($zona->{levels}[0]{x2_index}, 30, 'linea termina en barra visible actual');

my $early_stop = Market::Indicators::ZonaInterna->compute(
    zigzag            => zigzag_hash(current_price => 105),
    max_visible_index => 30,
    timeframe         => '1m',
    mintick           => 0.01,
);
is_deeply(
    [ map { $_->{ratio} } @{ $early_stop->{levels} } ],
    [ 0.618, 0.786, 1 ],
    'si stopit se activa temprano conserva niveles hasta x > shownlevels',
);

my $empty = Market::Indicators::ZonaInterna->compute(
    zigzag            => { segments => [] },
    max_visible_index => 10,
);
is(scalar @{ $empty->{levels} }, 0, 'sin tres puntos de zigzag no emite niveles');

my $shapes = Market::Overlays::ZonaInterna->build_shapes(
    zona_interna      => $zona,
    max_visible_index => 30,
    timeframe         => '1m',
);
is(scalar @$shapes, scalar @{ $zona->{levels} }, 'overlay crea una shape por nivel');
is($shapes->[0]{source_type}, 'zona_interna', 'source_type dedicado para filtro UI');
is($shapes->[0]{kind}, 'fib_line', 'usa fib_line para etiqueta de ratio/precio');
is($shapes->[0]{color_role}, 'zona_interna_0', 'usa paleta ciclica del snippet');
is($shapes->[0]{structure_scope}, 'internal', 'se marca como zona interna');

done_testing();
