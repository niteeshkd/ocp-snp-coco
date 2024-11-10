#!/bin/bash
KATA_CONTAINERS_RELEASE_TAG="3.9.0"
KATA_TARBALL_PATH="https://github.com/kata-containers/kata-containers/releases/download/${KATA_CONTAINERS_RELEASE_TAG}/kata-static-${KATA_CONTAINERS_RELEASE_TAG}-amd64.tar.xz"
KATA_CONTAINERS_REPO="https://github.com/kata-containers/kata-containers.git"

KATASHIM_FIX_REPO="https://github.com/ryansavino/kata-containers.git"
KATASHIM_FIX_BRANCH="rhel95-snp-testing"
KATASHIM_FIX_COMMIT="5525b50b3"

PAUSECONT_FIX_REPO="https://github.com/niteeshkd/kata-containers.git"
PAUSECONT_FIX_BRANCH="nd_ocp_snp_pause_3.9.0"
PAUSECONT_FIX_COMMIT="c0b119dcd"

WORKDIR=${PWD}

TMPDIR=${WORKDIR}/tmp_$(date +"%Y%m%d_%H%M")
mkdir -p $TMPDIR
cd $TMPDIR

# Get orig kata-tarball and untar it.
echo "Get ${KATA_TARBALL_PATH} ........... "
wget ${KATA_TARBALL_PATH}
kata_tarball=${KATA_TARBALL_PATH##*/}
KATADIR=${TMPDIR}/kata
mkdir -p $KATADIR
pushd $KATADIR
tar -xvf ../${kata_tarball}
popd

# Files to be replaced/updated
KATA_COCO_INITRD=$(readlink -f ${KATADIR}/opt/kata/share/kata-containers/kata-containers-initrd-confidential.img)
KATA_SHIM=${KATADIR}/opt/kata/bin/containerd-shim-kata-v2
KATA_MONITOR=${KATADIR}/opt/kata/bin/kata-monitor
KATA_RUNTIME=${KATADIR}/opt/kata/bin/kata-runtime
KATA_SNP_CONFIG=${KATADIR}/opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml


# Clone kata-containers 3.9.0 and add the fixes
echo "Clone ${KATA_CONTAINERS_REPO}:${KATA_CONTAINERS_RELEASE_TAG} and add Fixes ........... "
git clone --branch ${KATA_CONTAINERS_RELEASE_TAG}  --depth 1 ${KATA_CONTAINERS_REPO}
pushd kata-containers

git remote add KATASHIM_FIX_REP ${KATASHIM_FIX_REPO}
git fetch KATASHIM_FIX_REP ${KATASHIM_FIX_BRANCH}
git cherry-pick ${KATASHIM_FIX_COMMIT}

git remote add PAUSECONT_FIX_REPO ${PAUSECONT_FIX_REPO}
git fetch PAUSECONT_FIX_REPO ${PAUSECONT_FIX_BRANCH}
git cherry-pick ${PAUSECONT_FIX_COMMIT}

# Build and update kata shim
echo "Build and update kata shim ........... "
make -C src/runtime
cp src/runtime/containerd-shim-kata-v2 ${KATA_SHIM}
cp src/runtime/kata-monitor ${KATA_MONITOR}
cp src/runtime/kata-runtime ${KATA_RUNTIME}

# Build pause container 
echo "Build pause container ........... "
pushd tools/packaging/static-build/pause-image
./build.sh
popd

# Untar initrd as 'sudo su' user and replace pause_bundle 
echo "Replace pause_bundle in intrd ........... "
export ROOTFS_DIR=${TMPDIR}/initrd
mkdir -p ${ROOTFS_DIR}
pushd ${ROOTFS_DIR}
zcat ${KATA_COCO_INITRD} | sudo cpio -idmv
pause_bundle_owner=`ls -l | awk '/pause_bundle/ {print $3":"$4}'`
sudo rm -fr pause_bundle/*
sudo cp -r ${TMPDIR}/kata-containers/tools/packaging/static-build/pause-image/pause_bundle/* pause_bundle/
sudo chown -R ${pause_bundle_owner} pause_bundle
popd

# Build and update initrd with new pause_bundle
echo "Build and update initrd with new pause_bundle ........... "
pushd ${TMPDIR}/kata-containers/tools/osbuilder/initrd-builder
script -fec 'sudo -E AGENT_INIT=yes USE_DOCKER=true ./initrd_builder.sh "${ROOTFS_DIR}"'
cp kata-containers-initrd.img ${KATA_COCO_INITRD}
popd

popd

# Update KATA SNP config file
echo "Update ${KATA_SNP_CONFIG} ........... "
sed -i 's/^path[[:space:]]=/path = \"\/usr\/libexec\/qemu-kvm\" #/g' ${KATA_SNP_CONFIG}
sed -i 's/^firmware[[:space:]]=/firmware = \"\/usr\/share\/edk2\/ovmf\/OVMF.amdsev.fd\" #/g' ${KATA_SNP_CONFIG}

# Repackage kata tarball 
echo "Repackage kata tarball ........... "
pushd $KATADIR
tar cvfJ ${WORKDIR}/ocp_${kata_tarball} .
popd

ls -l ${WORKDIR}/ocp_${kata_tarball}

