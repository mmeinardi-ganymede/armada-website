#!/bin/bash

#
# This script is meant for quick & easy install/upgrade via:
#   bash <(curl -sL http://armada.sh/install)
# or:
#   bash <(wget -qO- http://armada.sh/install)
#

ARMADA_BASE_URL='http://armada.sh/install/'
ARMADA_REPOSITORY=dockyard.armada.sh

command_exists() {
    command -v "$@" > /dev/null 2>&1
}

start_using_initd() {
    download_file ${ARMADA_BASE_URL}initd_armada /tmp/initd_armada
    download_file ${ARMADA_BASE_URL}armada-runner /tmp/armada-runner
    $sh_c "mv -f /tmp/initd_armada /etc/init.d/armada"
    $sh_c "mv -f /tmp/armada-runner /usr/local/bin/armada-runner"
    $sh_c "chmod +x /etc/init.d/armada /usr/local/bin/armada-runner"

    if command_exists update-rc.d; then
        $sh_c "update-rc.d armada start 90 2 3 4 5 . stop 10 0 1 6 ."
    elif command_exists chkconfig; then
        $sh_c "chkconfig --level 2345 armada on"
    fi

    $sh_c "service armada restart"
}

start_using_systemd() {
    download_file ${ARMADA_BASE_URL}systemd_armada /tmp/systemd_armada
    download_file ${ARMADA_BASE_URL}armada-runner /tmp/armada-runner
    $sh_c "mv -f /tmp/systemd_armada /etc/systemd/system/armada.service"
    $sh_c "mv -f /tmp/armada-runner /usr/local/bin/armada-runner"
    $sh_c "chmod +x /usr/local/bin/armada-runner"
    $sh_c "systemctl enable armada.service"
    $sh_c "systemctl restart armada.service"
}

case "$(uname -m)" in
    *64)
        ;;
    *)
        echo >&2 'Error: you are not using a 64bit platform.'
        echo >&2 'armada only supports 64bit platforms.'
        exit 1
        ;;
esac

user="$(id -un 2>/dev/null || true)"

sh_c='sh -c'
if [ "$user" != 'root' ]; then
    if command_exists sudo; then
        sh_c='sudo sh -c'
    elif command_exists su; then
        sh_c='su -c'
    else
        echo >&2 'Error: this installer needs the ability to run commands as root.'
        echo >&2 'We are unable to find either "sudo" or "su" available to make this happen.'
        exit 1
    fi
fi


if ! command_exists docker; then
    echo >&2 '"armada" requires docker to be installed first. Try installing it with:'
    echo >&2 '    curl -sL https://get.docker.io/ | sh'
    exit 1
fi

$sh_c "docker info > /dev/null 2>&1"
if [ $? != 0 ]; then
    echo >&2 "Cannot run 'docker' command. Is docker running? Try 'docker -d'."
    exit 1
fi


download_file()
{
    url=$1
    local_path=$2

    $sh_c "rm -f ${local_path}"

    http_status_code='0'
    if command_exists curl; then
        http_status_code=$($sh_c "curl -sL -w \"%{http_code}\" -o ${local_path} ${url}")
    elif command_exists wget; then
        http_status_code=$($sh_c "wget -qS -O ${local_path} ${url} 2>&1 | awk '/^  HTTP/{print \$2}'")
    fi

    if [ ${http_status_code} -ne '200' ]; then
        echo >&2 "Error downloading file: ${url}"
        exit 1
    fi
}

#===================================================================================================

echo "Installing armada..."

if command_exists apt-get; then
    $sh_c "apt-get install -y python python-pip conntrack"
else
    if command_exists yum; then
        $sh_c "yum install -y epel-release"
        $sh_c "yum install -y python python-pip conntrack-tools net-tools"
    fi
fi
if command_exists pip; then
    $sh_c "pip install -U requests 2>/dev/null"

    # Hack for broken pip on Ubuntu after installing requests.
    if command_exists apt-get; then
        $sh_c "apt-get remove -y python-pip"
        $sh_c "apt-get autoremove -y"
        $sh_c "apt-get install -y curl"
        $sh_c "curl -ksLO https://raw.github.com/pypa/pip/master/contrib/get-pip.py"
        $sh_c "python get-pip.py && rm -f get-pip.py && ln -s /usr/local/bin/pip /usr/bin/pip"
    fi
fi

download_file ${ARMADA_BASE_URL}armada /tmp/armada
$sh_c "mv -f /tmp/armada /usr/local/bin/armada"
$sh_c "chmod +x /usr/local/bin/armada"

echo "Downloading armada image..."
$sh_c "docker pull ${ARMADA_REPOSITORY}/armada"
$sh_c "docker tag -f ${ARMADA_REPOSITORY}/armada armada"

if command_exists update-rc.d || command_exists chkconfig; then
    start_using_initd
elif command_exists systemctl; then
    start_using_systemd;
else
    echo "No initd or systemd installed."
    exit 1
fi

hash -r

#===================================================================================================
