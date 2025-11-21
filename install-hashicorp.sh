#!/usr/bin/env bash
set -Eeuo pipefail

#################################################
# Display usage information
#################################################
usage() {
    echo "Usage: $0 [options] <name>[:<version>] [...]"
    echo ""
    echo "Options:"
    echo "  -u, --user              Install in user scope (${HOME}/.local/bin)"
    echo "  -d, --directory PATH    Install in custom directory"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 terraform packer             # Install to /usr/local/bin (system scope)"
    echo "  $0 -u terraform                 # Install to ~/.local/bin (user scope)"
    echo "  $0 -d ./bin terraform           # Install to custom directory"
    echo "  $0 terraform:1.5.0              # Install specific version"
}

quiet_gpg() {
    local catch_err=0
    local tmp_dir="${TMPDIR:-/tmp}/install-hashicorp-binaries"
    set +e
    gpg --quiet "$@" 2> "${tmp_dir}/gpg.error.log"
    catch_err=$?
    set -e
    if [ $catch_err -ne 0 ]; then
        cat "${tmp_dir}/gpg.error.log"
        rm "${tmp_dir}/gpg.error.log"
        exit $catch_err
    fi
    rm "${tmp_dir}/gpg.error.log"
}

#################################################
# Install multiple HashiCorp binaries
# ARGUMENTS:
#   Installation directory
#   <name>[:<version>] [...]
# EXAMPLE:
#   install_hashicorp_binaries /usr/local/bin packer terraform:0.14.0-rc1
# RETURN:
#   * 0 if installation succeeded or skipped
#   * non-zero on error
#################################################
install_hashicorp_binaries(){
    local install_dir="$1"
    shift
    local download_url='https://releases.hashicorp.com'
    # https://www.hashicorp.com/security
    # HashiCorp PGP key
    local pgp_keystore='https://keybase.io/hashicorp/pgp_keys.asc'
    local pgp_thumbprint='C874011F0AB405110D02105534365D9472D7468F'
    local pgp_key_imported=1
    # HashiCorp Code Signature (darwin only)
    local codesign_teamid='D38WU7D763'
    local os='undefined' arch='undefined'
    local tmp_dir="${TMPDIR:-/tmp}/install-hashicorp-binaries"

    # Create temporary directory
    mkdir -p "$tmp_dir"
    trap "rm -rf \"${tmp_dir}\"" ERR
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
        echo -e >&2 "ERROR:   Ensure system requirements are installed and added to system's PATH!${cmds_error}"
        exit 1
    fi

    for archive in "$@"; do
        local delimiter=":" verify
        local name="${archive%$delimiter*}" version="${archive#*$delimiter}"
        # Look up the latest stable version
        if [ "$version" = "$archive" -o "$version" = "latest" ]; then
            local regex_grep="\"version\":\"[\.0-9]+\""
            local regex_sed="s/^.*\"([\.0-9]+)\".*$/\1/p"
            version="$(curl -s ${download_url}/${name}/index.json |
                grep -Eo "$regex_grep" | sed -En "$regex_sed" |
                sort -u -t '.' -k 1,1nr -k 2,2nr -k 3,3nr | sed -n '1p' || 
                echo 'undefined')"
        fi
        # Check if the binary already exists with the correct version
        local current_version
        current_version="$("${install_dir}/"${name} version 2>/dev/null | sed -En 's/^.*([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*).*$/\1/p' | sed -n '1p' || true)"
        if [ -n "${current_version}" ] && [ "${current_version}" = "${version}" ]; then
            echo >&2 "Skipping ${name} (${version})"
            continue
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
            exit 1
        fi
        set -e

        if [ ${gpg} -eq 0 ] && [ ${pgp_key_imported} -ne 0 ]; then
            # Verfiy the integrity of the PGP key and import the PGP key
            (cd "${tmp_dir}" && curl -so hashicorp.asc ${pgp_keystore})
            if [ "${pgp_thumbprint}" != "$(quiet_gpg --dry-run --import --import-options import-show "${tmp_dir}/hashicorp.asc" |
                sed -En 's/^[ \t]+([ A-Z0-9]{40,})$/\1/gp')" ]; then
                echo >&2 "ERROR:   Integrity of the PGP key \"${pgp_keystore}\" is compromised"
                exit 1
            fi
            quiet_gpg --import "${tmp_dir}/hashicorp.asc"
            pgp_key_imported=0
            rm "${tmp_dir}/hashicorp.asc"
        fi

        # Download the archive, checksums and signature files
        echo >&2 "Fetching ${download_url}/${name}/${version}/"
        (cd "${tmp_dir}" &&
        curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
        ${download_url}/${name}/${version}/${name}_${version}_${os}_${arch}.zip)
        (cd "${tmp_dir}" &&
        curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
        ${download_url}/${name}/${version}/${name}_${version}_SHA256SUMS)
        if [ ${gpg} -eq 0 ]; then
            (cd "${tmp_dir}" &&
            curl -Osw "  %{filename_effective} (%{time_total} seconds, %{size_download} bytes)\n" \
            ${download_url}/${name}/${version}/${name}_${version}_SHA256SUMS.sig)
        fi

        echo >&2 "Installing ${name} (${version})"
        if [ ${gpg} -eq 0 ]; then
            # Verify the integrity of the checksums file
            quiet_gpg --verify "${tmp_dir}/${name}_${version}_SHA256SUMS.sig" "${tmp_dir}/${name}_${version}_SHA256SUMS"
            # Clean up the signature file
            rm "${tmp_dir}/${name}_${version}_SHA256SUMS.sig"
        fi
        # Verify the integrity of the archive
        if [ $shasum -eq 0 ]; then
            (cd "${tmp_dir}" && grep ${name}_${version}_${os}_${arch}.zip ${name}_${version}_SHA256SUMS | shasum -a 256 -c --status)
        else
            (cd "${tmp_dir}" && grep ${name}_${version}_${os}_${arch}.zip ${name}_${version}_SHA256SUMS | sha256sum -c --status)
        fi
        # Clean up the checksums file
        rm "${tmp_dir}/${name}_${version}_SHA256SUMS"
        # Extract the archive
        unzip -o "${tmp_dir}/${name}_${version}_${os}_${arch}.zip" -d ${tmp_dir} >/dev/null
        chmod +x "${tmp_dir}/${name}"
        # Clean up the archive
        rm "${tmp_dir}/${name}_${version}_${os}_${arch}.zip"
        # Verify the integrity of the executable (darwin only)
        if [ "${os}" = "darwin" ] &&
            [ "${codesign_teamid}" != "$(codesign --verify -d --verbose=2 ${tmp_dir}/${name} 2>&1 |
            sed -En 's/^TeamIdentifier=([A-Z0-9]+)$/\1/gp')" ]; then
            echo >&2 "ERROR:   Integrity of the executable \"${name}\" is compromised"
            exit 1
        fi
        # Ensure the installation directory exists
        mkdir -p "${install_dir}"
        # Add the executable to the specified directory
        mv -f "${tmp_dir}/${name}" "${install_dir}/${name}"
        # Verify the installation
        verify="$("${install_dir}/"${name} version 2>/dev/null | sed -En 's/^.*([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*).*$/\1/p' | sed -n '1p' || true)"
        if [ "${verify}" != "${version}" ]; then
            echo >&2 "ERROR:   Verifying the installed version failed."
            exit 1
        fi
        verify="$(${name} version 2>/dev/null | sed -En 's/^.*([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*).*$/\1/p' | sed -n '1p' || true)"
        if [ "${verify}" != "${version}" ]; then
            echo "INFO: Command \"${name}\" is not using installed version. Check the system's PATH!"
        fi
    done
    rm -rf "$tmp_dir"
}

