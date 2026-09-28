package FZ;
# Executable transcription of perl 5.44.0's finalization and temporary-lifetime machinery over a small IR.
# Every routine names the C function it mirrors.  State: objects (refcounted, blessed), holders (lexicals,
# globals, tied scalars, one array and one hash), the tmps stack with its floor, the context stack, the
# save stack (SAVEt_CLEARSV and local entries), and the trace.
use strict; use warnings;
our (%OBJ, %VAR, @TMPS, $FLOOR, @CTX, @SAVE, @TRACE, @WEAKNAMES, %CONT, $INCLEAN);
sub FZ::Harness::ResetState { %OBJ=(); %VAR=(); @TMPS=(); $FLOOR=-1; @CTX=(); @SAVE=(); @TRACE=(); %CONT=(); $INCLEAN=0;
  $VAR{$_} = {val=>undef} for qw(keep wk G) }
sub FZ::Harness::Trace { push @TRACE, shift }
sub FZ::Harness::WeakFlags { join "", map { my $v=$VAR{$_}; ($v && $v->{val} && !$v->{tied}) ? 1 : 0 } @WEAKNAMES }   # defined on a tied holder goes through FETCH, which returns undef in the harness
sub FZ::Harness::IsRef { my $v=shift; ref $v eq 'HASH' }
# ---- refcounts: SvREFCNT_inc / SvREFCNT_dec -> Perl_sv_free2 -> Perl_sv_clear ----
sub SvREFCNT_inc { my $id=shift; $OBJ{$id}{rc}++ }
sub SvREFCNT_dec { my $id=shift; my $o=$OBJ{$id}; $o->{rc}--; sv_clear($id) if $o->{rc} <= 0 }
sub sv_clear { my $id=shift; my $o=$OBJ{$id}; return if $o->{freed};
  if ($o->{class} && $o->{class} ne "NONE") { return unless curse($id, 1); $o->{class} = "NONE" }   # Perl_sv_clear: curse(sv, 1), then SvOBJECT_off before magic and body are freed
  sv_kill_backrefs($id);                                                 # Perl_hv_kill_backrefs before the body is freed (sv.c:7281 vs 7370)
  $o->{freed}=1; my @kids = @{$o->{kids}||[]}; $o->{kids}=[];
  for my $k (reverse @kids) { SvREFCNT_dec($k) }                            # av_clear / hv_undef free the members after the container's own magic
}
# ---- S_curse ----
sub curse { my ($id,$check)=@_; my $o=$OBJ{$id};
  my $stash = $o->{class}; my $prev = '';
  while ($stash ne $prev && $stash ne 'NONE') {                       # a destructor that reblesses runs the new class's destructor too
    $prev = $stash;
    $o->{rc}++;                                                       # SV* const tmpref = newRV(sv); SvREADONLY_on(tmpref)
    FZ::Harness::RunDestroy($id, $stash);                                         # call_sv(destructor, G_DISCARD|G_EVAL|G_KEEPERR|G_VOID)
    $o->{rc}--;                                                       # if (SvREFCNT(tmpref) < 2) SvREFCNT(sv)--   (nothing here copies tmpref itself)
    $stash = $o->{class};
  }
  if ($check && $o->{rc} > 0) {                                       # if (check_refcnt && SvREFCNT(sv)) { croak in PL_in_clean_objs; return FALSE }
    die "DIE:DESTROY created new reference to dead object '$o->{class}' during global destruction.\n" if $INCLEAN;
    return 0 }
  return 1 }
sub FZ::Harness::RunDestroy { my ($id,$class)=@_; my $o=$OBJ{$id};
  FZ::Harness::Trace("D" . $o->{id} . ":" . $class . "[" . FZ::Harness::WeakFlags() . "]");
  if ($class eq 'K') { sv_setsv_flags('keep', {ref=>$id}) }                # $main::keep = $_[0]
  elsif ($class eq 'W') { sv_setsv_flags('wk', {ref=>$id}); sv_rvweaken('wk') } # $main::wk = $_[0]; sv_rvweaken($main::wk)
  elsif ($class eq 'R') { $o->{class} = 'P' }                         # bless $_[0], 'P'
  elsif ($class eq 'X') { FZ::Harness::Trace("W") }                                   # die inside DESTROY: G_KEEPERR -> "(in cleanup)" warning, $@ untouched
}
# ---- Perl_sv_kill_backrefs: referrers cleared after DESTROY, each with SvSETMAGIC; a dying set-magic aborts the loop ----
sub sv_kill_backrefs { my $id=shift; my $o=$OBJ{$id}; my @refs = @{$o->{backrefs}||[]}; $o->{backrefs}=[];
  for my $h (@refs) { my $v=$VAR{$h}; next unless $v->{val} && FZ::Harness::IsRef($v->{val}) && $v->{val}{ref} eq $id;
    $v->{val}=undef; $v->{weak}=0;                                    # SvRV_set(referrer, 0); SvROK_off; SvWEAKREF_off
    if ($v->{tied}) { FZ::Harness::Trace("S$h(undef)"); die "DIE:sd\n" if $v->{tied} eq "TX" && $h eq "ta" } } }   # SvSETMAGIC(referrer)
