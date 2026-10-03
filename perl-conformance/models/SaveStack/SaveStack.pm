package SS;
# Executable transcription of scope.c's `local` semantics over a miniature
# SV world: cells with refcounts, a mortals stack freed at statement
# boundaries, container/value magic, tied containers, a glob/GP layer, and
# the save stack with Perl_leave_scope's pop-before-execute unwind. A
# snake_case routine mirrors the perl 5.44.0 function or macro of that name
# (Perl_/S_ removed); comments cite them. What has no C counterpart is
# harness glue in SS::Harness: Reset, Trace and Show for the world and the
# observation, Read and Store for a payload read with get magic and a
# payload store with set magic (the value side of sv_setsv_mg, over opaque
# payloads), StoreRef for sv_setrv_inc_mg, RetainPayload and ReleasePayload
# for the references a tie's own store holds.
use strict; use warnings;

our (%CELL, %AV, %HV, %GLOB, %GP, @SS, @TMPS, @TRACE);
our ($NID, $ARMDIE, $PENDING);

sub SS::Harness::Reset {
    %CELL = (); %AV = (); %HV = (); %GLOB = (); %GP = ();
    @SS = (); @TMPS = (); @TRACE = ();
    $NID = 0; $ARMDIE = 0; $PENDING = undef;
}

sub SS::Harness::Trace { push @TRACE, join(':', @_) }
sub SS::Harness::Show { my $v = shift; !defined $v ? 'u' : ref $v ? 'r' : $v }

# ---------------- cells ----------------
# A cell is one SV: { v => payload, rc, mag => [..], smag, gmag, obj }.
# Payloads: plain scalar, undef, ['RV', cellid]. obj => { n => name,
# d => dies-in-DESTROY } marks a blessed referent.

sub newSV {
    my (%f) = @_;
    my $id = 'c' . ++$NID;
    $CELL{$id} = { v => undef, rc => 1, mag => [], smag => 0, gmag => 0, %f };
    return $id;
}

sub SvREFCNT_inc { $CELL{$_[0]}{rc}++; $_[0] }

sub SvREFCNT_dec {
    my ($id) = @_;
    return unless defined $id && $CELL{$id};
    my $c = $CELL{$id};
    return if --$c->{rc} > 0;
    delete $CELL{$id};
    if (my $o = $c->{obj}) {

        # S_curse invokes DESTROY via call_sv with G_EVAL|G_KEEPERR
        # (sv.c:7783): an exception raised inside an implicit destructor is
        # downgraded to a "(in cleanup)" warning and never propagates.
        SS::Harness::Trace('X', $o->{n});
        warn "D\n" if $o->{d};
    }
    if (ref $c->{v} && $c->{v}[0] eq 'RV') { SvREFCNT_dec($c->{v}[1]) }
}

sub sv_2mortal { push @TMPS, $_[0]; $_[0] }

# A tie's own store holds real references: storing an RV payload retains
# the referent, and overwriting or deleting the entry releases it. This is
# what defers a displaced object's DESTROY until the restore STORE
# overwrites the tie slot.
sub SS::Harness::RetainPayload {
    my ($v) = @_;
    SvREFCNT_inc($v->[1]) if ref $v && $v->[0] eq 'RV';
    return $v;
}

sub SS::Harness::ReleasePayload {
    my ($v) = @_;
    SvREFCNT_dec($v->[1]) if ref $v && $v->[0] eq 'RV';
}

# FREETMPS: tmps popped and released newest-first.
sub free_tmps { while (@TMPS) { SvREFCNT_dec(pop @TMPS) } }

# A statement boundary: pp_nextstate's FREETMPS.
sub pp_nextstate { free_tmps() }

# ---------------- magic ----------------
# Magic entries, keyed by the PERL_MAGIC_ name of their type:
#   { t => 'tied',     o => tieobj }                       PERL_MAGIC_tied, a tied scalar
#   { t => 'tiedelem', cont => id, key => k, kind => 'A'|'H' }  PERL_MAGIC_tiedelem, a tied element
#   { t => 'sv',       name => '$/'|'$0', gref => \$global }  PERL_MAGIC_sv, a magical variable
# mg_find(sv, type) returns the first entry of that type, as Perl_mg_find does.
sub mg_find { my ($c, $type) = @_; for (@{ $c->{mag} }) { return $_ if $_->{t} eq $type } return }

