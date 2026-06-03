package Market::MarketData;

use strict;
use warnings;
use POSIX qw(floor);

sub new {
    my ($class) = @_;
    my $self = {
        data       => {},
        current_tf => '1m',
    };
    bless $self, $class;
    return $self;
}

sub add_candle {
    my ($self, $candle) = @_;
    push @{ $self->{data}->{'1m'} }, $candle;
}

# ================================================================
# build_tf_candles — agrupación por tiempo real (NO por índice)
#
# Para cada vela de 1m se calcula su "bucket" temporal:
#   bucket = floor(minuto_del_día / N) * N
# donde minuto_del_día = hora*60 + minuto
# y N es el número de minutos de la temporalidad objetivo.
#
# Esto garantiza que, por ejemplo en 5m:
#   00:00–00:04 → bucket 0  (vela 00:00)
#   00:05–00:09 → bucket 5  (vela 00:05)
#   etc.
# y que el bucket 0 de cada día siempre coincide con la primera
# vela real de ese día (pivote), eliminando el desfase.
# ================================================================
sub build_tf_candles {
    my ($self, $target_tf) = @_;

    my ($n) = $target_tf =~ /(\d+)/;
    return unless $n && $n > 0;
    return unless exists $self->{data}->{'1m'} && @{ $self->{data}->{'1m'} } > 0;

    my $base_data = $self->{data}->{'1m'};
    my @aggregated;
    my %bucket_map;   # "YYYY-MM-DD:bucket" → índice en @aggregated

    for my $candle (@$base_data) {
        my $ts = $candle->{timestamp};

        # Extraer fecha y hora del timestamp (soporta offset timezone)
        my ($date, $hour, $min);
        if ($ts =~ /(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})/) {
            $date = $1;
            $hour = $2 + 0;
            $min  = $3 + 0;
        } else {
            next;  # timestamp no reconocido
        }

        my $day_minute = $hour * 60 + $min;
        my $bucket     = floor($day_minute / $n) * $n;
        my $key        = "$date:$bucket";

        if (!exists $bucket_map{$key}) {
            # Primera vela del bucket → inicializar
            my $bucket_hour = floor($bucket / 60);
            my $bucket_min  = $bucket % 60;
            my $bucket_ts   = sprintf("%sT%02d:%02d:00", $date, $bucket_hour, $bucket_min);
            # Preservar offset de zona horaria si existe
            if ($ts =~ /([-+]\d{2}:\d{2})$/) {
                $bucket_ts .= $1;
            }

            push @aggregated, {
                timestamp => $bucket_ts,
                open      => $candle->{open},
                high      => $candle->{high},
                low       => $candle->{low},
                close     => $candle->{close},
                volume    => $candle->{volume},
            };
            $bucket_map{$key} = $#aggregated;
        } else {
            # Vela adicional en el mismo bucket → actualizar
            my $idx = $bucket_map{$key};
            $aggregated[$idx]->{high}   = $candle->{high}   if $candle->{high}   > $aggregated[$idx]->{high};
            $aggregated[$idx]->{low}    = $candle->{low}    if $candle->{low}    < $aggregated[$idx]->{low};
            $aggregated[$idx]->{close}  = $candle->{close};
            $aggregated[$idx]->{volume} += $candle->{volume};
        }
    }

    $self->{data}->{$target_tf} = \@aggregated;
}

sub build_timeframes {
    my ($self) = @_;
    $self->build_tf_candles('5m');
    $self->build_tf_candles('15m');
    $self->set_timeframe('1m');
}

sub set_timeframe {
    my ($self, $tf) = @_;
    if (exists $self->{data}->{$tf}) {
        $self->{current_tf} = $tf;
    } else {
        warn "La temporalidad $tf no ha sido construida aún.\n";
    }
}

sub _active_array {
    my ($self) = @_;
    return $self->{data}->{ $self->{current_tf} };
}

sub get_slice {
    my ($self, $start, $end) = @_;
    my $array_ref = $self->_active_array();
    $start = 0                  if $start < 0;
    $end   = $#{$array_ref}     if $end > $#{$array_ref};
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
    return undef unless $array_ref && @$array_ref;
    return $#{$array_ref};
}

sub get_candle {
    my ($self, $index) = @_;
    my $array_ref = $self->_active_array();
    return undef if !defined $index || $index < 0 || $index > $#{$array_ref};
    return $array_ref->[$index];
}

1;
