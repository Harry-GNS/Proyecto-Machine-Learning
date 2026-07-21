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
    my ($self, $scale, $smc_slice, $start_idx_viewport, $visibility) = @_;
    my $c = $self->{canvas};

    # Limpiar dibujos anteriores
    $c->delete('smc_overlay');

    return unless $smc_slice && @$smc_slice;
    $start_idx_viewport //= 0;

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

    # Dibujaremos dos capas: 'internal' y 'swing'
    my @layers = qw(internal swing);

    for my $layer (@layers) {
        # 1. Recopilar FVGs a dibujar para esta capa
        my @fvgs_to_draw;
        if ($show->('fvg') && exists $smc_slice->[0]->{$layer}->{active_fvgs}) {
            push @fvgs_to_draw, @{ $smc_slice->[0]->{$layer}->{active_fvgs} };
        }

        # 2. Recopilar Order Blocks a dibujar para esta capa
        my @obs_to_draw;
        my $show_ob_key = ($layer eq 'swing') ? 'swing_ob' : 'internal_ob';
        if ($show->($show_ob_key) && exists $smc_slice->[0]->{$layer}->{active_obs}) {
            push @obs_to_draw, @{ $smc_slice->[0]->{$layer}->{active_obs} };
        }

        # Escanear el slice visible
        for my $i (0 .. $#$smc_slice) {
            my $punto = $smc_slice->[$i]->{$layer};
            next if !$punto;

            # FVGs creados durante el slice
            if ($show->('fvg') && exists $punto->{fvgs} && @{ $punto->{fvgs} }) {
                push @fvgs_to_draw, @{ $punto->{fvgs} };
            }

            # OBs creados durante el slice
            if ($show->($show_ob_key) && exists $punto->{obs} && @{ $punto->{obs} }) {
                push @obs_to_draw, @{ $punto->{obs} };
            }

            # ==================================================================
            # RENDERIZADO DE EVENTOS DE RUPTURA (BOS y CHOCH)
            # ==================================================================
            if ($show->('bos_choch') && exists $punto->{events} && @{ $punto->{events} }) {
                for my $ev (@{ $punto->{events} }) {
                    my $rel_origin = $ev->{origin} - $start_idx_viewport;
                    my $rel_break  = $i;

                    my $x_start = $scale->index_to_center_x($rel_origin);
                    my $x_end   = $scale->index_to_center_x($rel_break);
                    my $y       = $scale->value_to_y($ev->{price});

                    my $color;
                    if ($layer eq 'swing') {
                        $color = $ev->{dir} eq 'bullish' ? '#2979FF' : '#FF5252'; # colores intensos
                    } else {
                        $color = $ev->{dir} eq 'bullish' ? '#448AFF' : '#FF8A80'; # colores mas suaves para internos
                    }

                    my $dash = ($layer eq 'swing') ? undef : '-'; # solid para swing, dashed para internal
                    my $width_line = ($layer eq 'swing') ? 2 : 1;
                    my $font = ($layer eq 'swing') ? 'Helvetica 9 bold' : 'Helvetica 8';

                    $c->createLine($x_start, $y, $x_end, $y,
                        -dash => $dash, -fill => $color, -width => $width_line, -tags => ['smc_overlay']);
                    
                    my $label_text = ($layer eq 'swing') ? "Swing $ev->{type}" : "Int $ev->{type}";
                    $c->createText(($x_start + $x_end) / 2, $y - 8,
                        -text => $label_text, -fill => $color,
                        -font => $font, -tags => ['smc_overlay']);
                }
            }

            # ==================================================================
            # RENDERIZADO DE ETIQUETAS ESTRUCTURALES HH, HL, LH, LL
            # ==================================================================
            if ($show->('structure_labels')
                && defined $punto->{state} && $punto->{state} ne 'none')
            {
                my $x = $scale->index_to_center_x($i);
                my $y = $scale->value_to_y($punto->{price});
                
                # Offset vertical y estilo de fuente
                my $oy;
                my $font;
                my $color;
                
                if ($layer eq 'swing') {
                    $oy = ($punto->{state} =~ /H$/) ? -18 : 18;
                    $font = 'Helvetica 8 bold';
                    $color = '#131722'; # color oscuro claro
                } else {
                    $oy = ($punto->{state} =~ /H$/) ? -10 : 10;
                    $font = 'Helvetica 7';
                    $color = '#6B7280'; # gris mas claro
                }

                my $label_text = ($layer eq 'swing') ? "s$punto->{state}" : "i$punto->{state}";
                $c->createText($x, $y + $oy,
                    -text => $label_text, -fill => $color,
                    -font => $font, -tags => ['smc_overlay']);
            }
        }

        # ==================================================================
        # RENDERIZADO DE FAIR VALUE GAPS (FVG)
        # ==================================================================
        if ($show->('fvg')) {
            for my $fvg (@fvgs_to_draw) {
                my $rel_start = $fvg->{start_idx} - $start_idx_viewport;
                my $x1 = $scale->index_to_center_x($rel_start);
                my $x2;

                my $is_mitigated = defined $fvg->{mitigated_idx};

                if ($is_mitigated) {
                    my $rel_end = $fvg->{mitigated_idx} - $start_idx_viewport;
                    next if $rel_end < $offset_frac;
                    $x2 = $scale->index_to_center_x($rel_end);
                } else {
                    $x2 = $width + 100;
                }

                my $y1 = $scale->value_to_y($fvg->{top});
                my $y2 = $scale->value_to_y($fvg->{bottom});

                my $color;
                my $stipple;
                if ($layer eq 'swing') {
                    $color = $fvg->{type} eq 'bullish_fvg' ? '#A2E8DD' : '#FFCDD2';
                    $stipple = 'gray25';
                } else {
                    $color = $fvg->{type} eq 'bullish_fvg' ? '#E0F2F1' : '#FFE0B2';
                    $stipple = 'gray12';
                }

                my $outline_dash = ($layer eq 'swing') ? undef : '-';
                
                # Regla de mitigación: atenuar canales obsoletos
                if ($is_mitigated) {
                    $color = '#E5E7EB'; # Gris muy tenue para light mode
                    $outline_dash = '.'; 
                    $stipple = undef;
                }

                $c->createRectangle($x1, $y1, $x2, $y2,
                    -fill => $color, -outline => $color, -stipple => $stipple,
                    -tags => ['smc_overlay']);
                
                $c->createLine($x1, ($y1+$y2)/2, $x2, ($y1+$y2)/2,
                    -dash => $outline_dash, -fill => $color, -width => 1,
                    -tags => ['smc_overlay']);
            }
        }

        # ==================================================================
        # RENDERIZADO DE ORDER BLOCKS (OB)
        # ==================================================================
        if ($show->($show_ob_key)) {
            for my $ob (@obs_to_draw) {
                my $rel_start = $ob->{start_idx} - $start_idx_viewport;
                my $x1 = $scale->index_to_center_x($rel_start);
                my $x2;

                my $is_mitigated = defined $ob->{mitigated_idx};

                if ($is_mitigated) {
                    my $rel_end = $ob->{mitigated_idx} - $start_idx_viewport;
                    next if $rel_end < $offset_frac;
                    $x2 = $scale->index_to_center_x($rel_end);
                } else {
                    $x2 = $width + 100;
                }

                my $y1 = $scale->value_to_y($ob->{high});
                my $y2 = $scale->value_to_y($ob->{low});

                my $fill_color;
                my $outline_color;
                my $stipple = 'gray25';
                my $outline_dash = ($layer eq 'swing') ? undef : '-';

                if ($ob->{bias} eq 'bullish') {
                    $fill_color    = ($layer eq 'swing') ? '#B2DFDB' : '#E0F2F1';
                    $outline_color = ($layer eq 'swing') ? '#26A69A' : '#4DB6AC';
                } else {
                    $fill_color    = ($layer eq 'swing') ? '#FFCDD2' : '#FFE0B2';
                    $outline_color = ($layer eq 'swing') ? '#EF5350' : '#FFB74D';
                }

                if ($is_mitigated) {
                    $fill_color = '#E5E7EB';
                    $outline_color = '#9CA3AF';
                    $stipple = undef;
                    $outline_dash = '.';
                }

                $c->createRectangle($x1, $y1, $x2, $y2,
                    -fill    => $fill_color,
                    -outline => $outline_color,
                    -dash    => $outline_dash,
                    -stipple => $stipple,
                    -tags    => ['smc_overlay']
                );
            }
        }
    }

    $c->lower('smc_overlay');
}

1;