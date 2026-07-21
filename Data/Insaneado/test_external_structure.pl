#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::SMC_Structures;
use Market::Overlays::SMC_Structures;
use Market::SMCConfig;

sub c {
    my ($i, $close) = @_;
    return {
        time   => sprintf('2026-07-13T00:%02d:00', $i),
        open   => $close,
        high   => $close + 0.75,
        low    => $close - 0.75,
        close  => $close,
        volume => 1000,
    };
}

sub p {
    my (%args) = @_;
    return {
        id             => $args{id},
        kind           => $args{kind},
        scope          => $args{scope} // 'external',
        index          => $args{index},
        confirmed_at   => $args{confirmed_at},
        price          => $args{price},
        time           => sprintf('2026-07-13T00:%02d:00', $args{index}),
        confirmed_time => sprintf('2026-07-13T00:%02d:00', $args{confirmed_at}),
        source_logic   => 'mxwll_calculatePivots',
    };
}

sub build {
    my ($closes, $pivots, $max_idx, $tf) = @_;
    my $candles = [ map { c($_, $closes->[$_]) } 0 .. $#$closes ];
    return Market::Indicators::SMC_Structures::_build_structures(
        $candles, $pivots, $max_idx // $#$closes, $tf // '1m', [],
    );
}

sub primary_events {
    my ($events, $scope) = @_;
    return [
        grep {
            ($_->{type} // '') ne 'MSS'
                && (!defined $scope || ($_->{scope} // '') eq $scope)
        } @$events
    ];
}

my $defaults = Market::SMCConfig->defaults;
is($defaults->{externalStructureSensitivity}, 50,
   'estructura externa usa longitud swing 50 como SMC Pro Historical');
is($defaults->{internalStructureSensitivity}, 5,
   'estructura interna usa longitud 5 como SMC Pro Historical');

my $bull_bos = primary_events(build(
    [ 9, 9, 9, 9, 9.5, 10.5, 10.8, 10.9, 11.0, 12.5 ],
    [
        p(id => 'EH1', kind => 'high', index => 1, confirmed_at => 2, price => 10),
        p(id => 'EH2', kind => 'high', index => 6, confirmed_at => 7, price => 12),
    ],
), 'external');
is(scalar @$bull_bos, 2, 'tendencia externa alcista produce dos rupturas de high');
is($bull_bos->[1]{type}, 'BOS', 'nuevo maximo externo en sesgo alcista es BOS');
is($bull_bos->[1]{direction}, 'bullish', 'BOS externo de maximo es bullish');
is($bull_bos->[1]{previous_trend}, 'bullish', 'BOS alcista externo usa sesgo externo previo');
is($bull_bos->[1]{pivot_index}, 6, 'linea externa alcista nace en el pivot swing roto');
is($bull_bos->[1]{break_index}, 9, 'linea externa alcista termina en la vela de ruptura');
is($bull_bos->[1]{display_type}, 'BOS', 'texto externo alcista usa BOS exacto');

my $bull_choch = primary_events(build(
    [ 8, 8, 8, 7, 6.5, 5.5, 6, 7, 9.5, 10.5 ],
    [
        p(id => 'EL1', kind => 'low',  index => 1, confirmed_at => 2, price => 6),
        p(id => 'EH1', kind => 'high', index => 3, confirmed_at => 6, price => 10),
    ],
), 'external');
is($bull_choch->[0]{type}, 'BOS', 'primera ruptura de low establece sesgo externo bajista');
is($bull_choch->[1]{type}, 'CHOCH', 'ruptura de high contra sesgo bajista es CHoCH');
is($bull_choch->[1]{direction}, 'bullish', 'CHoCH externo alcista conserva direccion bullish');
is($bull_choch->[1]{previous_trend}, 'bearish', 'CHoCH alcista externo lee sesgo externo previo bajista');
is($bull_choch->[1]{display_type}, 'CHoCH', 'texto externo CHoCH usa capitalizacion exacta');

my $bear_bos = primary_events(build(
    [ 8, 8, 8, 7, 6.5, 5.5, 6, 5.8, 5.5, 4.5 ],
    [
        p(id => 'EL1', kind => 'low', index => 1, confirmed_at => 2, price => 6),
        p(id => 'EL2', kind => 'low', index => 6, confirmed_at => 7, price => 5),
    ],
), 'external');
is(scalar @$bear_bos, 2, 'tendencia externa bajista produce dos rupturas de low');
is($bear_bos->[1]{type}, 'BOS', 'nuevo minimo externo en sesgo bajista es BOS');
is($bear_bos->[1]{direction}, 'bearish', 'BOS externo de minimo es bearish');
is($bear_bos->[1]{previous_trend}, 'bearish', 'BOS bajista externo usa sesgo externo previo');

my $bear_choch = primary_events(build(
    [ 8, 8, 8, 9, 9.5, 10.5, 10, 9, 6.5, 5.5 ],
    [
        p(id => 'EH1', kind => 'high', index => 1, confirmed_at => 2, price => 10),
        p(id => 'EL1', kind => 'low',  index => 3, confirmed_at => 6, price => 6),
    ],
), 'external');
is($bear_choch->[0]{type}, 'BOS', 'primera ruptura de high establece sesgo externo alcista');
is($bear_choch->[1]{type}, 'CHOCH', 'ruptura de low contra sesgo alcista es CHoCH');
is($bear_choch->[1]{direction}, 'bearish', 'CHoCH externo bajista conserva direccion bearish');
is($bear_choch->[1]{previous_trend}, 'bullish', 'CHoCH bajista externo lee sesgo externo previo alcista');

my $internal_only = build(
    [ 9, 9, 9, 9, 9.5, 10.5 ],
    [
        p(id => 'IH1', scope => 'internal', kind => 'high', index => 1, confirmed_at => 2, price => 10),
        p(id => 'EH1', scope => 'external', kind => 'high', index => 1, confirmed_at => 2, price => 20),
    ],
);
is(scalar @{ primary_events($internal_only, 'internal') }, 1,
   'ruptura interna genera evento interno');
is(scalar @{ primary_events($internal_only, 'external') }, 0,
   'ruptura interna sin romper swing no genera evento externo');

my $no_repeats = primary_events(build(
    [ 9, 9, 9.5, 10.5, 9.5, 10.5 ],
    [ p(id => 'EH1', kind => 'high', index => 1, confirmed_at => 1, price => 10) ],
), 'external');
is(scalar @$no_repeats, 1, 'un mismo pivote externo se rompe una sola vez aunque el precio recruce');

my $replay_closes = [ 9, 9, 9.5, 10.5 ];
my $replay_pivots = [ p(id => 'EH1', kind => 'high', index => 1, confirmed_at => 1, price => 10) ];
is(scalar @{ primary_events(build($replay_closes, $replay_pivots, 2), 'external') }, 0,
   'replay antes de la vela de ruptura no muestra estructura externa');
is(scalar @{ primary_events(build($replay_closes, $replay_pivots, 3), 'external') }, 1,
   'replay al llegar a la vela de ruptura muestra estructura externa');

my $same_bar = build(
    [ 9, 9, 9.4, 10.5 ],
    [
        p(id => 'IH1', scope => 'internal', kind => 'high', index => 1, confirmed_at => 1, price => 9.5),
        p(id => 'EH1', scope => 'external', kind => 'high', index => 1, confirmed_at => 1, price => 10),
    ],
);
is(scalar @{ primary_events($same_bar, 'internal') }, 1,
   'evento interno se conserva cuando comparte vela de ruptura');
is(scalar @{ primary_events($same_bar, 'external') }, 1,
   'evento externo se conserva cuando comparte vela de ruptura');
is_deeply(
    [ sort map { $_->{scope} } @{ primary_events($same_bar) } ],
    [ qw(external internal) ],
    'eventos simultaneos mantienen scopes independientes',
);

my $same_level = build(
    [ 9, 9, 9.5, 10.5 ],
    [
        p(id => 'IH_SAME', scope => 'internal', kind => 'high', index => 1, confirmed_at => 1, price => 10),
        p(id => 'EH_SAME', scope => 'external', kind => 'high', index => 1, confirmed_at => 1, price => 10),
    ],
);
is(scalar @{ primary_events($same_level, 'external') }, 1,
   'ruptura del nivel swing compartido conserva el evento externo');
is(scalar @{ primary_events($same_level, 'internal') }, 0,
   'nivel interno igual al swing activo no se duplica como estructura interna');

my $tf_events = primary_events(build(
    [ 9, 9, 9.5, 10.5 ],
    [ p(id => 'EH1', kind => 'high', index => 1, confirmed_at => 1, price => 10) ],
    3,
    '5m',
), 'external');
is($tf_events->[0]{timeframe}, '5m', 'cambio de temporalidad no reutiliza timeframe anterior');

my $overlay_shapes = Market::Overlays::SMC_Structures->build_shapes(
    pivots      => [],
    structures  => [
        $bull_bos->[1],
        $bear_choch->[1],
        @{ primary_events($same_bar, 'internal') },
    ],
    max_visible_index => 9,
    timeframe         => '1m',
);
my @structure_labels = grep { ($_->{kind} // '') eq 'label' && ($_->{source_type} // '') eq 'smc' } @$overlay_shapes;
ok(scalar(grep { ($_->{text} // '') eq 'BOS' && ($_->{structure_scope} // '') eq 'external' && ($_->{label_position} // '') eq 'above' } @structure_labels),
   'overlay externo alcista dibuja BOS sobre la linea');
ok(scalar(grep { ($_->{text} // '') eq 'CHoCH' && ($_->{structure_scope} // '') eq 'external' && ($_->{label_position} // '') eq 'below' } @structure_labels),
   'overlay externo bajista dibuja CHoCH debajo de la linea');
ok(scalar(grep { ($_->{text} // '') eq 'I-BOS' && ($_->{structure_scope} // '') eq 'internal' } @structure_labels),
   'overlay interno dibuja I-BOS exacto');

my @structure_lines = grep { ($_->{kind} // '') eq 'line' && ($_->{source_type} // '') eq 'smc' } @$overlay_shapes;
ok(scalar(grep { ($_->{structure_scope} // '') eq 'external' && ($_->{x1_index} // -1) == 6 && ($_->{x2_index} // -1) == 9 } @structure_lines),
   'overlay externo traza linea desde pivot swing hasta vela de confirmacion');

done_testing();
