package Market::Overlays::Liquidity;

use strict;
use warnings;
use utf8; # <-- Obligatorio para que Tk dibuje las flechas ↑ y ↓ correctamente

sub new {
    my ($class, %args) = @_;
    my $self = {
        canvas => $args{canvas},
        # Colores configurables para EQH y EQL según la Tabla 2
        color_eqh => $args{color_eqh} || '#FFD600', # Amarillo por defecto
        color_eql => $args{color_eql} || '#FFD600',
    };
    bless $self, $class;
    return $self;
}

sub render {
    my ($self, $scale, $liquidity_slice, $visibility) = @_;
    my $c = $self->{canvas};

    $c->delete('liquidity_overlay');

    return unless $liquidity_slice && @$liquidity_slice;

    $visibility //= {};
    my $show = sub { $visibility->{$_[0]} // 1 };

    my $width        = $c->width;
    my $height       = $c->height;
    my $min_val      = $scale->{min_val};
    my $max_val      = $scale->{max_val};
    my $visible_bars = $scale->{visible_bars};
    my $offset_frac  = $scale->{offset};

    my $range = $max_val - $min_val;
    return if $range <= 0;

    my $candle_width = $width / $visible_bars;

    for my $i (0 .. $#$liquidity_slice) {
        my $punto = $liquidity_slice->[$i];
        next if !$punto;

        # =========================================================================
        # 1. LÍNEAS ESTRUCTURALES Y ETIQUETAS BASE (BSL, SSL, EQH, EQL)
        # =========================================================================
        if (defined $punto->{state} && $punto->{state} ne 'none') {
            my $state = $punto->{state};

            # Determinar si este tipo debe mostrarse
            my $should_show =
                ($state eq 'swing_high' && $show->('bsl'))  ||
                ($state eq 'swing_low'  && $show->('ssl'))  ||
                (($state eq 'eqh' || $state eq 'eql') && $show->('eqh_eql'));

            if ($should_show) {
                my $level_price = $punto->{price};
                my $end_idx     = $punto->{end_index} // $i;

                my $x_start = ($i       - $offset_frac) * $candle_width + ($candle_width / 2);
                my $x_end   = ($end_idx - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y = $height - ((($level_price - $min_val) / $range) * $height);

                next if $y < -100 || $y > $height + 100;

                if ($state eq 'swing_high') {
                    $c->createLine($x_start, $y, $x_end, $y,
                        -dash => '.', -fill => '#FF5252', -width => 1.5,
                        -tags => ['liquidity_overlay']);
                    if (defined $punto->{resolution} && $punto->{resolution} eq 'active') {
                        $c->createText($x_end - 5, $y - 10,
                            -text => 'BSL', -fill => '#FF5252', -anchor => 'e',
                            -font => 'Helvetica 8 bold', -tags => ['liquidity_overlay']);
                    }
                }
                elsif ($state eq 'swing_low') {
                    $c->createLine($x_start, $y, $x_end, $y,
                        -dash => '.', -fill => '#00E676', -width => 1.5,
                        -tags => ['liquidity_overlay']);
                    if (defined $punto->{resolution} && $punto->{resolution} eq 'active') {
                        $c->createText($x_end - 5, $y + 10,
                            -text => 'SSL', -fill => '#00E676', -anchor => 'e',
                            -font => 'Helvetica 8 bold', -tags => ['liquidity_overlay']);
                    }
                }
                elsif ($state eq 'eqh') {
                    $c->createLine($x_start, $y, $x_end, $y,
                        -fill => $self->{color_eqh}, -width => 2.0,
                        -tags => ['liquidity_overlay']);
                    if (defined $punto->{resolution} && $punto->{resolution} eq 'active') {
                        $c->createText($x_end - 5, $y - 10,
                            -text => 'EQH', -fill => $self->{color_eqh}, -anchor => 'e',
                            -font => 'Helvetica 8 bold', -tags => ['liquidity_overlay']);
                    }
                }
                elsif ($state eq 'eql') {
                    $c->createLine($x_start, $y, $x_end, $y,
                        -fill => $self->{color_eql}, -width => 2.0,
                        -tags => ['liquidity_overlay']);
                    if (defined $punto->{resolution} && $punto->{resolution} eq 'active') {
                        $c->createText($x_end - 5, $y + 10,
                            -text => 'EQL', -fill => $self->{color_eql}, -anchor => 'e',
                            -font => 'Helvetica 8 bold', -tags => ['liquidity_overlay']);
                    }
                }
            }
        }

        # =========================================================================
        # 2. SWEEPS, GRABS, RUNS (Liquidity Events)
        # =========================================================================
        if ($show->('liq_events') && exists $punto->{events} && @{ $punto->{events} }) {
            for my $ev (@{ $punto->{events} }) {
                my $x_event = ($i - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y_event = $height - ((($ev->{price} - $min_val) / $range) * $height);

                next if $y_event < 0 || $y_event > $height;

                if ($ev->{type} eq 'sweep_up') {
                    $c->createText($x_event, $y_event - 15,
                        -text => 'SWEEP ↑', -fill => '#FF5252',
                        -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                }
                elsif ($ev->{type} eq 'sweep_down') {
                    $c->createText($x_event, $y_event + 15,
                        -text => 'SWEEP↓', -fill => '#00E676',
                        -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                }
                elsif ($ev->{type} eq 'grab_up' || $ev->{type} eq 'grab_down') {
                    $c->createText($x_event, $y_event - 15,
                        -text => 'LQ GRAB', -fill => '#FF9100',
                        -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                }
                elsif ($ev->{type} eq 'run_up' || $ev->{type} eq 'run_down') {
                    $c->createText($x_event, $y_event - 15,
                        -text => 'LQ RUN', -fill => '#2979FF',
                        -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                }
            }
        }
    }
}

1;