# mg_get: tied scalar FETCH / tied element FETCH(key) / magical read; the
# fetched value lands in the cell's payload cache.
sub mg_get {
    my ($id) = @_;
    my $c = $CELL{$id};
    return unless $c->{gmag};
    if (my $m = mg_find($c, 'tied')) {
        my $v = $m->{o}{v};
        SS::Harness::Trace('F', SS::Harness::Show($v));
        $c->{v} = $v;
    }
    elsif (my $e = mg_find($c, 'tiedelem')) {
        my $cont = $e->{kind} eq 'A' ? $AV{ $e->{cont} } : $HV{ $e->{cont} };
        my $v = $cont->{tie}{store}{ $e->{key} };
        SS::Harness::Trace('F', $e->{key}, SS::Harness::Show($v));
        $c->{v} = $v;
    }
    elsif (my $s = mg_find($c, 'sv')) {

        # Perl_magic_get's cases for these variables are empty (mg.c:1237
        # '/': break with no body): the read keeps the cached payload, and
        # only magic_set writes the interpreter-global side.
    }
    return $c->{v};
}

# mg_set: tied scalar STORE / tied element STORE(key,v) / magical write.
# A STORE armed to die records the call first, then throws — the model of a
# user STORE whose body dies.
sub mg_set {
    my ($id) = @_;
    my $c = $CELL{$id};
    return unless $c->{smag};
    if (my $m = mg_find($c, 'tied')) {
        SS::Harness::Trace('S', SS::Harness::Show($c->{v}));
        die "S\n" if $ARMDIE;
        my $old = $m->{o}{v};
        $m->{o}{v} = SS::Harness::RetainPayload($c->{v});
        SS::Harness::ReleasePayload($old);
    }
    elsif (my $e = mg_find($c, 'tiedelem')) {
        my $cont = $e->{kind} eq 'A' ? $AV{ $e->{cont} } : $HV{ $e->{cont} };
        SS::Harness::Trace('S', $e->{key}, SS::Harness::Show($c->{v}));
        die "S\n" if $ARMDIE;
        my $old = $cont->{tie}{store}{ $e->{key} };
        $cont->{tie}{store}{ $e->{key} } = SS::Harness::RetainPayload($c->{v});
        SS::Harness::ReleasePayload($old);
        my $t = $cont->{tie};
        $t->{top} = $e->{key} if $e->{kind} eq 'A' && $e->{key} > ($t->{top} // -1);
    }
    elsif (my $s = mg_find($c, 'sv')) { ${ $s->{gref} } = $c->{v} }
}

sub SS::Harness::Read { my ($id) = @_; mg_get($id); $CELL{$id}{v} }
sub SS::Harness::Store {
    my ($id, $v) = @_;
    my $old = $CELL{$id}{v};
    $CELL{$id}{v} = $v;
    SS::Harness::ReleasePayload($old) if ref $old;
    mg_set($id);
}

# sv_setrv_inc_mg: the destination takes a new reference to the referent,
# then set magic runs.
sub SS::Harness::StoreRef {
    my ($id, $target) = @_;
    SvREFCNT_inc($target);
    my $old = $CELL{$id}{v};
    $CELL{$id}{v} = ['RV', $target];
    SvREFCNT_dec($old->[1]) if ref $old && $old->[0] eq 'RV';
    mg_set($id);
}

# ---------------- containers ----------------

sub newAV {
    my (%f) = @_;
    my $id = 'a' . ++$NID;
    $AV{$id} = { elems => [], tie => undef, %f };
    return $id;
}

sub newHV {
    my (%f) = @_;
    my $id = 'h' . ++$NID;
    $HV{$id} = { elems => {}, tie => undef, %f };
    return $id;
}

# av_fetch / hv_fetch_ent. A tied container yields a fresh mirror cell
# carrying tiedelem magic; no FETCH happens until mg_get. A plain fetch
# with lval set vivifies the slot; without it a missing slot is undef.
sub av_fetch {
    my ($avid, $idx, $lval) = @_;
    my $av = $AV{$avid};
    if ($av->{tie}) {
        my $m = newSV();
        push @{ $CELL{$m}{mag} }, { t => 'tiedelem', cont => $avid, key => $idx, kind => 'A' };
        $CELL{$m}{smag} = $CELL{$m}{gmag} = 1;
        sv_2mortal($m);
        return \$av->{mirror}[$idx], ($av->{mirror}[$idx] = $m);
    }
    return (undef, undef) if !$lval && !defined $av->{elems}[$idx];
    $av->{elems}[$idx] = newSV() unless defined $av->{elems}[$idx];
    return \$av->{elems}[$idx], $av->{elems}[$idx];
}

sub hv_fetch_ent {
    my ($hvid, $key, $lval) = @_;
    my $hv = $HV{$hvid};
    if ($hv->{tie}) {
        my $m = newSV();
        push @{ $CELL{$m}{mag} }, { t => 'tiedelem', cont => $hvid, key => $key, kind => 'H' };
        $CELL{$m}{smag} = $CELL{$m}{gmag} = 1;
        sv_2mortal($m);
        return \$hv->{mirror}{$key}, ($hv->{mirror}{$key} = $m);
    }
    return (undef, undef) if !$lval && !exists $hv->{elems}{$key};
    $hv->{elems}{$key} = newSV() unless defined $hv->{elems}{$key};
    return \$hv->{elems}{$key}, $hv->{elems}{$key};
}

sub av_exists {
    my ($avid, $idx) = @_;
    my $av = $AV{$avid};
    if ($av->{tie}) { SS::Harness::Trace('E', $idx); return exists $av->{tie}{store}{$idx} ? 1 : 0 }
    return defined $av->{elems}[$idx] ? 1 : 0;
}

sub hv_exists {
    my ($hvid, $key) = @_;
    my $hv = $HV{$hvid};
    if ($hv->{tie}) { SS::Harness::Trace('E', $key); return exists $hv->{tie}{store}{$key} ? 1 : 0 }
    return exists $hv->{elems}{$key} ? 1 : 0;
}

# av_delete / hv_delete with G_DISCARD; a tied container routes to the
# tie's DELETE. A plain array deletion past the fill is a no-op (av.c:1095
# returns before touching the array); a deletion at the top index shrinks
# the array past any contiguous holes below it. The past-the-fill case is
# reached by an ADELETE restore after the array shrank below the saved
# index; an earlier version extended the array to the index first and then
# trimmed it back through the holes, which is not what perl does.
sub av_delete {
    my ($avid, $idx) = @_;
    my $av = $AV{$avid};
    if ($av->{tie}) {
        SS::Harness::Trace('D', $idx);
        SS::Harness::ReleasePayload(delete $av->{tie}{store}{$idx});
        if ($idx == ($av->{tie}{top} // -1)) {
            my $t = $idx - 1;
            $t-- while $t >= 0 && !exists $av->{tie}{store}{$t};
            $av->{tie}{top} = $t;
        }
        return;
    }
    my $e = $av->{elems};
    return if $idx > $#$e;
    SvREFCNT_dec($e->[$idx]) if defined $e->[$idx];
    $e->[$idx] = undef;
    if ($idx == $#$e) { pop @$e; pop @$e while @$e && !defined $e->[-1] }
}

sub hv_delete {
    my ($hvid, $key) = @_;
    my $hv = $HV{$hvid};
    if ($hv->{tie}) {
        SS::Harness::Trace('D', $key);
        SS::Harness::ReleasePayload(delete $hv->{tie}{store}{$key});
        return;
    }
    my $c = delete $hv->{elems}{$key};
    SvREFCNT_dec($c) if defined $c;
}

sub av_clear {
    my ($avid) = @_;
    my $av = $AV{$avid};
    if ($av->{tie}) {
        SS::Harness::Trace('C');
        my $st = $av->{tie}{store};
        $av->{tie}{store} = {}; $av->{tie}{top} = -1;
        SS::Harness::ReleasePayload($st->{$_}) for sort keys %$st;
        return;
    }
    SvREFCNT_dec($_) for grep { defined } @{ $av->{elems} };
    $av->{elems} = [];
}

sub hv_clear {
    my ($hvid) = @_;
    my $hv = $HV{$hvid};
    if ($hv->{tie}) {
        SS::Harness::Trace('C');
        my $st = $hv->{tie}{store};
        $hv->{tie}{store} = {};
        SS::Harness::ReleasePayload($st->{$_}) for sort keys %$st;
        return;
    }
    SvREFCNT_dec($_) for values %{ $hv->{elems} };
    $hv->{elems} = {};
}

# Structural array operations on a plain (untied) array. The array is its
# element list: a defined entry is an SV, an undef entry is a NULL slot (a
# hole), and the list's last index is AvFILLp. None of these look inside
# the save stack, which is why a `local` on an element survives them
# unchanged: the AELEM record names the array and the original index, and
# the restore re-fetches by that index into whatever the array has become.
# The tied forms (SHIFT/UNSHIFT/PUSH/POP/STORESIZE/SPLICE method calls)
# are not modeled; the structural cells of the generator are plain-only.

# Perl_av_shift (av.c:934): returns the first SV itself, ownership passed
# to the caller; pp_shift mortalizes it. An empty array yields undef here,
# standing in for &PL_sv_undef.
sub av_shift {
    my ($avid) = @_;
    my $av = $AV{$avid};
    die "av_shift: tied arrays are not modeled" if $av->{tie};
    return undef unless @{ $av->{elems} };
    return shift @{ $av->{elems} };
}

# Perl_av_pop (av.c:810): the mirror image, from the top index.
sub av_pop {
    my ($avid) = @_;
    my $av = $AV{$avid};
    die "av_pop: tied arrays are not modeled" if $av->{tie};
    return undef unless @{ $av->{elems} };
    return pop @{ $av->{elems} };
}

# Perl_av_unshift (av.c:868): opens $num NULL slots at the front. The
# values pp_unshift then stores are fresh copies (newSVsv), never the
# caller's SVs.
sub av_unshift {
    my ($avid, $num) = @_;
    my $av = $AV{$avid};
    die "av_unshift: tied arrays are not modeled" if $av->{tie};
    unshift @{ $av->{elems} }, (undef) x $num;
}

# Perl_av_push (av.c:780) is av_store at AvFILLp + 1; pp_push stores a
# fresh copy of each argument.
sub av_push {
    my ($avid, $cell) = @_;
    my $av = $AV{$avid};
    die "av_push: tied arrays are not modeled" if $av->{tie};
    push @{ $av->{elems} }, $cell;
}

# Perl_av_fill (av.c:1010), the `$#a = N` store: shrinking frees the SVs
# above the new fill and NULLs their slots; growing extends with NULL
# slots, which are holes, not undef elements.
sub av_fill {
    my ($avid, $fill) = @_;
    my $av = $AV{$avid};
    die "av_fill: tied arrays are not modeled" if $av->{tie};
    $fill = -1 if $fill < 0;
    my $e = $av->{elems};
    if ($fill < $#$e) {
        SvREFCNT_dec($_) for grep { defined } @$e[$fill + 1 .. $#$e];
        $#$e = $fill;
    }
    elsif ($fill > $#$e) { $#$e = $fill }
}

# pp_splice (pp.c:6109) on a plain array. $gimme is 'list' or 'scalar'
# (void takes the scalar path). The inserted SVs are the caller's cells,
# already fresh copies as pp_splice makes them (newSVsv) before touching
# the array. The removed SVs are returned themselves, not copied: in list
# context every one is mortalized; in scalar context only the last is
# mortalized and returned, the rest are freed on the spot.
sub av_splice {
    my ($avid, $gimme, $offset, $length, @new) = @_;
    my $av = $AV{$avid};
    die "av_splice: tied arrays are not modeled" if $av->{tie};
    my $e = $av->{elems};
    $offset = @$e if $offset > @$e;
    $length = @$e - $offset if $offset + $length > @$e;
    my @removed = splice @$e, $offset, $length, @new;
    if ($gimme eq 'list') { sv_2mortal($_) for grep { defined } @removed; return @removed }
    my $last = @removed ? pop @removed : undef;
    SvREFCNT_dec($_) for grep { defined } @removed;
    sv_2mortal($last) if defined $last;
    return $last;
}

# ---------------- globs ----------------

# gv_fetchpv with GV_ADD: a fresh GV whose GP holds a fresh scalar slot.
sub gv_fetchpv {
    my ($name) = @_;
    my $gpid = 'g' . ++$NID;
    $GP{$gpid} = { sv => newSV(), rc => 1 };
    $GLOB{$name} = { gp => $gpid };
    return $name;
}

sub gp_free {
    my ($gpid) = @_;
    return if --$GP{$gpid}{rc} > 0;
    SvREFCNT_dec($GP{$gpid}{sv});
    delete $GP{$gpid};
}

# GvSV as an lvalue: a reference to the scalar slot of the glob's current GP.
sub GvSV { \$GP{ $GLOB{ $_[0] }{gp} }{sv} }

# ---------------- the save stack: scope.c transcriptions ----------------

sub SAVEf_SETMAGIC () { 1 }

# S_save_scalar_at: install a fresh SVt_NULL in the slot; if the old SV
# carried magic, mg_localize copies the container magic (never the value
# magic) onto the fresh SV and, under SAVEf_SETMAGIC, runs SvSETMAGIC on it.
sub save_scalar_at {
    my ($slotref, $flags) = @_;
    my $old = $$slotref;
    my $fresh = newSV();
    $$slotref = $fresh;
    mg_localize($old, $fresh, $flags & SAVEf_SETMAGIC) if @{ $CELL{$old}{mag} };
    return $fresh;
}

# Perl_mg_localize.
sub mg_localize {
    my ($oldid, $newid, $setmagic) = @_;
    my ($o, $n) = ($CELL{$oldid}, $CELL{$newid});
    push @{ $n->{mag} }, { %$_ } for @{ $o->{mag} };
    if (@{ $n->{mag} }) {
        $n->{smag} = $o->{smag}; $n->{gmag} = $o->{gmag};
        mg_set($newid) if $setmagic;
    }
}

# Perl_save_scalar: mg_get the old SV first when it is gmagical, push the
# SAVEt_SV record holding the GV and a new reference to the old SV, then
# save_scalar_at with SAVEf_SETMAGIC.
sub save_scalar {
    my ($gvname) = @_;
    my $slotref = GvSV($gvname);
    mg_get($$slotref) if $CELL{$$slotref}{gmag};
    push @SS, ['SV', $gvname, SvREFCNT_inc($$slotref)];
    return save_scalar_at($slotref, SAVEf_SETMAGIC);
}

# Perl_save_aelem_flags: SvGETMAGIC on the element, push SAVEt_AELEM with a
# new reference, save_scalar_at, and mortalize the fresh SV when the array
# is tied, since the tie's store never holds it.
sub save_aelem_flags {
    my ($avid, $idx, $slotref, $flags) = @_;
    mg_get($$slotref) if $CELL{$$slotref}{gmag};
    push @SS, ['AELEM', $avid, $idx, SvREFCNT_inc($$slotref)];
    my $fresh = save_scalar_at($slotref, $flags);
    sv_2mortal($fresh) if $AV{$avid}{tie};
}

# Perl_save_helem_flags: identical shape, key saved by copy (newSVsv).
sub save_helem_flags {
    my ($hvid, $key, $slotref, $flags) = @_;
    mg_get($$slotref) if $CELL{$$slotref}{gmag};
    push @SS, ['HELEM', $hvid, $key, SvREFCNT_inc($$slotref)];
    my $fresh = save_scalar_at($slotref, $flags);
    sv_2mortal($fresh) if $HV{$hvid}{tie};
}

sub save_adelete { push @SS, ['ADELETE', $_[0], $_[1]] }
sub save_hdelete { push @SS, ['HDELETE', $_[0], $_[1]] }

# Perl_save_gp: push the current GP; empty installs a new GP whose scalar
# slot is fresh, else the old GP gains a reference.
sub save_gp {
    my ($gvname, $empty) = @_;
    my $g = $GLOB{$gvname};
    push @SS, ['GP', $gvname, $g->{gp}];
    if ($empty) {
        my $gpid = 'g' . ++$NID;
        $GP{$gpid} = { sv => newSV(), rc => 1 };
        $g->{gp} = $gpid;
    }
    else { $GP{ $g->{gp} }{rc}++ }
}

# Perl_save_clearsv (SAVEt_CLEARSV is pushed when `my` executes).
sub save_clearsv { push @SS, ['CLEARSV', $_[0]] }

# pp_gvsv with OPpLVAL_INTRO.
sub pp_gvsv { save_scalar($_[0]) }

# pp_aelem's localizing block: preeminence via EXISTS when the container
# can, save_aelem (always SAVEf_SETMAGIC) when present, SAVEADELETE when
# absent. pp_helem is the same shape except that OPf_SPECIAL — the
# assignment form — suppresses SAVEf_SETMAGIC.
sub pp_aelem {
    my ($avid, $idx, $assign) = @_;
    my $pre = av_exists($avid, $idx);
    my ($slotref) = av_fetch($avid, $idx, 1);
    if ($pre) { save_aelem_flags($avid, $idx, $slotref, SAVEf_SETMAGIC) }
    else { save_adelete($avid, $idx) }
    return $slotref;
}

sub pp_helem {
    my ($hvid, $key, $assign) = @_;
    my $pre = hv_exists($hvid, $key);
    my ($slotref) = hv_fetch_ent($hvid, $key, 1);
    if ($pre) { save_helem_flags($hvid, $key, $slotref, $assign ? 0 : SAVEf_SETMAGIC) }
    else { save_hdelete($hvid, $key) }
    return $slotref;
}

# ---------------- Perl_leave_scope ----------------
# Records are popped before they execute. restore_sv is the shared tail:
# rebind the slot to the saved SV, drop the displaced one, and when the
# restored SV is set-magical, push FREESV cleanups for the value and the
# container BEFORE the fallible mg_set — a die inside mg_set skips the
# inline frees, and the cleanups run in the continuing unwind either way.
# An exception recorded mid-unwind does not stop the remaining records; it
# propagates after they run.

sub restore_sv {
    my ($slotref, $value, $refsv_cell) = @_;
    my $displaced = $$slotref;
    $$slotref = $value;
    SvREFCNT_dec($displaced);
    if ($CELL{$value}{smag}) {
        push @SS, ['FREESV', $value], ['FREESV', $refsv_cell // ()];
        pop @SS if !defined $refsv_cell;
        eval { mg_set($value) };
        $PENDING = $@ if $@ && !defined $PENDING;
        return;
    }
    SvREFCNT_dec($value);
    SvREFCNT_dec($refsv_cell) if defined $refsv_cell;
}

sub leave_scope {
    my ($base) = @_;
    while (@SS > $base) {
        my $rec = pop @SS;
        my ($t) = @$rec;
        if ($t eq 'SV') {
            my (undef, $gvname, $saved) = @$rec;
            restore_sv(GvSV($gvname), $saved, undef);
        }
        elsif ($t eq 'AELEM') {
            my (undef, $avid, $idx, $saved) = @$rec;

            # av_fetch(av, idx, 1): the re-fetch is keyed by container and
            # index, vivifying the slot if the array was cleared.
            my ($slotref, $cur) = av_fetch($avid, $idx, 1);
            SvREFCNT_inc($cur) if $AV{$avid}{tie};
            restore_sv($slotref, $saved, undef);
        }
        elsif ($t eq 'HELEM') {
            my (undef, $hvid, $key, $saved) = @$rec;
            my ($slotref, $cur) = hv_fetch_ent($hvid, $key, 1);
            SvREFCNT_inc($cur) if $HV{$hvid}{tie};
            restore_sv($slotref, $saved, undef);
        }
        elsif ($t eq 'ADELETE') {
            eval { av_delete($rec->[1], $rec->[2]) };
            $PENDING = $@ if $@ && !defined $PENDING;
        }
        elsif ($t eq 'HDELETE') {
            eval { hv_delete($rec->[1], $rec->[2]) };
            $PENDING = $@ if $@ && !defined $PENDING;
        }
        elsif ($t eq 'GP') {
            my (undef, $gvname, $oldgp) = @$rec;
            eval { gp_free($GLOB{$gvname}{gp}) };
            $PENDING = $@ if $@ && !defined $PENDING;
            $GLOB{$gvname}{gp} = $oldgp;
        }
        elsif ($t eq 'CLEARSV') {
            my (undef, $padref) = @$rec;
            my $c = $CELL{$$padref};

            # SAVEt_CLEARSV: clear in place when the pad SV holds the only
            # reference and is not itself a blessed object; otherwise
            # abandon it to a fresh SV and drop the reference.
            if ($c->{rc} == 1 && !$c->{obj}) {
                my $v = $c->{v};
                $c->{v} = undef;
                eval { SvREFCNT_dec($v->[1]) if ref $v && $v->[0] eq 'RV' };
                $PENDING = $@ if $@ && !defined $PENDING;
            }
            else {
                my $old = $$padref;
                $$padref = newSV();
                eval { SvREFCNT_dec($old) };
                $PENDING = $@ if $@ && !defined $PENDING;
            }
        }
        elsif ($t eq 'FREESV') {
            eval { SvREFCNT_dec($rec->[1]) };
            $PENDING = $@ if $@ && !defined $PENDING;
        }
    }
}

1;
