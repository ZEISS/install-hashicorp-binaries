$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Import-ScriptsWebDownload {
    if (-not ([System.Management.Automation.PSTypeName]'Scripts.Web').Type){
@"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Threading.Tasks;

namespace Scripts
{
    public class Web
    {
        private static readonly object LockObject = new object();

        public static int DownloadFiles(params string[] args)
        {
            // WriteLine("Network interfaces:");
            NetworkInterface[] interfaces = NetworkInterface.GetAllNetworkInterfaces();
            foreach (var networkInterface in interfaces)
            {
                if (networkInterface.OperationalStatus != OperationalStatus.Up)
                {
                    continue;
                }
                // WriteLine("  {1} \"{2}\" ({0}):", networkInterface.NetworkInterfaceType, networkInterface.Name, networkInterface.Description);
                IPInterfaceProperties ipProperties = networkInterface.GetIPProperties();
                IPAddressCollection dnsAddresses = ipProperties.DnsAddresses;
                foreach (IPAddress dnsAddress in dnsAddresses)
                {
                    // WriteLine("    {0}", dnsAddress);
                }
            }

            List<Task> tasks = new List<Task>();
            for (int i = 0; i < args.Length / 2; i++)
            {
                tasks.Add(DownloadFile(args[i * 2], args[i * 2 + 1], 300, TimeSpan.FromSeconds(10)));
            }

            Task.WhenAll(tasks).Wait();
            return 0;
        }

        private static async Task DownloadFile(string sourceUrl, string destinationFile, int attempts, TimeSpan delay)
        {
            string name = Path.GetFileName(destinationFile);
            bool success = false;
            for (int i = 0; i < attempts; i++)
            {
                try
                {
                    if (i > 0)
                    {
                        WriteLine("  {0} attempt #{1} after {2}s", name, i + 1, delay.TotalSeconds);
                        await Task.Delay(delay);
                    }
                    else
                    {
                        WriteLine("  {0} {1}", name, sourceUrl);
                    }

                    success = await DownloadFile(name, sourceUrl, destinationFile);
                    if (success)
                    {
                        break;
                    }

                    WriteErrorLine("  {0} abort", name);
                }
                catch (Exception ex)
                {
                    WriteErrorLine("  {0} error: \"{1}\"", name, ex.Message);
                }
            }

            if (!success)
            {
                throw new Exception("Downloading " + sourceUrl + " failed!");
            }
        }

        private static async Task<bool> DownloadFile(string name, string sourceUrl, string destinationFile)
        {
            Uri source = new Uri(sourceUrl);
            string host = source.DnsSafeHost;
            if (string.IsNullOrWhiteSpace(host))
            {
                throw new InvalidOperationException("Resolving " + sourceUrl + " failed!");
            }
            // WriteLine("  {0} resolved to domain {1}", name, host);
            IPHostEntry hostInfo = await Dns.GetHostEntryAsync(host);
            foreach (var address in hostInfo.AddressList)
            {
                // WriteLine("  {0} resolved to address {1}", name, address);
            }
            using (WebClient client = new WebClient())
            {
                long lastPercent = -1;
                Stopwatch stopwatch = new Stopwatch();
                stopwatch.Start();
                client.DownloadProgressChanged += (sender, args) =>
                {
                    long percent = 100 * args.BytesReceived / args.TotalBytesToReceive;
                    if (percent % 20 == 0 && percent > lastPercent)
                    {
                        double speed = args.TotalBytesToReceive / 1024.0 / 1024.0 / stopwatch.Elapsed.TotalSeconds;
                        if (lastPercent == -1)
                        {
                            speed = 0;
                        }

                        lastPercent = percent;
                        WriteLine("  {0}%\t{1} ({2:0.0} MB/s)", percent, name, speed);
                    }
                };
                bool completed = false;
                client.DownloadFileCompleted += (sender, args) =>
                {
                    completed = true;
                };
                await client.DownloadFileTaskAsync(source, destinationFile);
                return completed;
            }
        }

        private static void WriteLine(string message, params object[] args)
        {
            lock (LockObject)
            {
                Console.WriteLine(message, args);
            }
        }

        private static void WriteErrorLine(string message, params object[] args)
        {
            lock (LockObject)
            {
                Console.Error.WriteLine(message, args);
            }
        }
    }
}
"@ | Set-Content -Path "${env:Temp}\Web.cs"
        [string]$scriptsWeb = Get-Content -Path "${env:Temp}\Web.cs" -Raw
        Add-Type -TypeDefinition "$scriptsWeb" -Language CSharp
        Remove-Item -Force "${env:Temp}\Web.cs"
    }
}

