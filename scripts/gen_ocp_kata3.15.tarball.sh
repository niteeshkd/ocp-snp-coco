#!/bin/bash
KATA_CONTAINERS_RELEASE_TAG="3.15.0"
KATA_TARBALL_PATH="https://github.com/kata-containers/kata-containers/releases/download/${KATA_CONTAINERS_RELEASE_TAG}/kata-static-${KATA_CONTAINERS_RELEASE_TAG}-amd64.tar.xz"
KATA_CONTAINERS_REPO="https://github.com/kata-containers/kata-containers.git"

PAUSECONT_FIX_REPO="https://github.com/niteeshkd/kata-containers.git"
PAUSECONT_FIX_BRANCH="nd_pause_3.15"
PAUSECONT_FIX_COMMIT="b769f16cf2330aba35f39601baae91af9f95280e"

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
sudo tar -xvf ../${kata_tarball}
popd

# Files to be replaced/updated
KATA_COCO_INITRD=$(readlink -f ${KATADIR}/opt/kata/share/kata-containers/kata-containers-initrd-confidential.img)
KATA_SNP_CONFIG=${KATADIR}/opt/kata/share/defaults/kata-containers/configuration-qemu-snp.toml


# Clone kata-containers and add the fixes
echo "Clone ${KATA_CONTAINERS_REPO}:${KATA_CONTAINERS_RELEASE_TAG} and add Fixes ........... "
git clone --branch ${KATA_CONTAINERS_RELEASE_TAG}  --depth 1 ${KATA_CONTAINERS_REPO}
pushd kata-containers

git remote add PAUSECONT_FIX_REPO ${PAUSECONT_FIX_REPO}
git fetch PAUSECONT_FIX_REPO ${PAUSECONT_FIX_BRANCH}
git cherry-pick ${PAUSECONT_FIX_COMMIT}

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
script -fec 'sudo -E USE_DOCKER=true ./initrd_builder.sh "${ROOTFS_DIR}"'
sudo cp kata-containers-initrd.img ${KATA_COCO_INITRD}
popd

popd

# Update KATA SNP config file
echo "Update ${KATA_SNP_CONFIG} ........... "
sudo sed -i 's/^path[[:space:]]=/path = \"\/usr\/libexec\/qemu-kvm\" #/g' ${KATA_SNP_CONFIG}
sudo sed -i 's/^firmware[[:space:]]=/firmware = \"\/usr\/share\/edk2\/ovmf\/OVMF.amdsev.fd\" #/g' ${KATA_SNP_CONFIG}

# Repackage kata tarball 
echo "Repackage kata tarball ........... "
pushd $KATADIR
sudo tar cvfJ ${WORKDIR}/ocp_${kata_tarball} .
popd
ls -l ${WORKDIR}/ocp_${kata_tarball}
cd ${WORKDIR}

#sudo rm -fr ${TMPDIR}

