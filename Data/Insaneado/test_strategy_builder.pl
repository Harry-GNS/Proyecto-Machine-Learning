#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::Strategy_Builder;
use Market::Overlays::Strategy_Builder;

sub candles {
    my ($count) = @_;
    return [
        map {
            +{
                time   => sprintf('2026-06-29T00:%02d:00', $_),
                open   => 100 + $_ * 0.1,
                high   => 101 + $_ * 0.1,
                low    => 99 + $_ * 0.1,
                close  => 100 + $_ * 0.1,
                volume => 100,
            }
        } 0 .. ($count - 1)
    ];
}

sub series {
    my (@dirs) = @_;
    return [
        map {
            +{
                id        => "S_$_",
                index     => $_,
                time      => sprintf('2026-06-29T00:%02d:00', $_),
                timeframe => '1m',
                direction => $dirs[$_],
                value     => 100 + $_,
            }
        } 0 .. $#dirs
    ];
}

sub signal_result {
    my (%args) = @_;
    my $candles = candles($args{count} // 8);
    return Market::Indicators::Strategy_Builder::_build_strategy_signals(
        $candles,
        $#$candles,
        '1m',
        Market::Indicators::Strategy_Builder::_normalize_strategy_settings($args{settings} // {}),
        $args{ctx},
    );
}

{
    my $res = signal_result(
        count => 4,
        settings => { main_indicator => 'supertrend', confirmations => {}, alternate_signals => 0 },
        ctx => {
            supertrend   => series(qw(bearish bullish bullish bullish)),
            halftrend    => series(qw(bearish bearish bearish bearish)),
            range_filter => series(qw(neutral neutral neutral neutral)),
            supply_zones => [],
            demand_zones => [],
        },
    );
    ok($res->{signals}[1]{long_signal}, 'Strategy Builder genera Long con indicador principal solamente');
}

{
    my $res = signal_result(
        count => 5,
        settings => {
            main_indicator => 'supertrend',
            confirmations => { halftrend => 1 },
            signal_expiry_bars => 3,
            alternate_signals => 0,
        },
        ctx => {
            supertrend   => series(qw(bearish bullish bullish bullish bullish)),
            halftrend    => series(qw(bearish bearish bullish bullish bullish)),
            range_filter => series(qw(neutral neutral neutral neutral neutral)),
            supply_zones => [],
            demand_zones => [],
        },
    );
    ok(!$res->{signals}[1]{long_signal}, 'una confirmacion activa bloquea Long hasta aprobar');
    ok($res->{signals}[2]{long_signal}, 'una confirmacion activa participa realmente en Long');
}

{
    my $res = signal_result(
        count => 5,
        settings => {
            main_indicator => 'supertrend',
            confirmations => { halftrend => 1, range_filter => 1 },
            signal_expiry_bars => 3,
            alternate_signals => 0,
        },
        ctx => {
            supertrend   => series(qw(bearish bullish bullish bullish bullish)),
            halftrend    => series(qw(bearish bullish bullish bullish bullish)),
            range_filter => series(qw(neutral neutral bullish bullish bullish)),
            supply_zones => [],
            demand_zones => [],
        },
    );
    ok(!$res->{signals}[1]{long_signal}, 'confirmaciones multiples usan AND');
    ok($res->{signals}[2]{long_signal}, 'Long aparece cuando todas las confirmaciones AND aprueban');
}

{
    my $res = signal_result(
        count => 7,
        settings => {
            main_indicator => 'supertrend',
            confirmations => { halftrend => 1 },
            signal_expiry_bars => 2,
            alternate_signals => 0,
        },
        ctx => {
            supertrend   => series(qw(bearish bullish bullish bullish bullish bullish bullish)),
            halftrend    => series(qw(bearish bearish bearish bearish bullish bullish bullish)),
            range_filter => series(qw(neutral neutral neutral neutral neutral neutral neutral)),
            supply_zones => [],
            demand_zones => [],
        },
    );
    ok(!scalar(grep { $_->{long_signal} } @{ $res->{signals} }), 'señal principal expira si la confirmacion llega tarde');
}

{
    my $ctx = {
        supertrend   => series(qw(bearish bullish neutral bullish bearish)),
        halftrend    => series(qw(bearish bullish bullish bullish bearish)),
        range_filter => series(qw(neutral bullish bullish bullish bearish)),
        supply_zones => [],
        demand_zones => [],
    };
    my $alt = signal_result(
        count => 5,
        settings => { main_indicator => 'supertrend', confirmations => {}, alternate_signals => 1 },
        ctx => $ctx,
    );
    my $free = signal_result(
        count => 5,
        settings => { main_indicator => 'supertrend', confirmations => {}, alternate_signals => 0 },
        ctx => $ctx,
    );
    is(scalar(grep { $_->{long_signal} } @{ $alt->{signals} }), 1, 'alternate_signals bloquea Long repetido sin Short intermedio');
    is(scalar(grep { $_->{long_signal} } @{ $free->{signals} }), 2, 'alternate_signals desactivado permite Long repetido');
}

{
    my $strategy = {
        settings => Market::Indicators::Strategy_Builder::_normalize_strategy_settings({
            show_signals => 1,
            show_dashboard => 1,
        }),
        signals => [
            {
                id => 'SIG_LONG', index => 2, time => '2026-06-29T00:02:00',
                timeframe => '1m', low => 99, high => 101, close => 100,
                long_signal => 1, short_signal => 0,
            },
            {
                id => 'SIG_SHORT', index => 3, time => '2026-06-29T00:03:00',
                timeframe => '1m', low => 99, high => 101, close => 100,
                long_signal => 0, short_signal => 1,
            },
        ],
        signal_dashboard => {
            index => 3, timeframe => '1m', price => 100,
            main_indicator => 'supertrend', long_state => 'IDLE', short_state => 'SIGNAL',
            confirmations_active => ['halftrend'],
            confirmations_long => { halftrend => 0 },
            confirmations_short => { halftrend => 1 },
        },
    };
    my $shapes = Market::Overlays::Strategy_Builder->build_shapes(
        strategy => $strategy, max_visible_index => 3, timeframe => '1m',
    );
    ok(scalar(grep { ($_->{color_role} // '') eq 'strategy_long_signal' && ($_->{text} // '') eq 'LONG' } @$shapes),
       'overlay dibuja marcador LONG');
    ok(scalar(grep { ($_->{color_role} // '') eq 'strategy_short_signal' && ($_->{text} // '') eq 'SHORT' } @$shapes),
       'overlay dibuja marcador SHORT');
    ok(scalar(grep { ($_->{color_role} // '') eq 'strategy_dashboard' } @$shapes),
       'overlay dibuja dashboard de Strategy Builder');

    $strategy->{settings}{show_signals} = 0;
    $strategy->{settings}{show_dashboard} = 0;
    my $hidden = Market::Overlays::Strategy_Builder->build_shapes(
        strategy => $strategy, max_visible_index => 3, timeframe => '1m',
    );
    ok(!scalar(grep { ($_->{color_role} // '') =~ /^strategy_(?:long|short)_signal$/ } @$hidden),
       'show_signals desactiva marcadores LONG/SHORT');
    ok(!scalar(grep { ($_->{color_role} // '') eq 'strategy_dashboard' } @$hidden),
       'show_dashboard desactiva dashboard');
}

done_testing();
