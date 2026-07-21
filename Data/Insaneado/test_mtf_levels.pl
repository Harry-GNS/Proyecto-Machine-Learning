#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";

use Test::More;
use Market::MTFLevels qw(
    detect_session_start_minute
    mtf_level_allowed
    period_key_for_time
    previous_high_low_levels
    previous_period_extremes
);

sub c {
    my ($time, $high, $low) = @_;
    return {
        time   => $time,
        open   => ($high + $low) / 2,
        high   => $high + 0,
        low    => $low + 0,
        close  => ($high + $low) / 2,
        volume => 1,
    };
}

my $cme_session_start = 17 * 60;

is(
    period_key_for_time('D', '2026-07-12T17:00:00-05:00', session_start_minute => $cme_session_start),
    '2026-07-13',
    'la sesion CME de domingo 17:00 pertenece al dia de trading lunes',
);
is(
    period_key_for_time('W', '2026-07-12T17:00:00-05:00', session_start_minute => $cme_session_start),
    '2026-07-13',
    'la semana CME cambia en la apertura del domingo por la tarde',
);
is(
    period_key_for_time('M', '2026-06-30T17:00:00-05:00', session_start_minute => $cme_session_start),
    '2026-07',
    'el mes de trading cambia en la apertura de sesion previa al primer dia',
);

my @daily = (
    c('2026-07-10T09:00:00-05:00', 100, 90),
    c('2026-07-10T10:00:00-05:00', 110, 85),
    c('2026-07-12T17:00:00-05:00', 999, 1),
    c('2026-07-13T12:00:00-05:00', 1000, 0),
);

my $prev_day = previous_period_extremes(
    period_tf            => 'D',
    reference_time       => '2026-07-13T12:00:00-05:00',
    base_candles         => \@daily,
    session_start_minute => $cme_session_start,
);
is($prev_day->{key}, '2026-07-10', 'PDH/PDL usan el dia de trading previo cerrado');
is($prev_day->{high}, 110, 'PDH no usa el maximo de la sesion actual');
is($prev_day->{low}, 85, 'PDL no usa el minimo de la sesion actual');
is($prev_day->{high_time}, '2026-07-10T10:00:00-05:00', 'PDH conserva el tiempo de la vela extrema');

my @weekly = (
    c('2026-07-05T17:00:00-05:00', 330, 130),
    c('2026-07-08T10:00:00-05:00', 350, 90),
    c('2026-07-10T15:59:00-05:00', 340, 95),
    c('2026-07-12T17:00:00-05:00', 999, 1),
    c('2026-07-13T12:00:00-05:00', 1000, 0),
);

my $prev_week = previous_period_extremes(
    period_tf            => 'W',
    reference_time       => '2026-07-13T12:00:00-05:00',
    base_candles         => \@weekly,
    session_start_minute => $cme_session_start,
);
is($prev_week->{key}, '2026-07-06', 'PWH/PWL usan la semana previa cerrada');
is($prev_week->{high}, 350, 'PWH excluye la semana actual abierta');
is($prev_week->{low}, 90, 'PWL excluye la semana actual abierta');

my @monthly = (
    c('2026-06-01T09:00:00-05:00', 400, 300),
    c('2026-06-15T10:00:00-05:00', 500, 250),
    c('2026-06-30T16:59:00-05:00', 450, 240),
    c('2026-06-30T17:00:00-05:00', 999, 1),
    c('2026-07-01T12:00:00-05:00', 1000, 0),
);

my $prev_month = previous_period_extremes(
    period_tf            => 'M',
    reference_time       => '2026-07-01T12:00:00-05:00',
    base_candles         => \@monthly,
    session_start_minute => $cme_session_start,
);
is($prev_month->{key}, '2026-06', 'PMH/PML usan el mes previo cerrado');
is($prev_month->{high}, 500, 'PMH excluye la primera sesion del mes actual');
is($prev_month->{low}, 240, 'PML conserva el minimo del mes previo');

my @ties = (
    c('2026-07-05T17:00:00-05:00', 350, 120),
    c('2026-07-08T10:00:00-05:00', 350, 90),
    c('2026-07-12T17:00:00-05:00', 999, 1),
);
my $tie_week = previous_period_extremes(
    period_tf            => 'W',
    reference_time       => '2026-07-13T12:00:00-05:00',
    base_candles         => \@ties,
    session_start_minute => $cme_session_start,
);
is($tie_week->{high_time}, '2026-07-05T17:00:00-05:00', 'maximos repetidos conservan la primera ocurrencia estilo indexof');

my @levels = previous_high_low_levels(
    chart_timeframe      => '1m',
    reference_time       => '2026-07-13T12:00:00-05:00',
    base_candles         => \@weekly,
    chart_candles        => \@weekly,
    session_start_minute => $cme_session_start,
);
my %by_type = map { $_->{type} => $_ } @levels;
is($by_type{PWH}{price}, 350, 'PWH se serializa con el precio de la semana previa');
is($by_type{PWH}{anchor_time}, '2026-07-08T10:00:00-05:00', 'PWH inicia en la vela que genero el maximo');
is($by_type{PWL}{anchor_time}, '2026-07-08T10:00:00-05:00', 'PWL inicia en la vela que genero el minimo');
is($by_type{PDH}{label}, 'PDH', 'etiqueta diaria exacta');
ok(!exists $by_type{PML}, 'no inventa PML si el dataset no tiene mes previo');

my @month_levels = previous_high_low_levels(
    chart_timeframe      => '1m',
    reference_time       => '2026-07-01T12:00:00-05:00',
    base_candles         => \@monthly,
    chart_candles        => \@monthly,
    session_start_minute => $cme_session_start,
);
my %month_by_type = map { $_->{type} => $_ } @month_levels;
is($month_by_type{PML}{label}, 'PML', 'etiqueta mensual exacta cuando existe mes previo');

ok(mtf_level_allowed('D', 'D'), 'D se permite en D');
ok(!mtf_level_allowed('W', 'D'), 'D no se muestra sobre W');
ok(mtf_level_allowed('W', 'M'), 'M se permite sobre W');

my @detected = (
    c('2026-07-01T15:59:00-05:00', 1, 1),
    c('2026-07-01T17:00:00-05:00', 1, 1),
    c('2026-07-02T15:59:00-05:00', 1, 1),
    c('2026-07-02T17:00:00-05:00', 1, 1),
);
is(detect_session_start_minute(\@detected), $cme_session_start, 'detecta inicio de sesion por gaps del feed');

my @no_previous = (
    c('2026-07-13T09:00:00-05:00', 10, 5),
    c('2026-07-13T10:00:00-05:00', 11, 4),
);
my $empty = previous_period_extremes(
    period_tf            => 'D',
    reference_time       => '2026-07-13T10:00:00-05:00',
    base_candles         => \@no_previous,
    session_start_minute => $cme_session_start,
);
ok(!defined $empty, 'sin periodo anterior real no inventa niveles');

done_testing();
