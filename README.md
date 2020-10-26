# Install HashiCorp binaries

[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/rembik/install-hashicorp-binaries?sort=semver&logo=github)][github_releases]

Installation script for HashiCorp binaries hosted on https://releases.hashicorp.com (e.g. packer, terraform, vault).

## Getting Started

Download the installtion script

Linux / MacOS:

```shell
curl -LO https://raw.github.com/rembik/install-hashicorp-binaries/master/install-hashicorp.sh
chmod +x install-hashicorp.sh
```

Windows:

```shell
Invoke-WebRequest -UseBasicParsing -Uri https://raw.github.com/rembik/install-hashicorp-binaries/master/install-hashicorp.ps1 -OutFile install-hashicorp.ps1
```

### Prerequisities

Linux / MacOS:

* `bash` for executing script
* `curl` for fetching metadata and archives
* `unzip` for extracting binary archives
* `gpg` for verifying binary archive signatures (optional for MacOS)

Windows:

* `powershell`/ `pwsh` for executing script

### Usage

Install the required HashiCorp binaries

Linux / MacOS:

```shell
# ./install-hashicorp.sh <name>[:<version>] [...]
./install-hashicorp.sh packer terraform:0.13.5 vault:latest
```

Windows:

```shell
# .\install-hashicorp.ps1 <name>[:<version>] [...]
.\install-hashicorp.ps1 packer terraform:0.13.5 vault:latest
```

#### Script Details

* Verifies and imports PGP key (for Linux and optional MacOS)
* Determines binary archive based on
  * specified name
  * specified or latest stable version
  * detected operating system
  * detected CPU architecture
* Fetchs binary archive
* Verifies binary archive (for Linux and optional MacOS)
  * Fetchs signature files
  * Verifies binary archive signature
  * Cleans up signature files
* Extract binary archive
* Verifies binary code signature (for MacOS and Windows)
* Adds binary to system's PATH
  * Moves binary to `/usr/local/bin` (for Linux and MacOS)
  * Moves binary to `${env:ProgramFiles}\HashiCorp\bin` (for Windows)
  * Adds `${env:ProgramFiles}\HashiCorp\bin` to system's PATH (for Windows)
* Cleans up binary archive
* Verifies binary installation

## Contributing

If you find issues, please register them at this [GitHub project issue page][github_issue] or consider contributing code by following this [guideline][github_guide].

## Authors

* [Brian Rimek](https://github.com/rembik)

## License

This project is licensed under the MIT License - see the [LICENSE][github_licence] file for details.

[github_releases]: https://github.com/rembik/install-hashicorp-binaries/releases
[github_issue]: http://github.com/rembik/install-hashicorp-binaries/issues/new/choose
[github_guide]: http://github.com/rembik/install-hashicorp-binaries/tree/master/.github/CONTRIBUTING.md
[github_licence]: http://github.com/rembik/install-hashicorp-binaries/tree/master/LICENSE