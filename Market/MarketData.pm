package Market::MarketData;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        # Almacenamiento independiente por cada dimensión temporal [cite: 93]
        data       => { '1m' => [], '5m' => [], '15m' => [] }, 
        current_tf => '1m', 
    };
    bless $self, $class;
    return $self;
}

sub add_candle {
    my ($self, $candle) = @_;
    # La ingesta de datos crudos siempre entra por defecto a la escala de 1m [cite: 104]
    push @{$self->{data}->{'1m'}}, $candle;
}

# Abstracción interna clave: dirige a todos los otros métodos a leer la matriz correcta [cite: 114]
sub _active_array {
    my ($self) = @_;
    my $tf = $self->{current_tf};
    return $self->{data}->{$tf};
}

sub get_candle {
    my ($self, $index) = @_;
    return $self->_active_array()->[$index];
}

sub size {
    my ($self) = @_;
    return scalar @{$self->_active_array()};
}

# Algoritmo de Downsampling: Transforma N velas de 1m en 1 vela superior [cite: 106]
sub build_tf_candles {
    my ($self, $target_tf) = @_;
    my $source_data = $self->{data}->{'1m'};
    
    my $group_size = 1;
    $group_size = 5  if $target_tf eq '5m';
    $group_size = 15 if $target_tf eq '15m';
    
    return if $group_size == 1;

    my @aggregated;
    my $total = scalar @$source_data;
    
    for (my $i = 0; $i < $total; $i += $group_size) {
        my $chunk_end = $i + $group_size - 1;
        $chunk_end = $total - 1 if $chunk_end >= $total; # Protección de límite de array
        
        my $first = $source_data->[$i];
        my $last  = $source_data->[$chunk_end];
        
        # Inicializamos los topes con la primera vela del grupo
        my $high = $first->{high};
        my $low  = $first->{low};
        my $volume = 0;
        
        # Buscar máximos, mínimos y acumular volumen en la porción de tiempo
        for my $j ($i .. $chunk_end) {
            my $c = $source_data->[$j];
            $high = $c->{high} if $c->{high} > $high;
            $low  = $c->{low}  if $c->{low}  < $low;
            $volume += $c->{volume};
        }
        
        push @aggregated, {
            timestamp => $first->{timestamp}, # El tiempo ancla es el inicio del periodo
            open      => $first->{open},
            high      => $high,
            low       => $low,
            close     => $last->{close},
            volume    => $volume,
        };
    }
    
    # Asignamos el nuevo tensor agrupado a su llave correspondiente
    $self->{data}->{$target_tf} = \@aggregated;
}

sub build_timeframes {
    my ($self) = @_;
    $self->build_tf_candles('5m');
    $self->build_tf_candles('15m');
}

sub set_timeframe {
    my ($self, $tf) = @_;
    if (exists $self->{data}->{$tf}) {
        $self->{current_tf} = $tf;
    }
}

1;