# ---- holders (sv_setsv_flags, sv_set_undef, sv_rvweaken, sv_force_normal) ----
sub sv_setsv_flags { my ($name,$val)=@_; my $v = $VAR{$name} //= {val=>undef};
  my $old = $v->{val}; my $oldweak = $v->{weak};
  if (FZ::Harness::IsRef($val)) { SvREFCNT_inc($val->{ref}); $v->{val} = {ref=>$val->{ref}} } else { $v->{val} = $val }
  $v->{weak}=0;
  if ($old && FZ::Harness::IsRef($old)) { if ($oldweak) { sv_del_backref($old->{ref},$name) } else { SvREFCNT_dec($old->{ref}) } }   # SvREFCNT_dec(old_rv) after the copy
  if ($v->{tied}) { FZ::Harness::Trace("S$name(" . (defined $v->{val} ? 'def' : 'undef') . ")") } }
sub sv_set_undef { my $name=shift; my $v=$VAR{$name}; my $old=$v->{val}; $v->{val}=undef;
  if ($old && FZ::Harness::IsRef($old)) { if ($v->{weak}) { $v->{weak}=0; sv_del_backref($old->{ref},$name) } else { SvREFCNT_dec($old->{ref}) } } }   # sv_set_undef
sub sv_del_backref { my ($id,$name)=@_; my $o=$OBJ{$id}; @{$o->{backrefs}} = grep { $_ ne $name } @{$o->{backrefs}||[]} }
sub sv_rvweaken { my $name=shift; my $v=$VAR{$name}; return unless $v->{val} && FZ::Harness::IsRef($v->{val}) && !$v->{weak};
  $v->{weak}=1; my $id=$v->{val}{ref}; push @{$OBJ{$id}{backrefs}}, $name; SvREFCNT_dec($id) }   # Perl_sv_rvweaken: Perl_sv_add_backref then SvREFCNT_dec
sub sv_force_normal_flags { my $name=shift; my $v=$VAR{$name}; my $old=$v->{val};
  if ($old && FZ::Harness::IsRef($old)) { my $id=$old->{ref}; $v->{val}='plain';   # sv_force_normal_flags -> sv_unref_flags(sv, 0)
    if ($v->{weak}) { $v->{weak}=0; sv_del_backref($id,$name) }
    elsif ($OBJ{$id}{rc} != 1) { SvREFCNT_dec($id) } else { push @TMPS, $id } }   # if (SvREFCNT(target) != 1) dec else sv_2mortal(target)
  else { $v->{val}='plain' } }