#################################################
# Main script logic with argument parsing
#################################################
main() {
    local install_dir="/usr/local/bin"  # Default system scope
    local user_scope=0
    local custom_dir=""
    local binaries=()
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                user_scope=1
                shift
                ;;
            -d|--directory)
                if [ -z "${2:-}" ]; then
                    echo >&2 "ERROR:   Option --directory requires a path argument"
                    usage
                    exit 1
                fi
                custom_dir="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo >&2 "ERROR:   Unknown option $1"
                usage
                exit 1
                ;;
            *)
                binaries+=("$1")
                shift
                ;;
        esac
    done
    # Check if any binaries were specified
    if [ ${#binaries[@]} -eq 0 ]; then
        echo >&2 "ERROR:   No binaries specified"
        usage
        exit 1
    fi
    # Determine installation directory based on options
    if [ -n "${custom_dir}" ]; then
        install_dir="${custom_dir}"
    elif [ ${user_scope} -eq 1 ] || [ ! -r "${install_dir}" ] || [ ! -w "${install_dir}" ]; then
        install_dir="${HOME}/.local/bin"
        if ! [[ $PATH =~ ^$install_dir:.*|.*:$install_dir:.*|.*:$install_dir$ ]]; then
            export PATH="${install_dir}:${PATH}"
        fi
    fi
    # Call the installation function
    install_hashicorp_binaries "${install_dir}" "${binaries[@]}"
}

main "$@"
