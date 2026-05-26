package Market::Panels::Scales;
use strict;
use warnings;


sub value_to_y {
    my ($self, $value) = @_;
    my $min = $self->{min_value};
    my $max = $self->{max_value};
    my $height = $self->{canvas_height};
    
    return $height if ($max - $min) == 0; # Prevenir división por cero
    
    # Transformación lineal: Y crece hacia abajo en un Canvas Tk
    my $y = $height - ((($value - $min) / ($max - $min)) * $height);
    return $y;
}
1;