# ---- temporaries: sv_2mortal / Perl_free_tmps / cx_pushblock / cx_popblock ----
sub free_tmps { while (@TMPS - 1 > $FLOOR) { my $id = pop @TMPS; SvREFCNT_dec($id) } }        # while (PL_tmps_ix > myfloor) SvREFCNT_dec
sub cx_pushblock { push @CTX, {floor=>$FLOOR, saveix=>scalar(@SAVE)}; $FLOOR = $#TMPS }       # cx->blk_old_tmpsfloor = PL_tmps_floor; PL_tmps_floor = PL_tmps_ix
sub cx_popblock { my $cx = pop @CTX; $FLOOR = $cx->{floor} }                                   # PL_tmps_floor = cx->blk_old_tmpsfloor
sub leave_scope { my $ix = $CTX[-1]{saveix}; while (@SAVE > $ix) { my $e = pop @SAVE;      # LEAVE_SCOPE(cx->blk_oldsaveix): LIFO
    if ($e->[0] eq 'clearsv') { my $v=$VAR{$e->[1]}; my $old=$v->{val}; $v->{val}=undef;   # SAVEt_CLEARSV
      if ($old && FZ::Harness::IsRef($old)) { if ($v->{weak}) { $v->{weak}=0; sv_del_backref($old->{ref},$e->[1]) } else { SvREFCNT_dec($old->{ref}) } } }
    elsif ($e->[0] eq 'local') { sv_setsv_flags('G', $e->[1]) }                                 # SAVEt_SV restore
    elsif ($e->[0] eq 'clearcont') { my $c=$CONT{$e->[1]}; my @k=@{$c->{kids}}; $c->{kids}=[]; SvREFCNT_dec($_) for reverse @k } } }
sub leave_adjust_stacks { my $keep=shift;                             # non-void leave: return values kept, other temps above the floor freed
  my @above = splice(@TMPS, $FLOOR+1); my @kept;
  for my $id (reverse @above) { if (defined $keep && $id eq $keep && !grep { $_ eq $id } @kept) { unshift @kept, $id } else { SvREFCNT_dec($id) } }
  push @TMPS, @kept }
# ---- expressions ----
my %defs;
sub FZ::Harness::EvalExpr { my $e=shift; my ($t,@a)=@$e;
  if ($t eq "new") { my ($id,$cls)=@a; my $key = $id . "#" . (++$defs{seq}); $OBJ{$key} = {rc=>1, class=>$cls, id=>$id, kids=>[], backrefs=>[]}; push @TMPS, $key; return {ref=>$key} }   # each construction is a distinct SV
  if ($t eq 'var') { my $v=$VAR{$a[0]}; return $v->{val} }
  if ($t eq 'plain') { return 'plain' }
  if ($t eq 'cnt') { $defs{cnt} //= 0; return $defs{cnt}++ < 1 ? pp_entersub('cnt', [], 'scalar') : 'plain0' }
  if ($t eq 'call') { return pp_entersub($a[0], $a[1], $a[2] // 'void') }
  die "expr $t" }
my %SUBS = (
  foo => sub { FZ::Harness::Trace("m-foo"); "plain" }, push_weak => sub { "plain" },
  o   => sub { FZ::Harness::EvalExpr(['new','o','O']) },
  cnt => sub { FZ::Harness::EvalExpr(['new','c','O']) },
  vq  => sub { FZ::Harness::RunStmt(['stmt',['myasg','q',['new','q','O']]]); FZ::Harness::RunStmt(['stmt',['expr',['new','h','O']]]); $defs{last} },
  vh  => sub { FZ::Harness::RunStmt(['stmt',['expr',['new','h','O']]]); FZ::Harness::RunStmt(['stmt',['myasg','q',['new','q','O']]]); FZ::Harness::RunStmt(['stmt',['one']]); 'plain' },
);
sub pp_entersub { my ($name,$args,$ctx)=@_;
  my @argv = map { FZ::Harness::EvalExpr($_) } @$args;                            # arguments evaluated on the caller's tmps stack
  cx_pushblock();                                                        # pp_entersub: cx_pushsub / cx_pushblock
  my $ret = $SUBS{$name}->(@argv);
  if ($ctx eq 'void') { leave_scope(); cx_popblock(); return 'plain' }   # pp_leavesub, G_VOID: no drain; the last statement's temp survives to the caller's drain
  my $keep = (FZ::Harness::IsRef($ret) && $TMPS[-1] && $TMPS[-1] eq $ret->{ref}) ? $ret->{ref} : undef;
  leave_adjust_stacks($keep); leave_scope(); cx_popblock(); return $ret } # leave_adjust_stacks before CX_LEAVE_SCOPE
# ---- statements and constructs ----
sub pp_nextstate { free_tmps() }                                         # pp_nextstate: FREETMPS
sub FZ::Harness::RunOp { my $o=shift; my ($t,@a)=@$o;
  if ($t eq 'mark') { FZ::Harness::Trace("m$a[0]") }
  elsif ($t eq 'my') { $VAR{$a[0]} = {val=>undef}; push @SAVE, ['clearsv',$a[0]] }
  elsif ($t eq "ourasg") { my $v = FZ::Harness::EvalExpr($a[1]); sv_setsv_flags($a[0], $v); $defs{last}=$v }
  elsif ($t eq "myasg") { $VAR{$a[0]} = {val=>undef}; push @SAVE, ['clearsv',$a[0]]; my $v = FZ::Harness::EvalExpr($a[1]); sv_setsv_flags($a[0], $v); $defs{last}=$v }
  elsif ($t eq 'assign') { my $v = FZ::Harness::EvalExpr($a[1]); sv_setsv_flags($a[0], $v); $defs{last}=$v }
  elsif ($t eq 'undef') { sv_set_undef($a[0]) }
  elsif ($t eq 'cat') { sv_force_normal_flags($a[0]) }
  elsif ($t eq 'weaken') { sv_rvweaken($a[0]) }
  elsif ($t eq 'tie') { $VAR{$a[0]} = {val=>undef, tied=>$a[1]}; push @SAVE, ['clearsv',$a[0]] }
  elsif ($t eq 'our') { }
  elsif ($t eq 'myarr' || $t eq 'myhash') { my $v = FZ::Harness::EvalExpr($a[1]); $CONT{$a[0]} = {kids=>[]}; if (FZ::Harness::IsRef($v)) { SvREFCNT_inc($v->{ref}); push @{$CONT{$a[0]}{kids}}, $v->{ref} } push @SAVE, ['clearcont',$a[0]] }
  elsif ($t eq 'delete') { my $c=$CONT{$a[0]}; my @k=@{$c->{kids}}; $c->{kids}=[]; SvREFCNT_dec($_) for @k }      # pp_delete in void context: G_DISCARD, freed inside the op
  elsif ($t eq 'clear') { my $c=$CONT{$a[0]}; my @k=@{$c->{kids}}; $c->{kids}=[]; SvREFCNT_dec($_) for reverse @k }   # av_clear: from the top index down
  elsif ($t eq 'expr') { $defs{last} = FZ::Harness::EvalExpr($a[0]) }
  elsif ($t eq 'listctx' || $t eq 'scalarctx') { my $cn = $t eq 'listctx' ? 'l' : 's'; my $v = FZ::Harness::EvalExpr([ @{$a[0]}[0,1,2], $t eq 'listctx' ? 'list' : 'scalar' ]);
    $CONT{$cn} = {kids=>[]}; if (FZ::Harness::IsRef($v)) { SvREFCNT_inc($v->{ref}); push @{$CONT{$cn}{kids}}, $v->{ref} } push @SAVE, ['clearcont',$cn] }
  elsif ($t eq 'die') { die "DIE:$a[0]\n" }
  elsif ($t eq 'local') { my $v = FZ::Harness::EvalExpr($a[0]); push @SAVE, ['local', $VAR{G}{val}]; if ($VAR{G}{val} && FZ::Harness::IsRef($VAR{G}{val})) { SvREFCNT_inc($VAR{G}{val}{ref}) } sv_setsv_flags('G', $v) }
  elsif ($t eq 'one') { $defs{last}='plain' }
  else { die "op $t" } }
sub FZ::Harness::RunStmts { my $stmts=shift; FZ::Harness::RunStmt($_) for @$stmts }
sub FZ::Harness::RunBlock { my ($stmts)=@_; if (@$stmts > 1) { cx_pushblock(); FZ::Harness::RunStmts($stmts); leave_scope(); cx_popblock() } else { FZ::Harness::RunScope($stmts) } }   # OP_ENTER/OP_LEAVE vs OP_SCOPE
sub FZ::Harness::RunScope { my $stmts=shift; for my $s (@$stmts) { if ($s->[0] eq "stmt") { FZ::Harness::RunOp($_) for @{$s}[1..$#$s] } else { FZ::Harness::RunStmt($s) } } }   # OP_SCOPE: the body nextstate is nulled (ex-nextstate), no FREETMPS   # OP_ENTER/OP_LEAVE vs OP_SCOPE
sub FZ::Harness::RunStmt { my $s=shift; my ($t,@a)=@$s;
  if ($t eq 'stmt') { pp_nextstate(); FZ::Harness::RunOp($_) for @a; return }
  if ($t eq 'block') { FZ::Harness::RunBlock($a[0]); return }
  if ($t eq 'if') { pp_nextstate(); my $c = FZ::Harness::EvalExpr($a[0]); if ($c && $c ne 'plain0') { FZ::Harness::RunBlock($a[1]) } return }
  if ($t eq 'while') { pp_nextstate(); cx_pushblock();                        # pp_enterloop
    while (1) { my $c = FZ::Harness::EvalExpr($a[0]); last if !$c || $c eq 'plain0'; FZ::Harness::RunStmts($a[1]); free_tmps() }   # pp_unstack: FREETMPS each iteration
    leave_scope(); cx_popblock(); return }
  if ($t eq "postwhile") { pp_nextstate(); cx_pushblock(); while (1) { my $c = FZ::Harness::EvalExpr($a[1]); last if !$c || $c eq "plain0"; FZ::Harness::RunOp($a[0]); free_tmps() } leave_scope(); cx_popblock(); return }
  if ($t eq "dowhile") { pp_nextstate(); cx_pushblock(); while (1) { FZ::Harness::RunScope($a[0]); my $c = FZ::Harness::EvalExpr($a[1]); last if !$c || $c eq "plain0" } leave_scope(); cx_popblock(); return }   # do BLOCK while: enter/leave around the loop, body is OP_SCOPE, no unstack
  if ($t eq "cfor") { pp_nextstate(); cx_pushblock(); while (1) { my $c = FZ::Harness::EvalExpr($a[0]); last if !$c || $c eq "plain0"; if ($a[2]) { FZ::Harness::RunScope($a[1]) } else { FZ::Harness::RunStmts($a[1]) } free_tmps() } leave_scope(); cx_popblock(); return }   # step present: body+step form one OP_SCOPE with the leading nextstate nulled; no step: live nextstate
  if ($t eq 'grep') { pp_nextstate(); $CONT{g} = {kids=>[]}; push @SAVE, ['clearcont','g'];
    for my $i (1..2) { cx_pushblock(); $VAR{t} = {val=>undef}; push @SAVE, ["clearsv","t"]; my $v = FZ::Harness::EvalExpr(["new",$a[1],$a[0]]); sv_setsv_flags("t",$v); leave_scope(); cx_popblock(); free_tmps() } return }   # pp_grepwhile: ENTER/LEAVE per item, then FREETMPS   # grep_item ENTER/LEAVE: the previous item is left when the next begins; the last is never left   # pp_grepwhile: FREETMPS per item
  if ($t eq 'eval') { pp_nextstate(); cx_pushblock(); my $depth = @CTX; my $ok = eval { FZ::Harness::RunStmts($a[0]); 1 };
    if ($ok) { leave_scope(); cx_popblock(); FZ::Harness::Trace("E:") }
    else { my $msg = $@; $msg =~ s/^DIE://; $msg =~ s/\n\z//;
      while (@CTX >= $depth) { leave_scope(); cx_popblock() }            # Perl_die_unwind: dounwind to the eval frame, each LEAVE_SCOPE + popblock
      free_tmps(); FZ::Harness::Trace("E:$msg") }                                      # FREETMPS before ERRSV is set
    return }
  die "stmt $t" }
# ---- Perl_sv_clean_objs: within-pass order is arena order and out of scope; the rows are compared as sets ----
sub sv_clean_objs {
  FZ::Harness::Trace("END"); $INCLEAN=1;
  eval {
    for my $name (sort keys %VAR) { my $v=$VAR{$name}; next unless $v->{val} && FZ::Harness::IsRef($v->{val});          # visit(do_clean_objs, SVf_ROK, SVf_ROK)
      if ($v->{weak}) { $v->{weak}=0; sv_del_backref($v->{val}{ref},$name); $v->{val}=undef } else { my $id=$v->{val}{ref}; $v->{val}=undef; SvREFCNT_dec($id) } }
    for my $c (sort keys %CONT) { my @k=@{$CONT{$c}{kids}}; $CONT{$c}{kids}=[]; SvREFCNT_dec($_) for @k }
    for my $id (sort keys %OBJ) { next if $OBJ{$id}{freed} || $OBJ{$id}{class} eq "NONE"; curse($id, 0) }                                     # visit(do_curse, SVs_OBJECT, SVs_OBJECT)
    1 } or do { my $m=$@; $m =~ s/^DIE://; $m =~ s/\n\z//; FZ::Harness::Trace($m) };
}
sub FZ::Harness::Run { my ($ir,$opt)=@_; FZ::Harness::ResetState(); @WEAKNAMES = @{$opt->{weak}||[]}; %defs=();
  cx_pushblock(); my $ok = eval { FZ::Harness::RunStmts($ir); pp_nextstate(); FZ::Harness::Trace("m-end"); 1 };
  if (!$ok) { my $m=$@; $m =~ s/^DIE://; FZ::Harness::Trace("E:$m") }
  # end of main: file-scope lexicals and temps are released by perl_destruct before/within global destruction
  leave_scope(); cx_popblock(); free_tmps(); sv_clean_objs();   # end of main: the main CV scope is left (LIFO clears), then END blocks, then sv_clean_objs
  return join("", map { "$_\n" } @TRACE) }
1;
