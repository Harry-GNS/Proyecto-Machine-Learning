package Market::Overlays::SMC_Structures;

use strict;
use warnings;
use utf8;

sub new {
    my ($class, %args) = @_;
    my $self = {
        canvas => $args{canvas},
    };
    bless $self, $class;
    return $self;
}

sub render {
    my ($self, $scale, $smc_slice) = @_;
    my $c = $self->{canvas};

    # Limpiar solo los dibujos correspondientes a este overlay
    $c->delete('smc_overlay');

    return unless $smc_slice && @$smc_slice;

    my $width  = $c->width;
    my $height = $c->height;
    my $min_val = $scale->{min_val};
    my $max_val = $scale->{max_val};
    my $visible_bars = $scale->{visible_bars};
    my $offset_frac = $scale->{offset}; 
    
    my $range = $max_val - $min_val;
    return if $range <= 0;

    my $candle_width = $width / $visible_bars;

    for my $i (0 .. $#$smc_slice) {
        my $punto = $smc_slice->[$i];
        next if !$punto;

        # ==================================================================
        # 1. RENDERIZAR FAIR VALUE GAPS (FVG) CON DESVANECIMIENTO PROGRESIVO
        # ==================================================================
        if (exists $punto->{fvgs} && @{$punto->{fvgs}}) {
            for my $fvg (@{$punto->{fvgs}}) {
                my $start_idx = $fvg->{start_idx};
                
                # Si el bloque ya fue mitigado, se recorta hasta esa vela. 
                # Si no, se extiende proyectado hacia la derecha.
                my $end_idx = $fvg->{mitigated_idx} // ($scale->{offset} + $visible_bars);
                
                next if $end_idx < $scale->{offset}; # No dibujar si quedó muy atrás

                my $x1 = ($start_idx - $offset_frac) * $candle_width + ($candle_width / 2);
                my $x2 = ($end_idx - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y1 = $height - ((($fvg->{top} - $min_val) / $range) * $height);
                my $y2 = $height - ((($fvg->{bottom} - $min_val) / $range) * $height);

                my $color = $fvg->{type} eq 'bullish_fvg' ? '#2979FF' : '#FF5252';
                
                # Caja Translúcida (Usamos stipple para simular opacidad en Perl/Tk)
                $c->createRectangle(
                    $x1, $y1, $x2, $y2,
                    -fill => $color, -outline => '', -stipple => 'gray25',
                    -tags => ['smc_overlay']
                );
                
                # Línea central punteada del FVG
                $c->createLine(
                    $x1, ($y1+$y2)/2, $x2, ($y1+$y2)/2,
                    -dash => '-', -fill => $color, -width => 1,
                    -tags => ['smc_overlay']
                );
            }
        }

        # ==================================================================
        # 2. RENDERIZAR EVENTOS DE RUPTURA (BOS y CHOCH)
        # ==================================================================
        if (exists $punto->{events} && @{$punto->{events}}) {
            for my $ev (@{$punto->{events}}) {
                my $origin_idx = $ev->{origin};
                my $break_idx  = $i;
                
                my $x_start = ($origin_idx - $offset_frac) * $candle_width + ($candle_width / 2);
                my $x_end   = ($break_idx - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y       = $height - ((($ev->{price} - $min_val) / $range) * $height);

                my $label = $ev->{type};
                my $color = $ev->{dir} eq 'bullish' ? '#2979FF' : '#FF5252'; # Azul al alza, Rojo a la baja

                $c->createLine($x_start, $y, $x_end, $y, -fill => $color, -width => 2, -tags => ['smc_overlay']);
                $c->createText(
                    ($x_start + $x_end) / 2, $y - 8,
                    -text => $label, -fill => $color, -font => 'Helvetica 9 bold', -tags => ['smc_overlay']
                );
            }
        }
        
        # ==================================================================
        # 3. ETIQUETAS ESTRUCTURALES HH, HL, LH, LL
        # ==================================================================
        if (defined $punto->{state} && $punto->{state} ne 'none') {
            my $x = ($i - $offset_frac) * $candle_width + ($candle_width / 2);
            my $y = $height - ((($punto->{price} - $min_val) / $range) * $height);
            
            my $offset_y = ($punto->{state} =~ /H$/) ? -15 : 15; 
            
            $c->createText(
                $x, $y + $offset_y,
                -text => $punto->{state}, -fill => '#d1d4dc', -font => 'Helvetica 8 bold',
                -tags => ['smc_overlay']
            );
        }
    }
}

1;