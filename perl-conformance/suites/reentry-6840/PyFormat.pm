package PyFormat;

# Python's `repr` and `json.dumps` text, so that the reentry analyses print exactly what their earlier Python versions
# printed and the committed summaries stay reproducible.  The values are what JSON::PP decodes: strings, numbers,
# undef (None), JSON booleans, array references (lists) and hash references (dicts, whose keys are written in the
# order Python would keep them -- the order the record was written in, which for these records is sorted).  A tuple is
# an array reference blessed into PyFormat::Tuple.

use strict;
use warnings;
use B ();

sub tuple { return bless [@_], 'PyFormat::Tuple' }

# A number as Python writes it: an integer bare, a float with its shortest round-tripping digits and a `.0` when it has
# no fraction or exponent.
sub py_number {
    my ($v) = @_;
    my $flags = B::svref_2object(\$v)->FLAGS;
    return "$v" if ($flags & B::SVf_IOK) && !($flags & B::SVf_NOK);
    for my $p (1 .. 17) {
        my $s = sprintf("%.${p}g", $v);
        next unless $s + 0 == $v;
        $s =~ s/e([+-])0*(\d\d)/e$1$2/;
        $s .= '.0' unless $s =~ /[.e]|inf|nan/i;
        return $s;
    }
    return "$v";
}

sub is_number {
    my ($v) = @_;
    return 0 if ref $v || !defined $v;
    my $flags = B::svref_2object(\$v)->FLAGS;
    return ($flags & (B::SVf_IOK | B::SVf_NOK)) && !($flags & B::SVf_POK) ? 1 : 0;
}

sub repr_str {
    my ($s) = @_;
    my $q = ($s =~ /'/ && $s !~ /"/) ? '"' : "'";
    my $out = '';
    for my $c (split //, $s) {
        my $o = ord $c;
        if    ($c eq '\\')                 { $out .= '\\\\' }
        elsif ($c eq $q)                   { $out .= "\\$q" }
        elsif ($c eq "\n")                 { $out .= '\\n' }
        elsif ($c eq "\r")                 { $out .= '\\r' }
        elsif ($c eq "\t")                 { $out .= '\\t' }
        elsif ($o < 0x20 || $o == 0x7f)    { $out .= sprintf('\\x%02x', $o) }
        elsif ($o >= 0x80 && $o < 0xa0)    { $out .= sprintf('\\x%02x', $o) }
        else                               { $out .= $c }
    }
    return "$q$out$q";
}

# Python's repr(value).
sub repr {
    my ($v) = @_;
    return 'None' unless defined $v;
    if (ref $v) {
        return ($v ? 'True' : 'False') if JSON::PP::is_bool($v);
        if (ref $v eq 'PyFormat::Tuple') {
            return '(' . repr($v->[0]) . ',)' if @$v == 1;
            return '(' . join(', ', map { repr($_) } @$v) . ')';
        }
        return '[' . join(', ', map { repr($_) } @$v) . ']' if ref $v eq 'ARRAY';
        return '{' . join(', ', map { repr($_) . ': ' . repr($v->{$_}) } keys_of($v)) . '}' if ref $v eq 'HASH';
        die "cannot repr " . ref($v) . "\n";
    }
    return is_number($v) ? py_number($v) : repr_str($v);
}

# Python's str(value): a string bare, anything else as repr.
sub str { my ($v) = @_; return defined $v && !ref $v && !is_number($v) ? $v : repr($v) }

# A dict's keys in the order Python would hold them.  JSON::PP does not keep the decoded order, so the order is the
# sorted one, which is how every record in these files was written; a dict built here passes its own order instead.
sub keys_of {
    my ($h) = @_;
    return @{ $h->{'__order__'} } if $h->{'__order__'};
    return sort grep { $_ ne '__order__' } keys %$h;
}

sub json_str {
    my ($s) = @_;
    my $out = '"';
    for my $c (split //, $s) {
        my $o = ord $c;
        if    ($c eq '"')  { $out .= '\\"' }
        elsif ($c eq '\\') { $out .= '\\\\' }
        elsif ($c eq "\n") { $out .= '\\n' }
        elsif ($c eq "\r") { $out .= '\\r' }
        elsif ($c eq "\t") { $out .= '\\t' }
        elsif ($c eq "\b") { $out .= '\\b' }
        elsif ($c eq "\f") { $out .= '\\f' }
        elsif ($o < 0x20 || $o > 0x7e) {
            if ($o > 0xffff) {
                my $u = $o - 0x10000;
                $out .= sprintf('\\u%04x\\u%04x', 0xd800 + ($u >> 10), 0xdc00 + ($u & 0x3ff));
            }
            else { $out .= sprintf('\\u%04x', $o) }
        }
        else { $out .= $c }
    }
    return "$out\"";
}

# Python's json.dumps(value, sort_keys=True), with indent=N when $indent is given; a dict that carries its own key
# order (`__order__`) is written in that order, as json.dumps without sort_keys writes a dict built in it.
sub dumps {
    my ($v, $indent, $level) = @_;
    $level //= 0;
    return 'null' unless defined $v;
    if (ref $v) {
        return ($v ? 'true' : 'false') if JSON::PP::is_bool($v);
        my $nl = defined $indent ? "\n" . (' ' x ($indent * ($level + 1))) : '';
        my $end = defined $indent ? "\n" . (' ' x ($indent * $level)) : '';
        my $sep = defined $indent ? ',' : ', ';
        if (ref $v eq 'ARRAY' || ref $v eq 'PyFormat::Tuple') {
            return '[]' unless @$v;
            return '[' . $nl . join($sep . $nl, map { dumps($_, $indent, $level + 1) } @$v) . $end . ']';
        }
        if (ref $v eq 'HASH') {
            my @k = keys_of($v);
            return '{}' unless @k;
            my @items = map { json_str($_) . ': ' . dumps($v->{$_}, $indent, $level + 1) } @k;
            return '{' . $nl . join($sep . $nl, @items) . $end . '}';
        }
        die "cannot dump " . ref($v) . "\n";
    }
    return is_number($v) ? py_number($v) : json_str($v);
}

1;
