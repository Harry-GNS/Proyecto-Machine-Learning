#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Test::More;

use Market::Indicators::SMC_Structures;
use Market::Overlays::SMC_Structures;

sub candle {
    my ($i, $high, $low) = @_;
    return {
        time   => sprintf('2026-06-29T00:%02d:00', $i),
        open   => ($high + $low) / 2,
        high   => $high,
        low    => $low,
        close  => ($high + $low) / 2,
        volume => 100,
    };
}

my $candles = [
    candle(0,  8, 6.0),
    candle(1, 10, 6.0),
    candle(2,  9, 6.0),
    candle(3,  9, 6.0),
    candle(4,  9, 5.0),
    candle(5, 15, 5.5),
    candle(6, 11, 5.2),
    candle(7, 10, 4.0),
    candle(8, 10, 4.0),
    candle(9, 12, 4.5),
    candle(10,12, 4.0),
];

my $pivots = [
    {
        id => 'H_OLD', kind => 'high', scope => 'external', index => 1,
        time => $candles->[1]{time}, price => 10, confirmed_at => 3,
        label => 'HH', label_scope => 'external',
    },
    {
        id => 'L_CURRENT', kind => 'low', scope => 'external', index => 4,
        time => $candles->[4]{time}, price => 5, confirmed_at => 6,
        label => 'HL', label_scope => 'external',
    },
    {
        id => 'H_CURRENT', kind => 'high', scope => 'external', index => 6,
        time => $candles->[6]{time}, price => 11, confirmed_at => 8,
        label => 'LH', label_scope => 'external',
    },
];

my $bullish_event = {
    id => 'BOS_UP', type => 'BOS', scope => 'external',
    direction => 'bullish', confirmation_index => 5,
};
my $bearish_event = {
    id => 'CHOCH_DOWN', type => 'CHOCH', scope => 'external',
    direction => 'bearish', confirmation_index => 9,
};

my $on_high_confirmation = Market::Indicators::SMC_Structures::_build_trailing_extremes(
    $candles, $pivots, [$bullish_event, $bearish_event], 8,
);
is($on_high_confirmation->{source_high_pivot_id}, 'H_OLD',
   'new swing reset is not drawn before SMC processes its confirmation candle');
is($on_high_confirmation->{top}, 15,
   'confirmation candle still displays the previously trailing upper extreme');
is($on_high_confirmation->{structural_bias}, 'bullish',
   'only structures confirmed before the current drawing pass affect its bias');

my $on_bearish_confirmation = Market::Indicators::SMC_Structures::_build_trailing_extremes(
    $candles, $pivots, [$bullish_event, $bearish_event], 9,
);
is($on_bearish_confirmation->{source_high_pivot_id}, 'H_CURRENT',
   'confirmed swing reset becomes visible on the following candle');
is($on_bearish_confirmation->{top}, 12,
   'following candle advances the newly reset trailing upper extreme');
is($on_bearish_confirmation->{structural_bias}, 'bullish',
   'new structural bias is not drawn before its confirmation pass completes');

my $trailing = Market::Indicators::SMC_Structures::_build_trailing_extremes(
    $candles, $pivots, [$bullish_event, $bearish_event], 10,
);

ok($trailing, 'builds one current trailing state');
is($trailing->{source_high_pivot_id}, 'H_CURRENT',
   'latest confirmed external high resets the upper trailing extreme');
is($trailing->{source_low_pivot_id}, 'L_CURRENT',
   'latest confirmed external low resets the lower trailing extreme');
is($trailing->{top}, 12,
   'upper trailing follows only a new absolute high after its structural reset');
is($trailing->{bottom}, 4,
   'lower trailing follows only a new absolute low after its structural reset');
is($trailing->{last_top_index}, 10,
   'equal trailing high moves the origin to the latest equal touch');
is($trailing->{last_bottom_index}, 10,
   'equal trailing low moves the origin to the latest equal touch');
is($trailing->{structural_bias}, 'bearish',
   'last confirmed external BOS or CHOCH defines swing bias');
is($trailing->{high_classification}, 'strong_high',
   'bearish swing bias classifies the trailing high as Strong High');
is($trailing->{low_classification}, 'weak_low',
   'bearish swing bias classifies the trailing low as Weak Low');
is($trailing->{source_structure_event_id}, 'CHOCH_DOWN',
   'classification links to the latest confirmed swing structure');
ok(!scalar(grep { exists $_->{strength_class} } @$pivots),
   'calculation does not annotate historical pivots Strong/Weak');

my $bullish_trailing = Market::Indicators::SMC_Structures::_build_trailing_extremes(
    $candles, $pivots, [$bullish_event], 10,
);
is($bullish_trailing->{high_classification}, 'weak_high',
   'bullish swing bias classifies the trailing high as Weak High');
is($bullish_trailing->{low_classification}, 'strong_low',
   'bullish swing bias classifies the trailing low as Strong Low');

my $neutral_trailing = Market::Indicators::SMC_Structures::_build_trailing_extremes(
    $candles, $pivots, [], 10,
);
is($neutral_trailing->{high_classification}, 'weak_high',
   'neutral initial bias leaves the trailing high Weak');
is($neutral_trailing->{low_classification}, 'weak_low',
   'neutral initial bias leaves the trailing low Weak');

my $shapes = Market::Overlays::SMC_Structures->build_shapes(
    pivots            => $pivots,
    structures        => [],
    trailing_extremes => $trailing,
    fvgs              => [],
    fib_sets          => [],
    premium_discount_zones => [],
    max_visible_index => 10,
    timeframe         => '1m',
);
my @strong_weak = grep {
    ($_->{color_role} // '') =~ /^(?:strong|weak)_(?:high|low)$/
} @$shapes;

is(scalar @strong_weak, 4,
   'overlay emits exactly two current lines and two current labels');
is(scalar(grep { ($_->{kind} // '') eq 'line' } @strong_weak), 2,
   'overlay keeps exactly one upper and one lower line');
is(scalar(grep { ($_->{kind} // '') eq 'label' } @strong_weak), 2,
   'overlay keeps exactly one upper and one lower label');
ok(!scalar(grep { ($_->{id} // '') =~ /^PV_SW_/ } @$shapes),
   'overlay emits no historical pivot Strong/Weak objects');
ok(!scalar(grep { ($_->{x2_index} // -1) != 10 } @strong_weak),
   'all current Strong/Weak objects end at the current candle');
is_deeply(
    [ sort map { $_->{text} } grep { ($_->{kind} // '') eq 'label' } @strong_weak ],
    ['Strong High', 'Weak Low'],
    'only labels for the current bearish pair are visible',
);
is_deeply(
    [ sort map { $_->{source_id} } grep { ($_->{kind} // '') eq 'line' } @strong_weak ],
    ['H_CURRENT', 'L_CURRENT'],
    'current lines remain tied to the latest confirmed structural swings',
);

done_testing();
