package Market::MarketData;

use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = {
        data          => {},       # Hash para almacenar { '1m' => [], '5m' => [], ... }
        current_tf    => '1m',     # Temporalidad por defecto
    };
    bless $self, $class;
    return $self;
}

sub add_candle {
    my ($self, $candle) = @_;
    # Asumimos que la entrada principal siempre llega en la menor temporalidad (ej: 1m)
    push @{ $self->{data}->{'1m'} }, $candle;
}


sub build_tf_candles {
    my ($self, $target_tf) = @_;
    
    # 1. Determinar el factor de agrupación (N)
    # Asumimos que la temporalidad base en la memoria es '1m'.
    # Extraemos el valor numérico de la cadena (ej. de '5m' extraemos 5)
    my ($n) = $target_tf =~ /(\d+)/; 
    
    # Validamos que tengamos datos base de 1m para procesar
    return unless exists $self->{data}->{'1m'} && @{ $self->{data}->{'1m'} } > 0;
    
    my $base_data = $self->{data}->{'1m'};
    my @aggregated_data;
    my $total_candles = scalar @$base_data;
    
    # 2. Iterar sobre el vector base dando "saltos" del tamaño de N
    for (my $i = 0; $i < $total_candles; $i += $n) {
        
        # Calcular el índice final del bloque actual
        # Si estamos al final y no hay N velas exactas, cerramos con la última disponible
        my $end_idx = $i + $n - 1;
        $end_idx = $total_candles - 1 if $end_idx >= $total_candles;
        
        # 3. Aplicar las ecuaciones: Open, Close y Timestamp son O(1)
        my $open      = $base_data->[$i]->{open};
        my $close     = $base_data->[$end_idx]->{close};
        my $timestamp = $base_data->[$i]->{timestamp};
        
        # Inicializar High, Low y Volume para la reducción
        my $high   = $base_data->[$i]->{high};
        my $low    = $base_data->[$i]->{low};
        my $volume = 0;
        
        # 4. Operaciones iterativas de reducción en O(N) para High, Low y Volume
        for my $j ($i .. $end_idx) {
            my $candle = $base_data->[$j];
            
            $high = $candle->{high} if $candle->{high} > $high;
            $low  = $candle->{low}  if $candle->{low}  < $low;
            $volume += $candle->{volume};
        }
        
        # 5. Insertar la nueva vela agregada al final de nuestro nuevo arreglo
        push @aggregated_data, {
            timestamp => $timestamp,
            open      => $open,
            high      => $high,
            low       => $low,
            close     => $close,
            volume    => $volume,
        };
    }
    
    # 6. Almacenar el nuevo vector de la temporalidad en el hash central
    $self->{data}->{$target_tf} = \@aggregated_data;
}


sub build_timeframes {
    my ($self) = @_;
    
    # Construimos las temporalidades requeridas en la arquitectura (ej. 5m y 15m)
    $self->build_tf_candles('5m');
    $self->build_tf_candles('15m');
    
    # Setear la vista inicial (por defecto 1m, o la que consideres)
    $self->set_timeframe('1m');
}

sub set_timeframe {
    my ($self, $tf) = @_;
    # Afecta qué datos se usan al seleccionar la temporalidad activa
    if (exists $self->{data}->{$tf}) {
        $self->{current_tf} = $tf;
    } else {
        warn "La temporalidad $tf no ha sido construida aún.\n";
    }
}

sub _active_array {
    my ($self) = @_;
    # Devuelve el array activo según timeframe. Abstracción interna clave.
    return $self->{data}->{ $self->{current_tf} };
}

sub get_slice {
    my ($self, $start, $end) = @_;
    my $array_ref = $self->_active_array();
    
    # Protecciones de límites para evitar errores de índice
    $start = 0 if $start < 0;
    $end = $#{$array_ref} if $end > $#{$array_ref};
    
    # Retorna un subconjunto de velas
    return [ @{$array_ref}[$start .. $end] ];
}

sub size {
    my ($self) = @_;
    my $array_ref = $self->_active_array();
    return scalar @{$array_ref};
}

sub last_candle {
    my ($self) = @_;
    my $array_ref = $self->_active_array();
    return $array_ref->[-1] if @{$array_ref};
    return undef;
}

sub get_timestamp {
    my ($self, $index) = @_;
    my $array_ref = $self->_active_array();
    return $array_ref->[$index]->{timestamp} if defined $array_ref->[$index];
    return undef;
}

sub last_index {
    my ($self) = @_;
    my $array_ref = $self->_active_array();
    
    # Si el arreglo no existe o está vacío, retornamos undef
    return undef unless $array_ref && @$array_ref;
    
    # En Perl, $#array devuelve el último índice válido (N - 1)
    return $#{$array_ref}; 
}

sub get_candle {
    my ($self, $index) = @_;
    my $array_ref = $self->_active_array();
    
    # Protecciones para evitar que el indicador pida un índice fuera de rango
    return undef if !defined $index || $index < 0 || $index > $#{$array_ref};
    
    return $array_ref->[$index];
}

1;