function Update-SessionEnvironment {
    $userName = $env:USERNAME
    $architecture = $env:PROCESSOR_ARCHITECTURE
    $psModulePath = $env:PSModulePath

    #Path gets special treatment b/c it munges the two together
    $paths = 'Machine', 'User' |
        % {[System.Environment]::GetEnvironmentVariable("PATH","$_") -split ';'} |
        Select -Unique
    $env:PATH = $paths -join ';'

    # PSModulePath is almost always updated by process, so we want to preserve it.
    $env:PSModulePath = $psModulePath

    # reset user and architecture
    if ($userName) { $env:USERNAME = $userName; }
    if ($architecture) { $env:PROCESSOR_ARCHITECTURE = $architecture; }
}

#################################################
# Display usage information
#################################################
function Show-Usage {
    Write-Host "Usage: .\install-hashicorp.ps1 [options] <name>[:<version>] [...]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -User               Install in user scope ($env:LOCALAPPDATA\Programs\HashiCorp\bin)"
    Write-Host "  -Directory PATH     Install in custom directory"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\install-hashicorp.ps1 terraform packer             # Install to Program Files (system scope)"
    Write-Host "  .\install-hashicorp.ps1 -User terraform              # Install to user scope"
    Write-Host "  .\install-hashicorp.ps1 -Directory .\bin terraform   # Install to custom directory"
    Write-Host "  .\install-hashicorp.ps1 terraform:1.5.0              # Install specific version"
}

function Invoke-QuietGPG {
    [string]$cacheErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    gpg --quiet @args 2> "${env:Temp}\gpg.error.log"
    if ($LASTEXITCODE -ne 0){
        [string]$gpgErrorLog = Get-Content -Path "${env:Temp}\gpg.error.log" -Raw
        Remove-Item -Force "${env:Temp}\gpg.error.log"
        Write-Error -Message "$gpgErrorLog" -ErrorAction $cacheErrorActionPreference
    }
    $ErrorActionPreference = $cacheErrorActionPreference
    Remove-Item -Force "${env:Temp}\gpg.error.log"
}

