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
    my ($self, $scale, $smc_slice, $start_idx_viewport) = @_;
    my $c = $self->{canvas};

    # Limpiar dibujos anteriores
    $c->delete('smc_overlay');

    return unless $smc_slice && @$smc_slice;
    $start_idx_viewport //= 0;

    my $width  = $c->width;
    my $height = $c->height;
    my $min_val = $scale->{min_val};
    my $max_val = $scale->{max_val};
    my $visible_bars = $scale->{visible_bars};
    my $offset_frac = $scale->{offset}; 
    
    my $range = $max_val - $min_val;
    return if $range <= 0;

    my $candle_width = $width / $visible_bars;

    # 1. Recopilar TODOS los FVGs a dibujar 
    # (Los históricos que venían activos + Los nuevos de este segmento)
    my @fvgs_to_draw;
    if (exists $smc_slice->[0]->{active_fvgs}) {
        push @fvgs_to_draw, @{$smc_slice->[0]->{active_fvgs}};
    }

    for my $i (0 .. $#$smc_slice) {
        my $punto = $smc_slice->[$i];
        next if !$punto;

        # Agregar FVGs nuevos que nacen dentro de esta pantalla
        if (exists $punto->{fvgs} && @{$punto->{fvgs}}) {
            push @fvgs_to_draw, @{$punto->{fvgs}};
        }

        # ==================================================================
        # 2. RENDERIZAR EVENTOS DE RUPTURA (BOS y CHOCH)
        # ==================================================================
        if (exists $punto->{events} && @{$punto->{events}}) {
            for my $ev (@{$punto->{events}}) {
                my $origin_idx = $ev->{origin};
                
                # CORRECCIÓN: Convertir índices absolutos a relativos a la pantalla
                my $rel_origin = $origin_idx - $start_idx_viewport;
                my $rel_break  = $i;
                
                my $x_start = ($rel_origin - $offset_frac) * $candle_width + ($candle_width / 2);
                my $x_end   = ($rel_break - $offset_frac) * $candle_width + ($candle_width / 2);
                my $y       = $height - ((($ev->{price} - $min_val) / $range) * $height);

                my $label = $ev->{type};
                my $color = $ev->{dir} eq 'bullish' ? '#2979FF' : '#FF5252';

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

    # ==================================================================
    # 4. RENDERIZAR FAIR VALUE GAPS (FVG) ESTILO TRADINGVIEW (EXTENDIDO)
    # ==================================================================
    for my $fvg (@fvgs_to_draw) {
        my $start_idx = $fvg->{start_idx};
        my $rel_start = $start_idx - $start_idx_viewport;
        
        my $x1 = ($rel_start - $offset_frac) * $candle_width + ($candle_width / 2);
        my $x2;

        # LÓGICA DE EXTENSIÓN "EXTEND RIGHT"
        if (defined $fvg->{mitigated_idx}) {
            my $rel_end = $fvg->{mitigated_idx} - $start_idx_viewport;
            
            # No dibujar si el bloque ya fue superado y quedó en el pasado oculto
            next if $rel_end < $offset_frac; 
            
            $x2 = ($rel_end - $offset_frac) * $candle_width + ($candle_width / 2);
        } else {
            # Si NO está mitigado, se proyecta "infinitamente" hacia el futuro 
            # (sobrepasamos el margen derecho de la pantalla con un valor muy alto)
            $x2 = $width + 2000; 
        }

        my $y1 = $height - ((($fvg->{top} - $min_val) / $range) * $height);
        my $y2 = $height - ((($fvg->{bottom} - $min_val) / $range) * $height);

        my $color = $fvg->{type} eq 'bullish_fvg' ? '#2979FF' : '#FF5252';
        
        # Caja Translúcida (agregamos '-outline => $color' para darle el borde definido de TV)
        $c->createRectangle(
            $x1, $y1, $x2, $y2,
            -fill => $color, -outline => $color, -stipple => 'gray25',
            -tags => ['smc_overlay']
        );
        
        # Línea central punteada del FVG (también extendida)
        $c->createLine(
            $x1, ($y1+$y2)/2, $x2, ($y1+$y2)/2,
            -dash => '-', -fill => $color, -width => 1,
            -tags => ['smc_overlay']
        );
    
    # Empuja toda la capa SMC hacia el fondo, permitiendo que 
    # las velas y mechas del PricePanel se vean nítidas por encima.
    $c->lower('smc_overlay');
    }
}

1;