#! /bin/bash

cd "`dirname "$0"`"
top="`pwd`"
stage="$top/stage"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

OPENSSL_SOURCE_DIR="openssl-git"

if [ -z "$AUTOBUILD" ] ; then
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="`cygpath -u "$AUTOBUILD"`"
fi

# load autbuild provided shell functions and variables
set +x
eval "`"$AUTOBUILD" source_environment`"
set -x

build_unix()
{
    target="$1"
    reltype="$2"
    shift 2

    # "shared" means build shared and static, instead of just static.
    ./Configure no-idea no-mdc2 no-rc5 no-gost enable-tlsext $* \
      --with-zlib-include="$stage/packages/include/zlib" --with-zlib-lib="$stage/packages/lib/release" \
      --prefix="$stage" --libdir="lib/$reltype" $target

    # Need to regenerate dependencies after reconfigure.
    make depend
    # Clean up stuff from a previous compile.
    make clean
    # Parallel building is broken for this package. Only use one core.
    make build_libs
    make build_apps
    make openssl.pc
    make libssl.pc
    make libcrypto.pc
    # Make sure INSTALL_PREFIX is empty, so that we install in --prefix ($stage) and not in $INSTALL_PREFIX/$stage.
    make INSTALL_PREFIX= install_sw

    # Fix the three pkgconfig files.
    find "$stage/lib/$reltype/pkgconfig" -type f -name '*.pc' -exec sed -i -e 's%'$stage'%${PREBUILD_DIR}%g' {} \;

    if expr match "$*" '.* shared' >/dev/null; then
        # By default, 'make install' leaves even the user write bit off.
        # This causes trouble for us down the road, along about the time
        # the consuming build tries to strip libraries.
        chmod u+w "$stage/lib/$reltype"/libcrypto.so.* "$stage/lib/$reltype"/libssl.so.*
    fi
}

build_windows()
{
    target="$1"
    reltype="$2"
    shift 2

    if [ "$reltype" = "debug" ] ; then
        cfgpfx="debug-" # 'perl Configure VC-WIN[arch] ...' must be changed to 'perl Configure debug-VC-WIN[arch] ...'
         mkpfx="debug"   # 'perl util/mk1mf.pl dll VC-WIN[arch] ...' must be changed to 'perl util/mk1mf.pl debug dll VC-WIN[arch] ...'
         outpfx=".dbg"   # 'out32dll' and 'tmp32dll' must be changed to 'out32dll.dbg' and 'tmp32dll.dbg '
    fi

    # Building openssl creates a mess of stale files. Kill them all before building, as they may interfere. No, nmake clean does not clean them all up.
    rm -f NUL
    rm -f MINFO
    rm -f Makefile
    rm -f ms/*.{mak,def,obj,asm,rc}
    rm -rf out32dll$outpfx
    rm -rf tmp32dll$outpfx

    if [ "$AUTOBUILD_PLATFORM" = "windows64" ] ; then
        config="VC-WIN64A"
        # Not specifying no-asm results in missing symbols, even if you fix the chain of bugs in openssl that prevent the link stage from even being reached.
        opt="no-asm"
        # Even with no-asm specified, uptable.obj still needs to be generated from assembly.
        perl ms/uplink-x86_64.pl nasm > ms/uptable.asm
        nasm -f win64 -o ms/uptable.obj ms/uptable.asm
    else
        config="VC-WIN32"
    fi

    perl Configure $cfgpfx$config $opt $*
    perl util/mkfiles.pl > MINFO
    perl util/mk1mf.pl $mkpfx $opt dll $config > ms/ntdll.mak

    perl util/mkdef.pl 32 libeay > ms/libeay32.def
    perl util/mkdef.pl 32 ssleay > ms/ssleay32.def

    export CL=/MP
    nmake -f ms/ntdll.mak

    # Stage archives
    mkdir -p "$stage/lib/$reltype"
    cp out32dll$outpfx/{libeay32,ssleay32}.{dll,lib} "$stage/lib/$reltype"

    nmake -f ms/ntdll.mak clean
}

pushd "$OPENSSL_SOURCE_DIR"
    case $AUTOBUILD_PLATFORM in
        windows|windows64)
            load_vsvars

            build_windows $AUTOBUILD_PLATFORM release
            build_windows $AUTOBUILD_PLATFORM debug

            # Stage headers
            mkdir -p $stage/include/openssl
            cp -af inc32/openssl/*.h "${stage}"/include/openssl/
        ;;
        darwin)
            build_unix darwin-i386-cc release no-shared
            build_unix debug-darwin-i386-cc debug no-shared
        ;;
        linux)
            build_unix linux-generic32 release threads no-shared -fno-stack-protector
            build_unix debug-linux-generic32 debug threads no-shared -fno-stack-protector
        ;;
        linux64)
            build_unix linux-x86_64 release threads shared zlib-dynamic -fno-stack-protector
            build_unix debug-linux-x86_64 debug threads shared zlib-dynamic -fno-stack-protector
        ;;

        *)
          fail "Unknown platform $AUTOBUILD_PLATFORM."
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/openssl.txt"
popd
pass

