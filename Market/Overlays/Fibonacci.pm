package Market::Overlays::Fibonacci;

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
    my ($self, $scale, $zz_slice, $start_idx_viewport, $visibility) = @_;
    my $c = $self->{canvas};

    # Limpiar dibujos anteriores
    $c->delete('fibonacci_overlay');

    $visibility //= {};
    return unless ($visibility->{fibonacci} // 1);
    return unless $zz_slice && @$zz_slice;
    $start_idx_viewport //= 0;

    my $width        = $c->width;
    my $height       = $c->height;
    my $min_val      = $scale->{min_val};
    my $max_val      = $scale->{max_val};
    my $visible_bars = $scale->{visible_bars};
    my $offset_frac  = $scale->{offset};

    my $range = $max_val - $min_val;
    return if $range <= 0;

    # 1. Encontrar el último dato de segmento completado de la serie visible
    my $last_data = undef;
    for my $i (reverse 0 .. $#$zz_slice) {
        if (defined $zz_slice->[$i]) {
            $last_data = $zz_slice->[$i];
            last;
        }
    }
    return unless defined $last_data;

    my @segments = @{ $last_data->{segments} // [] };
    return unless @segments;

    # Tomar el último tramo completado confirmado
    my $seg = $segments[-1];
    return unless defined $seg->{from_price} && defined $seg->{to_price};

    # 2. Calcular los niveles de Fibonacci del segmento
    my $p_start = $seg->{from_price};
    my $p_end   = $seg->{to_price};
    my $diff    = $p_end - $p_start;

    # Niveles estándar de retroceso de Fibonacci
    my @levels = (
        { ratio => 0.000, color => '#EF5350' }, # Rojo
        { ratio => 0.236, color => '#FF7043' }, # Naranja
        { ratio => 0.382, color => '#FFA726' }, # Naranja claro
        { ratio => 0.500, color => '#66BB6A' }, # Verde
        { ratio => 0.618, color => '#26A69A' }, # Verde azulado (Golden Ratio)
        { ratio => 0.786, color => '#29B6F6' }, # Azul claro
        { ratio => 1.000, color => '#AB47BC' }  # Púrpura
    );

    # Calcular posiciones horizontales
    my $rel_from = $seg->{from_bar} - $start_idx_viewport;
    my $rel_to   = $seg->{to_bar}   - $start_idx_viewport;

    my $candle_width = $width / $visible_bars;
    my $x_start = ($rel_from - $offset_frac) * $candle_width + ($candle_width / 2);
    my $x_end   = ($rel_to   - $offset_frac) * $candle_width + ($candle_width / 2);

    # Dibujar la línea de tendencia diagonal del tramo
    my $y_start_trend = $scale->value_to_y($p_start);
    my $y_end_trend   = $scale->value_to_y($p_end);
    $c->createLine($x_start, $y_start_trend, $x_end, $y_end_trend,
        -fill  => '#78909C',
        -width => 1.5,
        -dash  => '.',
        -tags  => ['fibonacci_overlay']
    );

    # 3. Dibujar cada nivel horizontal extendido
    for my $lvl (@levels) {
        my $ratio = $lvl->{ratio};
        my $color = $lvl->{color};
        
        my $price = $p_start + $diff * $ratio;
        my $y_pos = $scale->value_to_y($price);

        # Línea horizontal del nivel extendida hasta el final derecho del gráfico
        $c->createLine(
            $x_start, $y_pos, $width, $y_pos,
            -fill => $color,
            -dash => '-',
            -tags => ['fibonacci_overlay']
        );

        # Etiqueta de texto descriptiva
        my $label_text = sprintf("Fib %.3f (%.2f)", $ratio, $price);
        $c->createText(
            $x_start + 10, $y_pos - 8,
            -text   => $label_text,
            -fill   => $color,
            -font   => 'Helvetica 8 bold',
            -anchor => 'w',
            -tags   => ['fibonacci_overlay']
        );
    }

    $c->lower('fibonacci_overlay');
}

1;
