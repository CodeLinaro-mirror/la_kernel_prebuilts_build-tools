#!/bin/bash -ex

OUT_DIR=${OUT_DIR:-out}
TOP=$(pwd)
OS=linux

build_soong=1
use_musl=false
clean=true
while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                resume) clean= ;;
                musl) use_musl=true ;;
                *) echo "Unknown option --${OPTARG}"; exit 1 ;;
            esac;;
        *) echo "'${opt}' '${OPTARG}'"
    esac
done

# Use toybox and other prebuilts even outside of the build (test running, go, etc)
export PATH=${TOP}/prebuilts/build-tools/path/${OS}-x86:$PATH

if [ -n ${build_soong} ]; then
    SOONG_OUT=${OUT_DIR}/soong
    SOONG_HOST_OUT=${OUT_DIR}/soong/host/${OS}-x86
    [[ -z "${clean}" ]] || rm -rf ${SOONG_OUT}
    mkdir -p ${SOONG_OUT}
    cat > ${SOONG_OUT}/soong.variables << EOF
{
    "Allow_missing_dependencies": true,
    "HostArch":"x86_64",
    "HostMusl": $use_musl
}
EOF
    SOONG_BINARIES=(
        avbtool
        blk_alloc_to_base_fs
        build_image
        build_super_image
        certify_bootimg
        depmod
        dtc
        e2fsck
        e2fsdroid
        external_updater
        fec
        fsck.erofs
        img2simg
        interceptor
        interceptor_analysis
        lpmake
        lz4
        mkbootfs
        mkdtboimg
        mkdtimg
        mke2fs
        mkfs.erofs
        mkuserimg_mke2fs
        simg2img
        soong_zip
        stg
        stgdiff
        swig
        tune2fs
        ufdt_apply_overlay
    )

    # TODO(b/354773024): pahole needs argp
    if [[ ${use_musl} != "true" ]]; then
        SOONG_BINARIES+=(pahole)
    fi

    SOONG_LIBRARIES=(
        libcrypto-host.so
        libdw.so
        libelf.so
        libinterceptor.so
    )

    binaries="${SOONG_BINARIES[@]/#/${SOONG_HOST_OUT}/bin/}"
    libraries="${SOONG_LIBRARIES[@]/#/${SOONG_HOST_OUT}/lib64/}"

    # TODO: When we have a better method of extracting zips from Soong, use that.
    py3_stdlib_zip="${SOONG_OUT}/.intermediates/external/python/cpython3/Lib/py3-stdlib-zip/gen/py3-stdlib.zip"

    musl_x86_64_sysroot=""
    if [[ ${use_musl} = "true" ]]; then
        musl_x86_64_sysroot="${SOONG_OUT}/.intermediates/external/musl/libc_musl_sysroot/linux_musl_x86_64/gen/libc_musl_sysroot.zip"
    fi

    # Build everything
    build/soong/soong_ui.bash --make-mode --skip-make \
        ${binaries} \
        ${libraries} \
        ${py3_stdlib_zip} \
        ${musl_x86_64_sysroot} \

    # Stage binaries
    mkdir -p ${SOONG_OUT}/dist/bin
    cp ${binaries} ${SOONG_OUT}/dist/bin/
    cp -R ${SOONG_HOST_OUT}/lib* ${SOONG_OUT}/dist/

    # Stage include files
    include_dir=${SOONG_OUT}/dist/include
    mkdir -p ${include_dir}/openssl/
    cp -a ${TOP}/external/boringssl/include/openssl/* ${include_dir}/openssl/

    # The elfutils header locations are messy; just make them match
    # common Linux distributions, as this is what Linux expects
    mkdir -p ${include_dir}/elfutils
    cp -a ${TOP}/external/elfutils/libelf/gelf.h ${include_dir}/
    cp -a ${TOP}/external/elfutils/libelf/libelf.h ${include_dir}/
    cp -a ${TOP}/external/elfutils/libelf/nlist.h ${include_dir}/
    cp -a ${TOP}/external/elfutils/libelf/elf-knowledge.h ${include_dir}/elfutils/
    cp -a ${TOP}/external/elfutils/version.h ${include_dir}/elfutils/
    # libdw
    cp -a ${TOP}/external/elfutils/libdw/dwarf.h ${include_dir}/
    cp -a ${TOP}/external/elfutils/libdw/libdw.h ${include_dir}/elfutils/
    cp -a ${TOP}/external/elfutils/libdwfl/libdwfl.h ${include_dir}/elfutils/

    # Stage share files
    share_dir=${SOONG_OUT}/dist/share
    mkdir -p ${share_dir}

    # Copy over the testkey for signing
    mkdir -p ${share_dir}/avb
    cp -a ${TOP}/external/avb/test/data/testkey_rsa2048.pem ${share_dir}/avb/

    # Copy over the swig library files
    mkdir -p ${share_dir}/swig
    cp -a ${TOP}/external/swig/Lib/* ${share_dir}/swig/

    if [[ ${use_musl} = "true" ]]; then
        cp ${musl_x86_64_sysroot} ${SOONG_OUT}/musl-sysroot-x86_64-unknown-linux-musl.zip
    fi

    # Patch dist dir
    (
      cd ${SOONG_OUT}/dist/
      ln -sf libcrypto-host.so lib64/libcrypto.so
    )

    # Package prebuilts
    (
        cd ${SOONG_OUT}/dist
        zip -qryX build-prebuilts.zip *
    )
fi

if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR} || true

    if [ -n ${build_soong} ]; then
        cp ${SOONG_OUT}/dist/build-prebuilts.zip ${DIST_DIR}/

        if [[ ${use_musl} = "true" ]]; then
            cp ${SOONG_OUT}/musl-sysroot-x86_64-unknown-linux-musl.zip ${DIST_DIR}/
        fi
    fi
fi

exit 0