#################################################
# Install multiple HashiCorp binaries
# ARGUMENTS:
#   Installation directory
#   <name>[:<version>] [...]
# EXAMPLE:
#   Install-HashiCorpBinaries "C:\Program Files\HashiCorp\bin" packer terraform:0.14.0-rc1
# RETURN:
#   * 0 if installation succeeded or skipped
#   * non-zero on error
#################################################
function Install-HashiCorpBinaries {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$installDir,
        [Parameter( Mandatory=$false,
        ValueFromRemainingArguments=$true )]
        [string[]]$archives
    )

    [string]$downloadUrl = 'https://releases.hashicorp.com'
    # https://www.hashicorp.com/security
    # HashiCorp PGP key
    [string]$pgpKeystore = 'https://keybase.io/hashicorp/pgp_keys.asc'
    [string]$pgpThumbprint = 'C874011F0AB405110D02105534365D9472D7468F'
    [bool]$pgpKeyImported = $false
    # HashiCorp Code Signature
    [string[]]$codeSignThumbprint = @('35AB9FC834D217E9E7B1778FB1B97AF7C73792F2', '7868E4F55FD7B047CD8BF93FEA8C38509CFB5939', '6F1DCD6FE62C173708E26E25D19656E413277816')
    [string]$os = 'windows'
    [string]$arch = 'undefined'

    # Look up the architecture
    if ((Get-WmiObject Win32_OperatingSystem).OSArchitecture -match '64'){
        $arch = 'amd64'
        if ((Get-WmiObject Win32_ComputerSystem).SystemType -match 'ARM'){
            # Because of current lack of x64 emulation on ARM64 support
            $arch = '386'
        }
    }
    elseif ((Get-WmiObject Win32_OperatingSystem).OSArchitecture -match '32'){
        $arch = '386'
    }
    # Verify the system requirements
    [string[]]$cmds = 'gpg'
    [string]$cmds_error = ''
    [string]$gpg = 0
    foreach ($cmd in $cmds){
        try {
            Get-Command $cmd | Out-Null
        }
        catch {
            switch ($cmd){
                'gpg' {$gpg = 1}
                Default {$cmds_error += "`r`n         Command `"${cmd}`" not found"}
            }
        }
    }
    if (-not ([string]::IsNullOrEmpty($cmds_error))){
        Write-Error "ERROR:   Ensure system requirements are installed and added to system's PATH!${cmd_errors}"
    }

    [string[]]$verifiedArchives = @()
    [string]$downloadFiles = ''
    foreach ($archive in $archives){
        [string]$name, [string]$version = "$archive" -split ":"
        # Look up the latest stable version
        if ([string]::IsNullOrEmpty($version) -or "$version" -eq "latest" ){
            [string]$regex = "^([\.0-9]+)$"
            try {
                $version = (ConvertFrom-Json (Invoke-WebRequest -UseBasicParsing -Method Get `
                    -Uri "${downloadUrl}/${name}/index.json")).versions | `
                    % {$_.PSObject.Properties} | % {"$($_.Name)"} | `
                    Select-String -Pattern $regex -AllMatches | `
                    % {$_.Matches} | % {$_.Groups[1]} | % {$_.Value} | `
                    % {[System.Version]$_} | Sort-Object Major,Minor,Build -Descending | `
                    Select-Object -first 1 | % {"$($_.Major).$($_.Minor).$($_.Build)"}
            }
            catch {
                $version = "undefined"
            }
        }
        # Check if the binary already exists with the correct version
        [string]$currentVersion = $(try { Invoke-Expression "${installDir}\${name} version" 2>$null } catch { "" })
        $currentVersion = $currentVersion | Select-String -Pattern "([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*)" -AllMatches | `
            % {$_.Matches.Groups[1]} | % {$_.Value} | Select-Object -First 1
        if (-not [string]::IsNullOrEmpty($currentVersion) -and $currentVersion -eq $version){
            Write-Host "Skipping ${name} (${version})"
            continue
        }
        # Look up the archive
        try {
            Invoke-WebRequest -UseBasicParsing -Method Head `
            -Uri "${downloadUrl}/${name}/${version}/${name}_${version}_${os}_${arch}.zip" | `
            Out-Null
        }
        catch {
            Write-Host "Installing ${name} (${version})"
            Write-Host "ERROR:   No appropriate archive for your product, version, operating"
            Write-Host "         system or architecture on ${downloadUrl}"
            Write-Host "         product:          ${name}"
            Write-Host "         version:          ${version}"
            Write-Host "         operating system: ${os}"
            Write-Host "         architecture:     ${arch}"
            exit 1
        }
        $verifiedArchives += "${name}:${version}"
        $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_${os}_${arch}.zip', '${env:Temp}\${name}_${version}_${os}_${arch}.zip', "
        $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_SHA256SUMS', '${env:Temp}\${name}_${version}_SHA256SUMS', "
        if ($gpg -eq 0){
            $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_SHA256SUMS.sig', '${env:Temp}\${name}_${version}_SHA256SUMS.sig', "
        }
    }

    if ($verifiedArchives){
        # Download the archive, checksums and signature files
        Write-Host "Fetching ${downloadUrl}/"
        $downloadFiles = $downloadFiles.SubString(0, [math]::Max(0, $downloadFiles.length - 2))
        if (-not ([string]::IsNullOrEmpty($downloadFiles))){
            Import-ScriptsWebDownload
            [string]$download = "[Scripts.Web]::DownloadFiles($downloadFiles)"
            Invoke-Expression $download | Out-Null
        }
    }

    foreach ($archive in $verifiedArchives){
        [string]$name, [string]$version = "$archive" -split ":"
        if ($gpg -eq 0 -and -not $pgpKeyImported){
            # Verfiy the integrity of the PGP key and import the PGP key
            Invoke-WebRequest -UseBasicParsing -Method Get `
            -Uri "${pgpKeystore}" -OutFile "${env:Temp}\hashicorp.asc" | `
            Out-Null
            if ("${pgpThumbprint}" -ne (Invoke-QuietGPG --dry-run --import --import-options import-show "${env:Temp}\hashicorp.asc" | `
                Select-String -Pattern '^[ \t]+([ A-Z0-9]{40,})$' -AllMatches | `
                % {$_.Matches.Groups[1]} | % {$_.Value})){
                Write-Error "ERROR:   Integrity of the PGP key `"${pgpKeystore}`" is compromised"
            }
            Invoke-QuietGPG --import "${env:Temp}\hashicorp.asc"
            $pgpKeyImported = $true
            Remove-Item -Force "${env:Temp}\hashicorp.asc"
        }
        Write-Host "Installing ${name} (${version})"
        if ($gpg -eq 0){
            # Verify the integrity of the checksums file
            Invoke-QuietGPG --verify "${env:Temp}\${name}_${version}_SHA256SUMS.sig" "${env:Temp}\${name}_${version}_SHA256SUMS"
            # Clean up the signature file
            Remove-Item -Force "${env:Temp}\${name}_${version}_SHA256SUMS.sig"
        }
        # Verify the integrity of the archive
        [string]$checksum = (Get-FileHash "${env:Temp}\${name}_${version}_${os}_${arch}.zip" -Algorithm SHA256).Hash
        [string]$regex = "^([A-Fa-f0-9]{64}).*${name}_${version}_${os}_${arch}\.zip$"
        if ($checksum -ne (Get-Content -Path "${env:Temp}\${name}_${version}_SHA256SUMS" | `
            Select-String -Pattern $regex -AllMatches | % {$_.Matches.Groups[1]} | % {$_.Value})){
            Write-Error "ERROR:   Integrity of the archive `"${name}_${version}_${os}_${arch}.zip`" is compromised"
        }
        # Clean up the checksums file
        Remove-Item -Force "${env:Temp}\${name}_${version}_SHA256SUMS"
        # Extract the archive
        Expand-Archive -Force -Path "${env:Temp}\${name}_${version}_${os}_${arch}.zip" -DestinationPath "${env:Temp}"
        # Clean up the archive
        Remove-Item -Force "${env:Temp}\${name}_${version}_${os}_${arch}.zip"
        # Verify the integrity of the executable
        if (((Get-AuthenticodeSignature -FilePath "${env:Temp}\${name}.exe").SignerCertificate).thumbprint -notin $codeSignThumbprint){
            Write-Error "ERROR:   Integrity of the executable `"${name}.exe`" is compromised"
        }
        # Ensure the installation directory exists
        if (-not (Test-Path "${installDir}")){
            New-Item -ItemType Directory -Force -Path "${installDir}" | Out-Null
        }
        # Add the executable to the specified directory
        Move-Item -Force -Path "${env:Temp}\${name}.exe" "${installDir}\${name}.exe"
        # Verify the CLI installation
        $verify = $(try { Invoke-Expression "${installDir}\${name} version" 2>$null } catch { "" })
        $verify = $verify | Select-String -Pattern "([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*)" -AllMatches | `
            % {$_.Matches.Groups[1]} | % {$_.Value} | Select-Object -First 1
        if ("${verify}" -ne "${version}"){
            Write-Error "ERROR:   Verifying the installed version failed."
        }
        # Check if the command is available in PATH
        Update-SessionEnvironment
        $verify = $(try { Invoke-Expression "${name} version" 2>$null } catch { "" })
        $verify = $verify | Select-String -Pattern "([0-9]+\.[0-9]+\.[0-9]+[0-9a-zA-Z\.+-]*)" -AllMatches | `
            % {$_.Matches.Groups[1]} | % {$_.Value} | Select-Object -First 1
        if ("${verify}" -ne "${version}"){
            Write-Host "WARNING: Command `"${name}`" is not using installed version. Check the system's PATH!"
        }
    }
}

#################################################
# Main script logic with argument parsing
#################################################
function Main {
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [Parameter(Mandatory=$false)]
        [switch]$User,
        [Parameter(Mandatory=$false)]
        [string]$Directory,
        [Parameter(Mandatory=$false)]
        [switch]$Help,
        [Parameter( Mandatory=$false,
        ValueFromRemainingArguments=$true )]
        [string[]]$Binaries
    )
    # Show help if requested
    if ($Help){
        Show-Usage
        exit 0
    }
    # Check if any binaries were specified
    if ($Binaries.Count -eq 0){
        Write-Host "ERROR:   No binaries specified"
        Show-Usage
        exit 1
    }
    # Determine installation directory based on options
    [string]$installDir = "${env:ProgramW6432}\HashiCorp\bin"  # Default system scope
    if ($PSBoundParameters.ContainsKey('Directory') -and -not [string]::IsNullOrWhiteSpace($Directory) -and -not [string]::IsNullOrEmpty($Directory)){
        # Custom directory scope
        $installDir = [System.IO.Path]::GetFullPath($Directory)
    }
    elseif ($User -or -not (Test-Path $installDir -PathType Container) -or `
        -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        # User scope
        $installDir = "${env:LOCALAPPDATA}\Programs\HashiCorp\bin"
        Update-SessionEnvironment
        if (-not ("$env:PATH" -match [Regex]::Escape("${installDir}"))){
            SETX PATH ('{0};{1};' -f "${env:PATH}", "${installDir}") | Out-Null
        }
    }
    else {
        # System scope
        Update-SessionEnvironment
        if (-not ("$env:PATH" -match [Regex]::Escape("${installDir}"))){
            SETX /M PATH ('{0};{1};' -f "${env:PATH}", "${installDir}") | Out-Null
        }
    }
    # Call the installation function
    Install-HashiCorpBinaries -InstallDir $installDir @Binaries
}

Main @args
