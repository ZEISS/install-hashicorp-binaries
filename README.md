# Install HashiCorp binaries

[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/ZEISS/install-hashicorp-binaries?sort=semver&logo=github)][github_releases]

Installation script for HashiCorp binaries hosted on https://releases.hashicorp.com (e.g. packer, terraform, vault).

## Getting Started

Download the installtion script

Linux / MacOS:

```shell
curl -LO https://raw.github.com/ZEISS/install-hashicorp-binaries/master/install-hashicorp.sh
chmod +x install-hashicorp.sh
```

Windows:

```shell
Invoke-WebRequest -UseBasicParsing `
-Uri https://raw.github.com/ZEISS/install-hashicorp-binaries/master/install-hashicorp.ps1 `
-OutFile install-hashicorp.ps1
```

### Prerequisities

MacOS:
* GNU utilities (see [Homebrew GNU bin](https://gist.github.com/skyzyx/3438280b18e4f7c490db8a2a2ca0b9da)) for `sed` and `grep`

Linux / MacOS:

* `bash` for executing script
* `curl` for fetching metadata and archive
* `unzip` for extracting binary from archive
* `shasum` / `sha256sum` for verifying archive checksum
* [`gpg`](https://gnupg.org/) for verifying checksum signature (optional)

Windows:

* `powershell` / `pwsh` for executing script
* [`gpg`](https://gnupg.org/) for verifying checksum signature (optional)

### Usage

Install the required HashiCorp binaries

Linux / MacOS:

```shell
# ./install-hashicorp.sh [options] <name>[:<version>] [...]
./install-hashicorp.sh packer terraform:0.14.0-rc1 vault:latest
```

Windows:

```shell
# .\install-hashicorp.ps1 [options] <name>[:<version>] [...]
.\install-hashicorp.ps1 packer terraform:0.14.0-rc1 vault:latest
```

#### Installation Scopes

The scripts support three installation scopes:

**System Scope (Default)**
* Linux / MacOS: Installs to `/usr/local/bin` (requires `sudo` or appropriate permissions)
* Windows: Installs to `${env:ProgramW6432}\HashiCorp\bin` (requires Administrator privileges)

**User Scope**
* Linux / MacOS: Use `-u` or `--user` flag to install to `${HOME}/.local/bin`
* Windows: Use `-User` flag to install to `${env:LOCALAPPDATA}\Programs\HashiCorp\bin`

**Custom Directory**
* Linux / MacOS: Use `-d` or `--directory PATH` to specify a custom installation directory
* Windows: Use `-Directory PATH` to specify a custom installation directory

#### Examples

Linux / MacOS:

```shell
# Install to system scope (default)
./install-hashicorp.sh terraform packer

# Install to user scope
./install-hashicorp.sh -u terraform packer

# Install to custom directory
./install-hashicorp.sh -d ./example terraform packer

# Install specific versions
./install-hashicorp.sh terraform:1.5.0 packer:1.9.0

# Show help
./install-hashicorp.sh -h
```

Windows:

```shell
# Install to system scope (default, requires Administrator)
.\install-hashicorp.ps1 terraform packer

# Install to user scope
.\install-hashicorp.ps1 -User terraform packer

# Install to custom directory
.\install-hashicorp.ps1 -Directory .\example terraform packer

# Install specific versions
.\install-hashicorp.ps1 terraform:1.5.0 packer:1.9.0

# Show help
.\install-hashicorp.ps1 -Help
```

#### Script Details

* Determines pre-compiled binary archive based on
  * specified name
  * specified or latest stable version
  * detected operating system
  * detected CPU architecture
* Verifies system requirements
* Checks if binary already exists with correct version (skips installation if version matches)
* Verifies and imports PGP key (optional, on first use)
* Fetches archive, checksums and signature files
* Verifies checksum signature (optional)
* Verifies archive checksum
* Extract binary from archive
* Verifies binary code signature (for MacOS and Windows)
* Installs binary to the specified directory:
  * System scope: `/usr/local/bin` (Linux/MacOS) or `${env:ProgramW6432}\HashiCorp\bin` (Windows)
  * User scope: `${HOME}/.local/bin` (Linux/MacOS) or `${env:LOCALAPPDATA}\Programs\HashiCorp\bin` (Windows)
  * Custom directory: User-specified path
* Adds system/user scoped installation directory to system's PATH (for Windows)
* Cleans up archive, checksums and signature files
* Verifies binary installation

## Contributing

If you find issues, please register them at this [GitHub project issue page][github_issue] or consider contributing code by following this [guideline][github_guide].

## Authors

* [Brian Rimek](https://github.com/rembik)

## License

This project is licensed under the MIT License - see the [LICENSE][github_licence] file for details.

[github_releases]: https://github.com/ZEISS/install-hashicorp-binaries/releases
[github_issue]: http://github.com/ZEISS/install-hashicorp-binaries/issues/new/choose
[github_guide]: http://github.com/ZEISS/install-hashicorp-binaries/tree/master/.github/CONTRIBUTING.md
[github_licence]: http://github.com/ZEISS/install-hashicorp-binaries/tree/master/LICENSE
