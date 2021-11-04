#!/usr/bin/env bash
set -Eeuo pipefail

quiet_gpg(){
    local catch_err=0
    set +e
    gpg --quiet "$@" 2> ${TMPDIR:-/tmp}/gpg.error.log
    catch_err=$?
    set -e
    if [ $catch_err -ne 0 ]; then
        cat ${TMPDIR:-/tmp}/gpg.error.log
        rm ${TMPDIR:-/tmp}/gpg.error.log
        exit $catch_err
    fi
    rm ${TMPDIR:-/tmp}/gpg.error.log
}

#################################################
# Install multiple HashiCorp binaries
# ARGUMENTS:
#   <name>[:<version>] [...]
# EXAMPLE:
#   install_hashicorp_binaries packer terraform:0.14.0-rc1
# RETURN:
#   * 0 if installation succeeded or skipped
#   * non-zero on error
#################################################
install_hashicorp_binaries(){
    local download_url='https://releases.hashicorp.com'
    # https://www.hashicorp.com/security
    # HashiCorp PGP key
    local pgp_keystore='https://keybase.io/hashicorp/pgp_keys.asc'
    local pgp_thumbprint='C874011F0AB405110D02105534365D9472D7468F'
    # HashiCorp Code Signature (darwin only)
    local codesign_teamid='D38WU7D763'
    local os='undefined' arch='undefined'

    # Look up the operating system
    case "$(uname | tr '[:upper:]' '[:lower:]')" in
        linux*) os='linux';;
        freebsd*) os='freebsd';;
        netbsd*) os='netbsd';;
        openbsd*) os='openbsd';;
        darwin*) os='darwin';;
        sunos*) os='solaris';;
    esac
    # Look up the architecture
    if [ "$(getconf LONG_BIT)" = "64" ]; then
        if [ "$(uname -m)" = "x86_64" ]; then
            arch="amd64"
        elif [[ "$(uname -m)" =~ ^.*(arm|aarch).*$ ]]; then
            arch="arm64"
        fi
    elif  [ "$(getconf LONG_BIT)" = "32" ]; then
        if [ "$(uname -m)" = "x86_64" ]; then
            arch="386"
        elif [[ "$(uname -m)" =~ ^.*arm.*$ ]]; then
            arch="arm"
        fi
    fi
    # Verify the system requirements
    local cmds=(shasum sha256sum curl unzip gpg) cmds_error="" gpg=0 shasum=0
    set +e
    for cmd in "${cmds[@]}"; do
        command -v ${cmd} >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            case "${cmd}" in
                gpg) gpg=1;;
                shasum) shasum=1;;
                sha256sum)
                    if [ $shasum -ne 0 ]; then
                        cmds_error+="\n         Command \"shasum\" or \"${cmd}\" not found"
                    fi;;
                *) cmds_error+="\n         Command \"${cmd}\" not found";;
            esac
        fi
    done
    set -e
    if [ -n "${cmds_error}" ]; then
        echo -e >&2 "FATAL:   Ensure system requirements are installed and added to system's PATH!${cmds_error}"
        exit 1
    fi
    if [ ${gpg} -eq 0 ]; then
        # Verfiy the integrity of the PGP key and import the PGP key
        (cd ${TMPDIR:-/tmp} && curl -so hashicorp.asc ${pgp_keystore})
        if [ "${pgp_thumbprint}" != "$(quiet_gpg --dry-run --import --import-options import-show ${TMPDIR:-/tmp}/hashicorp.asc |
            sed -En 's/^[ \t]+([ A-Z0-9]{40,})$/\1/gp')" ]; then
            echo >&2 "FATAL:   Integrity of the PGP key \"${pgp_keystore}\" is compromised"
            exit 1
        fi
        quiet_gpg --import ${TMPDIR:-/tmp}/hashicorp.asc
        rm ${TMPDIR:-/tmp}/hashicorp.asc
    fi

    for archive in "$@"; do
        local delimiter=":" verify
        local name="${archive%$delimiter*}" version="${archive#*$delimiter}"
        # Look up the latest stable version
        if [ "$version" = "$archive" -o "$version" = "latest" ]; then
            local regex_grep="\"[\.0-9]+\":\{\"name\":\"${name}\",\"version\""
            local regex_sed="s/^\"([\.0-9]+)\".*$/\1/p"
            version="$(curl -s ${download_url}/${name}/index.json | 
                grep -Eo "$regex_grep" | 
                sed -En "$regex_sed" | 
                sort -t '.' -k 1,1nr -k 2,2nr -k 3,3nr | 
                sed -n '1p' || 
                echo 'undefined')"
        fi
        # Look up the archive
        set +e
        curl -fsIo /dev/null ${download_url}/${name}/${version}/${name}_${version}_${os}_${arch}.zip
        if [ $? -ne 0 ]; then
            set -e
            echo >&2 "Installing ${name} (${version})"
            echo >&2 "ERROR:   No appropriate archive for your product, version, operating"
            echo >&2 "         system or architecture on ${download_url}"
            echo >&2 "         product:          ${name}"
            echo >&2 "         version:          ${version}"
            echo >&2 "         operating system: ${os}"
            echo >&2 "         architecture:     ${arch}"
            continue
        fi
        set -e

        # Download the archive, checksums and signature files
        echo >&2 "Fetching ${download_url}/${name}/${version}/"
        (cd ${TMPDIR:-/tmp} &&
        curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
        ${download_url}/${name}/${version}/${name}_${version}_${os}_${arch}.zip)
        (cd ${TMPDIR:-/tmp} &&
        curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
        ${download_url}/${name}/${version}/${name}_${version}_SHA256SUMS)
        if [ ${gpg} -eq 0 ]; then
            (cd ${TMPDIR:-/tmp} &&
            curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
            ${download_url}/${name}/${version}/${name}_${version}_SHA256SUMS.sig)
        fi

        echo >&2 "Installing ${name} (${version})"
        if [ ${gpg} -eq 0 ]; then
            # Verify the integrity of the checksums file
            quiet_gpg --verify ${TMPDIR:-/tmp}/${name}_${version}_SHA256SUMS.sig ${TMPDIR:-/tmp}/${name}_${version}_SHA256SUMS
            # Clean up the signature file
            rm ${TMPDIR:-/tmp}/${name}_${version}_SHA256SUMS.sig
        fi
        # Verify the integrity of the archive
        if [ $shasum -eq 0 ]; then
            (cd ${TMPDIR:-/tmp} && grep ${name}_${version}_${os}_${arch}.zip ${name}_${version}_SHA256SUMS | shasum -a 256 -c --status)
        else
            (cd ${TMPDIR:-/tmp} && grep ${name}_${version}_${os}_${arch}.zip ${name}_${version}_SHA256SUMS | sha256sum -c --status)
        fi
        # Clean up the checksums file
        rm ${TMPDIR:-/tmp}/${name}_${version}_SHA256SUMS
        # Extract the archive
        unzip ${TMPDIR:-/tmp}/${name}_${version}_${os}_${arch}.zip -d ${TMPDIR:-/tmp} >/dev/null
        chmod +x ${TMPDIR:-/tmp}/${name}
        # Clean up the archive
        rm ${TMPDIR:-/tmp}/${name}_${version}_${os}_${arch}.zip
        # Verify the integrity of the executable (darwin only)
        if [ "${os}" = "darwin" ] &&
            [ "${codesign_teamid}" != "$(codesign --verify -d --verbose=2 ${TMPDIR:-/tmp}/${name} 2>&1 |
            sed -En 's/^TeamIdentifier=([A-Z0-9]+)$/\1/gp')" ]; then
            echo >&2 "FATAL:   Integrity of the executable \"${name}\" is compromised"
            exit 1
        fi
        # Add the executable to system's PATH
        mv -f ${TMPDIR:-/tmp}/${name} /usr/local/bin/${name}
        # Verify the installation
        verify="$(${name} version)"
        verify="$(echo "$verify" | sed -En 's/^.*?([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' | sed -n '1p')"
        if [ "${verify}" != "${version}" ]; then
            echo >&2 "WARNING: Another executable file is prioritized when the command \"${name}\" is executed"
            echo >&2 "         Check your system's PATH!"
        fi
    done
}

install_hashicorp_binaries "$@"
