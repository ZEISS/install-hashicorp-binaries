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
#   <name>[:<version>] [...]
# EXAMPLE:
#   Install-HashiCorpBinaries packer terraform:0.14.0-rc1
# RETURN:
#   * 0 if installation succeeded or skipped
#   * non-zero on error
#################################################
function Install-HashiCorpBinaries {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$false,
        ValueFromRemainingArguments=$true )]
        [string[]]$archives
    )

    [string]$downloadUrl = 'https://releases.hashicorp.com'
    # https://www.hashicorp.com/security
    # HashiCorp PGP key
    [string]$pgpKeystore = 'https://keybase.io/hashicorp/pgp_keys.asc'
    [string]$pgpThumbprint = '91A6E7F85D05C65630BEF18951852D87348FFC4C'
    # HashiCorp Code Signature
    [string]$codeSignThumbprint = '35AB9FC834D217E9E7B1778FB1B97AF7C73792F2'
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
        WriteError "FATAL:   Ensure system requirements are installed and added to system's PATH!${cmd_errors}"
    }
    if ($gpg -eq 0){
        # Verfiy the integrity of the PGP key and import the PGP key
        Invoke-WebRequest -UseBasicParsing -Method Get `
        -Uri "${pgpKeystore}" -OutFile "${env:Temp}\hashicorp.asc" | `
        Out-Null
        if ("${pgpThumbprint}" -ne (Invoke-QuietGPG --dry-run --import --import-options import-show "${env:Temp}\hashicorp.asc" | `
            Select-String -Pattern '^[ \t]+([ A-Z0-9]{40,})$' -AllMatches | `
            % {$_.Matches.Groups[1]} | % {$_.Value})){
            Write-Error "FATAL:   Integrity of the PGP key `"${pgpKeystore}`" is compromised"
        }
        Invoke-QuietGPG --import "${env:Temp}\hashicorp.asc"
        Remove-Item -Force "${env:Temp}\hashicorp.asc"
    }

    [string[]]$verifiedArchives = @()
    [string]$downloadFiles = ''
    foreach ($archive in $archives){
        [string]$name, [string]$version = "$archive" -split ":"
        # Look up the latest stable version
        if ([string]::IsNullOrEmpty($version) -or "$version" -eq "latest" ){
            [string]$regex = "`"([\.0-9]+)`":{`"name`":`"${name}`",`"version`""
            try {
                $version = (Invoke-WebRequest -UseBasicParsing -Method Get `
                    -Uri "${downloadUrl}/${name}/index.json").Content | `
                    Select-String -Pattern $regex -AllMatches | `
                    % {$_.Matches} | % {$_.Groups[1]} | % {$_.Value} | `
                    % {[System.Version]$_} | Sort-Object Major,Minor,Build -Descending | `
                    Select-Object -first 1 | % {"$($_.Major).$($_.Minor).$($_.Build)"}
            }
            catch {
                $version = "undefined"
            }
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
            continue
        }
        $verifiedArchives += "${name}:${version}"
        $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_${os}_${arch}.zip', '${env:Temp}\${name}_${version}_${os}_${arch}.zip', "
        $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_SHA256SUMS', '${env:Temp}\${name}_${version}_SHA256SUMS', "
        if ($gpg -eq 0){
            $downloadFiles += "'${downloadUrl}/${name}/${version}/${name}_${version}_SHA256SUMS.sig', '${env:Temp}\${name}_${version}_SHA256SUMS.sig', "
        }
    }

    # Download the archive, checksums and signature files
    Write-Host "Fetching ${downloadUrl}/"
    $downloadFiles = $downloadFiles.SubString(0, [math]::Max(0, $downloadFiles.length - 2))
    if (-not ([string]::IsNullOrEmpty($downloadFiles))){
        Import-ScriptsWebDownload
        [string]$download = "[Scripts.Web]::DownloadFiles($downloadFiles)"
        Invoke-Expression $download | Out-Null
    }

    foreach ($archive in $verifiedArchives){
        [string]$name, [string]$version = "$archive" -split ":"
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
            Write-Error "FATAL:   Integrity of the archive `"${name}_${version}_${os}_${arch}.zip`" is compromised"
        }
        # Clean up the checksums file
        Remove-Item -Force "${env:Temp}\${name}_${version}_SHA256SUMS"
        # Extract the archive
        Expand-Archive -Force -Path "${env:Temp}\${name}_${version}_${os}_${arch}.zip" -DestinationPath "${env:Temp}"
        # Clean up the archive
        Remove-Item -Force "${env:Temp}\${name}_${version}_${os}_${arch}.zip"
        # Verify the integrity of the executable
        if ($codeSignThumbprint -ne ((Get-AuthenticodeSignature -FilePath "${env:Temp}\${name}.exe").SignerCertificate).thumbprint){
            Write-Error "FATAL:   Integrity of the executable `"${name}.exe`" is compromised"
        }
        # Add the executable to system's PATH
        if (-not (Test-Path "${env:ProgramFiles}\HashiCorp\bin")){
            New-Item -ItemType Directory -Force -Path "${env:ProgramFiles}\HashiCorp\bin" | Out-Null
        }
        Move-Item -Force -Path "${env:Temp}\${name}.exe" "${env:ProgramFiles}\HashiCorp\bin\${name}.exe"
        $pathPS = New-PSSession -ComputerName localhost
        [string]$path = Invoke-Command -Session $pathPS -ScriptBlock { Write-Output "${env:PATH}" }
        Remove-PSSession -Session $pathPS
        if (-not ("$path" -match [Regex]::Escape("${env:ProgramFiles}\HashiCorp\bin"))){
            SETX /M PATH ('{0};{1};' -f "${env:PATH}", "${env:ProgramFiles}\HashiCorp\bin") | Out-Null
        }
        # Verify the CLI installation
        [string]$verify = "${name} version"
        $verifyPS = New-PSSession -ComputerName localhost
        $verify = Invoke-Command -Session $verifyPS -ScriptBlock { Invoke-Expression $args[0] } -ArgumentList "$verify"
        Remove-PSSession -Session $verifyPS
        $verify = $verify | Select-String -Pattern '^.*?([0-9]+\.[0-9]+\.[0-9]+).*$' -AllMatches | `
            % {$_.Matches.Groups[1]} | % {$_.Value}
        if ("${verify}" -ne "${version}"){
            Write-Host "WARNING: Another executable file is prioritized when the command `"${name}`" is executed"
            Write-Host "         Check your system's PATH!"
        }
    }
}

Install-HashiCorpBinaries @args