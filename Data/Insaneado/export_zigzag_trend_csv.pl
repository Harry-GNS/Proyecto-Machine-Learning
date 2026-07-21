#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use Getopt::Long;
use Market::Indicators::ZigZagTrend;

sub usage {
    return <<"USAGE";
Uso:
  perl backend/export_zigzag_trend_csv.pl --input backend/data/2026_03.csv > zigzag_out.csv

Opciones:
  --input PATH                       CSV OHLCV de entrada
  --output PATH                      CSV de salida (opcional, por defecto stdout)
  --swing-length N                   Longitud ZigZag, default 150
  --high-pivot-price-source low|high Precio del pivot alto, default low
USAGE
}

my $input;
my $output;
my $swing_length = 150;
my $high_pivot_price_source = 'low';
my $help = 0;

GetOptions(
    'input=s'                    => \$input,
    'output=s'                   => \$output,
    'swing-length=i'             => \$swing_length,
    'high-pivot-price-source=s'  => \$high_pivot_price_source,
    'help'                       => \$help,
) or die usage();

if (!$input && @ARGV) {
    $input = shift @ARGV;
}

if ($help || !$input) {
    print usage();
    exit($help ? 0 : 1);
}

open(my $in_fh, '<', $input) or die "No pude abrir $input: $!";

my $out_fh;
if (defined $output && length $output) {
    open($out_fh, '>', $output) or die "No pude escribir $output: $!";
}
else {
    open($out_fh, '>&', \*STDOUT) or die "No pude usar stdout: $!";
}

my $zz = Market::Indicators::ZigZagTrend->new(
    swingLength             => $swing_length,
    high_pivot_price_source => $high_pivot_price_source,
);

my $first = <$in_fh>;
die "CSV vacio: $input\n" unless defined $first;
chomp $first;
$first =~ s/\r$//;

my @first_fields = split(/,/, $first, -1);
my ($has_header, %pos) = _detect_header(@first_fields);

if ($has_header) {
    %pos = _header_positions(@first_fields);
}
else {
    %pos = (
        time   => 0,
        open   => 1,
        high   => 2,
        low    => 3,
        close  => 4,
        volume => 5,
    );
}

print $out_fh _csv_row(qw(
    index time open high low close volume
    swing_high swing_low trend trend_changed
    pivot_high_index pivot_high_price pivot_low_index pivot_low_price
    last_high_index last_high_price last_low_index last_low_price
    active_direction active_start_index active_start_price active_end_index active_end_price
    completed_segment_direction completed_segment_start_index completed_segment_start_price
    completed_segment_end_index completed_segment_end_price completed_segments
));

my $idx = 0;
if (!$has_header) {
    _process_fields(\@first_fields, \%pos, $zz, $out_fh, $idx++);
}

while (my $line = <$in_fh>) {
    chomp $line;
    $line =~ s/\r$//;
    next if $line =~ /^\s*$/;

    my @fields = split(/,/, $line, -1);
    _process_fields(\@fields, \%pos, $zz, $out_fh, $idx++);
}

close($in_fh);
close($out_fh);

sub _process_fields {
    my ($fields, $pos, $zz, $out_fh, $idx) = @_;

    my $candle = {
        time   => _field($fields, $pos, 'time'),
        open   => _field($fields, $pos, 'open')  + 0,
        high   => _field($fields, $pos, 'high')  + 0,
        low    => _field($fields, $pos, 'low')   + 0,
        close  => _field($fields, $pos, 'close') + 0,
        volume => (_field($fields, $pos, 'volume') // 0) + 0,
    };

    my $state = $zz->update_candle($candle, $idx);
    my $hp    = $state->{high_pivot};
    my $lp    = $state->{low_pivot};
    my $lhp   = $state->{last_high_pivot};
    my $llp   = $state->{last_low_pivot};
    my $act   = $state->{active_segment};
    my $done  = $state->{completed_segment};

    print $out_fh _csv_row(
        $idx,
        $candle->{time},
        $candle->{open},
        $candle->{high},
        $candle->{low},
        $candle->{close},
        $candle->{volume},
        $state->{swing_high},
        $state->{swing_low},
        $state->{trend},
        $state->{trend_changed},
        $hp  ? $hp->{index}  : undef,
        $hp  ? $hp->{price}  : undef,
        $lp  ? $lp->{index}  : undef,
        $lp  ? $lp->{price}  : undef,
        $lhp ? $lhp->{index} : undef,
        $lhp ? $lhp->{price} : undef,
        $llp ? $llp->{index} : undef,
        $llp ? $llp->{price} : undef,
        $act ? $act->{direction}   : undef,
        $act ? $act->{start_index} : undef,
        $act ? $act->{start_price} : undef,
        $act ? $act->{end_index}   : undef,
        $act ? $act->{end_price}   : undef,
        $done ? $done->{direction}   : undef,
        $done ? $done->{start_index} : undef,
        $done ? $done->{start_price} : undef,
        $done ? $done->{end_index}   : undef,
        $done ? $done->{end_price}   : undef,
        $state->{completed_segments},
    );

    return;
}

sub _detect_header {
    my @fields = @_;
    for my $field (@fields) {
        return (1) if lc($field) eq 'high';
    }
    return (0);
}

sub _header_positions {
    my @header = @_;
    my %pos;
    for my $i (0 .. $#header) {
        my $name = lc $header[$i];
        $name =~ s/^\s+|\s+$//g;
        $pos{$name} = $i;
    }

    for my $required (qw(time open high low close)) {
        die "CSV sin columna requerida: $required\n" unless exists $pos{$required};
    }
    $pos{volume} = $pos{vol} if !exists $pos{volume} && exists $pos{vol};
    $pos{volume} = $pos{Volume} if !exists $pos{volume} && exists $pos{Volume};
    $pos{volume} = 5 unless exists $pos{volume};

    return %pos;
}

sub _field {
    my ($fields, $pos, $name) = @_;
    my $idx = $pos->{$name};
    return undef unless defined $idx;
    return $fields->[$idx];
}

sub _csv_row {
    return join(',', map { _csv_cell($_) } @_) . "\n";
}

sub _csv_cell {
    my ($value) = @_;
    return '' unless defined $value;
    $value = "$value";
    if ($value =~ /[",\r\n]/) {
        $value =~ s/"/""/g;
        return qq{"$value"};
    }
    return $value;
}
