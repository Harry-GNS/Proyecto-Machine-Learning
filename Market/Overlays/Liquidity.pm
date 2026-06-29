package Market::Overlays::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        canvas => $args{canvas},
    };
    bless $self, $class;
    return $self;
}

sub render {
    my ($self, $scale, $liquidity_slice) = @_;
    my $c = $self->{canvas};

    $c->delete('liquidity_overlay');

    return unless $liquidity_slice && @$liquidity_slice;

    my $width  = $c->width;
    my $height = $c->height;
    
    my $min_val = $scale->{min_val};
    my $max_val = $scale->{max_val};
    my $visible_bars = $scale->{visible_bars};
    my $offset_frac = $scale->{offset}; 
    
    my $range = $max_val - $min_val;
    return if $range <= 0;

    my $candle_width = $width / $visible_bars;

    for my $i (0 .. $#$liquidity_slice) {
        my $punto = $liquidity_slice->[$i];
        next if !$punto;

        # 1. RENDERIZADO DE LÍNEAS DE LIQUIDEZ RE CORTADAS POR LA MÁQUINA DE ESTADOS
        if (defined $punto->{state} && $punto->{state} ne 'none') {
            my $level_price = $punto->{price};
            my $end_idx = $punto->{end_index} // $i;

            # Calcular posiciones en píxeles basándose en los índices reales del rebanado visible
            my $x_start = ($i - $offset_frac) * $candle_width + ($candle_width / 2);
            my $x_end   = ($end_idx - $offset_frac) * $candle_width + ($candle_width / 2);
            
            my $y = $height - ((($level_price - $min_val) / $range) * $height);
            
            next if $y < -100 || $y > $height + 100; # No dibujar si está fuera de pantalla

            if ($punto->{state} eq 'swing_high') {
                # Línea de BSL (Roja) [cite: 104]
                $c->createLine(
                    $x_start, $y, $x_end, $y,
                    -dash => '.', -fill => '#FF5252', -width => 1.5,
                    -tags => ['liquidity_overlay']
                );
                if ($punto->{resolution} eq 'active') {
                    $c->createText(
                        $x_end - 5, $y - 10,
                        -text => 'BSL', -fill => '#FF5252', -anchor => 'e', -font => 'Helvetica 8 bold',
                        -tags => ['liquidity_overlay']
                    );
                }
            } elsif ($punto->{state} eq 'swing_low') {
                # Línea de SSL (Verde) [cite: 104]
                $c->createLine(
                    $x_start, $y, $x_end, $y,
                    -dash => '.', -fill => '#00E676', -width => 1.5,
                    -tags => ['liquidity_overlay']
                );
                if ($punto->{resolution} eq 'active') {
                    $c->createText(
                        $x_end - 5, $y + 10,
                        -text => 'SSL', -fill => '#00E676', -anchor => 'e', -font => 'Helvetica 8 bold',
                        -tags => ['liquidity_overlay']
                    );
                }
            }
        }

        # 2. RENDERIZADO DE ETIQUETAS DE EVENTOS DE RESOLUCIÓN DE LIQUIDEZ 
        if (exists $punto->{events} && @{$punto->{events}}) {
            for my $ev (@{$punto->{events}}) {
                my $x_event = ($i - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y_event = $height - ((($ev->{price} - $min_val) / $range) * $height);

                next if $y_event < 0 || $y_event > $height;

                if ($ev->{type} eq 'sweep_up') {
                    $c->createText($x_event, $y_event - 15, -text => 'SWEEP ↑', 
                        -fill => '#FF5252', -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                } 
                elsif ($ev->{type} eq 'sweep_down') {
                    $c->createText($x_event, $y_event + 15, -text => 'SWEEP ↓', 
                        -fill => '#00E676', -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']);
                } 
                elsif ($ev->{type} eq 'grab_up' || $ev->{type} eq 'grab_down') {
                    $c->createText($x_event, $y_event - 15, -text => 'LQ GRAB', 
                        -fill => '#FF9100', -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']); # Naranja [cite: 105]
                } 
                elsif ($ev->{type} eq 'run_up' || $ev->{type} eq 'run_down') {
                    $c->createText($x_event, $y_event - 15, -text => 'LQ RUN', 
                        -fill => '#2979FF', -font => 'Helvetica 9 bold', -tags => ['liquidity_overlay']); # Azul [cite: 105]
                }
            }
        }
    }
}

1;