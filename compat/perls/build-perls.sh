#!/bin/bash
# Builds the six perl 5.44.0 interpreters the harness needs, using perlbrew from a GitHub tag
# tarball (CPAN downloads are not required).  Two families, the unthreaded one and the one built
# with -Dusethreads, each in three variants:
#
#   perl-5.44.0                     stock, the oracle
#   perl-5.44.0-noreuse             noreuse.patch: freed SV heads never return to the free list
#   perl-5.44.0-descending          descending.patch: each new SV arena's free list is threaded high to low
#   perl-5.44.0-threads             the same three with -Dusethreads, the oracle for probes that
#   perl-5.44.0-threads-noreuse     require ithreads and the configuration cross-check for the rest
#   perl-5.44.0-threads-descending
#
# Usage: build-perls.sh [--prepare-only] [--jobs N] [--family plain|threads|all]
#   --prepare-only  clone the tag, apply both patches, and create the three source tarballs, but do
#                   not compile. Useful for checking that the patches still apply.
#   --family        build only one family (default all).
#
# Environment: PERLBREW_ROOT (default /opt/perlbrew), WORK (default /tmp/oracle-build).
# Each build takes 15-30 minutes on one core. Status files: $WORK/<name>.DONE or $WORK/<name>.FAILED.

set -u
PREPARE_ONLY=0
JOBS=$(nproc)
FAMILIES="plain threads"
while [ $# -gt 0 ]; do
    case "$1" in
        --prepare-only) PREPARE_ONLY=1 ;;
        --jobs) shift; JOBS="$1" ;;
        --family) shift
            case "$1" in
                plain|threads) FAMILIES="$1" ;;
                all) FAMILIES="plain threads" ;;
                *) echo "unknown family $1" >&2; exit 2 ;;
            esac ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=5.44.0
export PERLBREW_ROOT=${PERLBREW_ROOT:-/opt/perlbrew}
export PERLBREW_HOME=$PERLBREW_ROOT/home
WORK=${WORK:-/tmp/oracle-build}
mkdir -p "$WORK"
cd "$WORK" || exit 1

fail() { echo "FAILED: $1" >&2; echo "$1" > "$WORK/$2.FAILED"; exit 1; }

if [ ! -d "$WORK/src" ]; then
    git init "$WORK/src" || fail clone all
    git -C "$WORK/src" fetch --depth 1 https://github.com/Perl/perl5.git "refs/tags/v$VERSION" || fail clone all
    git -C "$WORK/src" checkout --detach FETCH_HEAD || fail clone all
fi

# Stage one source tree per variant. The directory inside each tarball must be named perl-VERSION.
# Both families build from the same three tarballs; only the Configure flags differ.
base=$(git -C "$WORK/src" rev-parse HEAD)
for variant in stock noreuse descending; do
    if [ "$variant" != stock ]; then
        git -C "$WORK/src" apply --index "$HERE/$variant.patch" || fail "patch $variant" "$variant"
        git -C "$WORK/src" -c user.name=oracle -c user.email=oracle@localhost commit -q -m "$variant" || fail "commit $variant" "$variant"
    fi
    git -C "$WORK/src" archive --format=tar.gz --prefix="perl-$VERSION/" -o "$WORK/perl-$VERSION-$variant.tar.gz" HEAD || fail "tar $variant" "$variant"
    git -C "$WORK/src" reset -q --hard "$base"
    echo "prepared $WORK/perl-$VERSION-$variant.tar.gz"
done
[ "$PREPARE_ONLY" = 1 ] && exit 0

if [ ! -x "$PERLBREW_ROOT/bin/perlbrew" ]; then
    curl -sSL https://raw.githubusercontent.com/gugod/App-perlbrew/master/perlbrew-install -o "$WORK/perlbrew-install" || fail curl all
    bash "$WORK/perlbrew-install" || fail "perlbrew install" all
fi
set +u; source "$PERLBREW_ROOT/etc/bashrc" || fail bashrc all; set -u

for family in $FAMILIES; do
    for variant in stock noreuse descending; do
        name="perl-$VERSION"
        flags=()
        if [ "$family" = threads ]; then
            name="$name-threads"
            flags=(-Dusethreads)
        fi
        [ "$variant" != stock ] && name="$name-$variant"
        rm -f "$WORK/$name.DONE" "$WORK/$name.FAILED"
        if [ -x "$PERLBREW_ROOT/perls/$name/bin/perl" ]; then
            echo "already built: $name"
        else
            echo "building $name with -j$JOBS ${flags[*]:-} (perlbrew logs under $PERLBREW_ROOT/build.*.log)"
            start=$(date +%s)
            perlbrew --notest install "$WORK/perl-$VERSION-$variant.tar.gz" --as "$name" -j "$JOBS" ${flags[@]+"${flags[@]}"} || fail "build $name" "$name"
            echo "built $name in $(( $(date +%s) - start ))s"
        fi
        "$PERLBREW_ROOT/perls/$name/bin/perl" -e 'print "$]\n"' > "$WORK/$name.DONE"
        echo "$name: perl $(cat "$WORK/$name.DONE") $("$PERLBREW_ROOT/perls/$name/bin/perl" -V:useithreads)"
    done
done

echo "profile of perl-$VERSION:"
"$PERLBREW_ROOT/perls/perl-$VERSION/bin/perl" -V:ivsize -V:nvsize -V:usemymalloc -V:d_malloc_good_size -V:d_malloc_size
