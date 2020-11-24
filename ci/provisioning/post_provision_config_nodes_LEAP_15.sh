#!/bin/bash

url_to_repo() {
    local URL="$1"

    local repo=${URL#*://}
    repo="${repo//%252F/_}"

    echo "$repo"
}
post_provision_config_nodes() {
    time zypper --non-interactive install dnf

    local dnf_repo_args="--disablerepo=*"
    dnf_repo_args+=" --enablerepo=repo.dc.hpdd.intel.com_repository_*"
    dnf_repo_args+=",build.hpdd.intel.com_job_daos-stack*"

    # Reserve port ranges 31416-31516 for DAOS and CART servers
    echo 31416-31516 > /proc/sys/net/ipv4/ip_local_reserved_ports

    if $CONFIG_POWER_ONLY; then
        rm -f /etc/dnf.repos.d/*.hpdd.intel.com_job_daos-stack_job_*_job_*.repo
        dnf -y erase fio fuse ior-hpc mpich-autoload               \
                     ompi argobots cart daos daos-client dpdk      \
                     fuse-libs libisa-l libpmemobj mercury mpich   \
                     openpa pmix protobuf-c spdk libfabric libpmem \
                     libpmemblk munge-libs munge slurm             \
                     slurm-example-configs slurmctld slurm-slurmmd
    fi
    if [ -n "$DAOS_STACK_GROUP_REPO" ]; then
         rm -f /etc/dnf.repos.d/*"$DAOS_STACK_GROUP_REPO"
         dnf config-manager \
             --add-repo="$REPOSITORY_URL$DAOS_STACK_GROUP_REPO"
    fi

    if [ -n "$DAOS_STACK_LOCAL_REPO" ]; then
        rm -f /etc/dnf.repos.d/*"$DAOS_STACK_LOCAL_REPO"
        local repo="$REPOSITORY_URL$DAOS_STACK_LOCAL_REPO"
        dnf config-manager --add-repo="${repo}"
        dnf config-manager --save --setopt=*"$(url_to_repo "$repo")".gpgcheck=0
    fi

    if [ -n "$INST_REPOS" ]; then
        for repo in $INST_REPOS; do
            branch="master"
            build_number="lastSuccessfulBuild"
            if [[ $repo = *@* ]]; then
                branch="${repo#*@}"
                repo="${repo%@*}"
                if [[ $branch = *:* ]]; then
                    build_number="${branch#*:}"
                    branch="${branch%:*}"
                fi
            fi
            local repo="${JENKINS_URL}"job/daos-stack/job/"${repo}"/job/"${branch//\//%252F}"/"${build_number}"/artifact/artifacts/centos7/
            dnf config-manager --add-repo="${repo}"
            dnf config-manager --save --setopt=*"$(url_to_repo "$repo")".gpgcheck=0
        done
    fi
    if [ -n "$INST_RPMS" ]; then
        # shellcheck disable=SC2086
        dnf -y erase $INST_RPMS
    fi
    for gpg_url in $GPG_KEY_URLS; do
      rpm --import "$gpg_url"
    done
    rm -f /etc/profile.d/openmpi.sh
    rm -f /tmp/daos_control.log
    dnf -y install lsb-release

    # monkey-patch lua-lmod
    if ! grep MODULEPATH=".*"/usr/share/modules /etc/profile.d/lmod.sh; then \
        sed -e '/MODULEPATH=/s/$/:\/usr\/share\/modules/'                     \
               /etc/profile.d/lmod.sh;                                        \
    fi

    # force install of avocado 52.1
    dnf -y erase avocado{,-common} python2-avocado{,-plugins-{output-html,varianter-yaml-to-mux}}
    dnf -y install {avocado-common,python2-avocado{,-plugins-{output-html,varianter-yaml-to-mux}}}-52.1

    # shellcheck disable=SC2086
    if [ -n "$INST_RPMS" ] &&
       ! dnf -y $dnf_repo_args install $INST_RPMS; then
        rc=${PIPESTATUS[0]}
        for file in /etc/dnf.repos.d/*.repo; do
            echo "---- $file ----"
            cat "$file"
        done
        exit "$rc"
    fi

    # now make sure everything is fully up-to-date
    time dnf -y upgrade --exclude fuse,mercury,daos,daos-\*
}
