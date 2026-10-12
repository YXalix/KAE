#!/bin/bash
set -e
# Get the directory of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"

function build_driver()
{
    lsmod | grep -q "^hisi_migration"       && modprobe -r hisi_migration
    lsmod | grep -q "^hisi_acc_vfio_pci"    && modprobe -r hisi_acc_vfio_pci
    lsmod | grep -q "^hisi_zip"             && modprobe -r hisi_zip
    lsmod | grep -q "^hisi_hpre"            && modprobe -r hisi_hpre
    lsmod | grep -q "^hisi_sec2"            && modprobe -r hisi_sec2
    lsmod | grep -q "^hisi_qm"              && modprobe -r hisi_qm
    lsmod | grep -q "^uacce"                && modprobe -r uacce

    cd ${KAE_KERNEL_DIR}

    if [ "$1" = "migration" ]; then
        make ENABLE_MIGRATION=y -j"$(kae_jobs)"
        make nosva ENABLE_MIGRATION=y DRACUT=${DRACUT_MAKEVAR}
    else
        make -j"$(kae_jobs)"
        make nosva DRACUT=${DRACUT_MAKEVAR} #默认使用nosva模式
    fi
    # make install
    # chmod 666 /dev/hisi_*
}

function build_driver_sva()
{
    cd ${KAE_KERNEL_DIR}
    make -j"$(kae_jobs)"
    # make nosva #默认使用nosva模式
    if [ "$1" = "migration" ]; then
        make install ENABLE_MIGRATION=y DRACUT=${DRACUT_MAKEVAR}
    else
        make install DRACUT=${DRACUT_MAKEVAR} #默认使用nosva模式
    fi
    chmod 666 /dev/hisi_*
}

function driver_clean()
{
    cd ${KAE_KERNEL_DIR}
    if [ "$1" = "migration" ]; then
        make uninstall ENABLE_MIGRATION=y DRACUT=${DRACUT_MAKEVAR}
    else
        make uninstall DRACUT=${DRACUT_MAKEVAR} #默认使用nosva模式
    fi
    make clean
}

function driver_delete()
{
    cd ${KAE_KERNEL_DIR}
    make delete-modules
}

function driver_check()
{
    cd ${KAE_KERNEL_DIR}
    make check
}

# Main execution logic
check_environment
build_check_OS_version

# On Debian/Ubuntu, prefer the kernel's in-tree uacce/hisi_zip modules and
# skip the out-of-tree build; KAE's driver trees track OLK kernels and may
# not compile against distro kernels. Set KAE_FORCE_DRIVER_BUILD=1 to force.
if [ "${KAE_IS_DEBIAN}" = "1" ] && [ "${KAE_FORCE_DRIVER_BUILD:-0}" != "1" ]; then
    if kae_in_tree_zip_modules_present; then
        kae_info "in-tree uacce/hisi_zip kernel modules detected; skipping KAE out-of-tree driver build (set KAE_FORCE_DRIVER_BUILD=1 to override)"
        modprobe uacce 2>/dev/null || true
        modprobe hisi_qm 2>/dev/null || true
        modprobe hisi_zip 2>/dev/null || true
        exit 0
    fi
fi

# Building kernel modules needs headers for the running kernel:
# linux-headers-$(uname -r) on Debian/Ubuntu, kernel-devel on RPM distros.
if [ ! -e "/lib/modules/$(uname -r)/build/Makefile" ]; then
    if [ "${KAE_IS_DEBIAN}" = "1" ]; then
        kae_die "kernel headers for $(uname -r) not found; install with: apt install linux-headers-\$(uname -r)"
    else
        kae_die "kernel-devel for $(uname -r) not found; install with: yum install kernel-devel-\$(uname -r)"
    fi
fi

# Debian/Ubuntu manage initramfs with initramfs-tools, not dracut; stub the
# dracut calls inside the driver Makefile instead of rebuilding initramfs.
DRACUT_MAKEVAR="dracut"
if [ "${KAE_IS_DEBIAN}" = "1" ]; then
    DRACUT_MAKEVAR="true"
fi

# Handle arguments
ACTION=$1
OPTION=$2

case "$ACTION" in
    "driver")
        if [ "$OPTION" = "clean" ]; then  
            driver_clean
        elif [ "$OPTION" = "sva" ]; then  
            build_driver_sva
        elif [ "$OPTION" = "check" ]; then  
            driver_check
        elif [ "$OPTION" = "delete" ]; then  
            driver_delete
        else  
            build_driver
        fi  
        ;;
    "driver_migration")
        if [ "$OPTION" = "clean" ]; then  
            driver_clean migration
        elif [ "$OPTION" = "sva" ]; then  
            build_driver_sva migration
        elif [ "$OPTION" = "check" ]; then  
            driver_check
        elif [ "$OPTION" = "delete" ]; then  
            driver_delete
        else  
            build_driver migration
        fi  
        ;;
    *)
        echo "Usage: $0 {driver|driver_migration} [clean|sva|check|delete]"
        exit 1
        ;;
esac
