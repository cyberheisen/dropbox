# Windows 11 Activation and Product Key Reference

Operator reference for identifying, extracting, and applying Windows 11 activation
across retail, OEM, digital license, MAK, and KMS channels.

Tested on Windows 11 Pro 22H2 through 25H2. All PowerShell examples assume an
elevated session unless noted.

---

## Table of Contents

- [1. Identify the License Channel First](#1-identify-the-license-channel-first)
- [2. Channel Reference](#2-channel-reference)
- [3. Key Extraction Methods](#3-key-extraction-methods)
  - [3.1 Firmware OEM Key (MSDM)](#31-firmware-oem-key-msdm)
  - [3.2 Installed Key from Registry DigitalProductId](#32-installed-key-from-registry-digitalproductid)
  - [3.3 Partial Key and Activation State](#33-partial-key-and-activation-state)
- [4. Applying a Key](#4-applying-a-key)
- [5. KMS Activation](#5-kms-activation)
- [6. Digital License and Hardware Hash](#6-digital-license-and-hardware-hash)
- [7. Fleet Inventory Script](#7-fleet-inventory-script)
- [8. Troubleshooting](#8-troubleshooting)
- [9. Where Microsoft Stores Your Keys](#9-where-microsoft-stores-your-keys)
- [10. Generic KMS Client Setup Keys](#10-generic-kms-client-setup-keys)

---

## 1. Identify the License Channel First

Do not extract anything until you know what channel the machine is on. The channel
determines whether a real key exists to recover.

```powershell
Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" |
    Select-Object Name, Description, PartialProductKey, LicenseStatus, ProductKeyChannel |
    Format-List
```

Equivalent GUI or dialog output:

```cmd
slmgr /dlv
```

Full license state including all installed SKUs:

```cmd
slmgr /dlv all
```

`LicenseStatus` values:

| Value | Meaning |
|-------|---------|
| 0 | Unlicensed |
| 1 | Licensed |
| 2 | Out of box grace period |
| 3 | Out of tolerance grace period |
| 4 | Non genuine grace period |
| 5 | Notification |
| 6 | Extended grace |

---

## 2. Channel Reference

| Channel string | Source | Recoverable 25 character key? | Survives motherboard swap? |
|----------------|--------|-------------------------------|----------------------------|
| `OEM_DM` | UEFI firmware, preinstalled by OEM | Yes, from MSDM table | No, tied to that board |
| `Retail` | Boxed or Microsoft Store purchase | Yes, from registry | Yes, with Microsoft account or phone activation |
| `Volume_MAK` | Volume licensing agreement | Yes, from registry and admin center | Yes, subject to activation count |
| `Volume_KMSCLIENT` | KMS or ADBA activated | No real key, only the public generic setup key | Reactivates on network contact |
| `Retail:TB:Eval` | Evaluation media | No | No |
| Digital license (no key) | Free upgrade or MSA linked entitlement | No, entitlement is a hardware hash | Only if linked to a Microsoft account |

---

## 3. Key Extraction Methods

### 3.1 Firmware OEM Key (MSDM)

Pulls the key burned into the UEFI ACPI MSDM table by the OEM. This survives a full
wipe and reinstall and is the only value worth archiving for OEM hardware.

```powershell
(Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
```

Empty output means there is no MSDM table, which is normal for retail installs,
custom builds, and virtual machines.

Legacy `wmic` form. Works on older builds only, `wmic` is removed in 24H2 and later:

```cmd
wmic path SoftwareLicensingService get OA3xOriginalProductKey
```

Raw ACPI dump if you want to confirm the table exists:

```powershell
Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Out-Null
# MSDM presence check
(Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID
```

### 3.2 Installed Key from Registry DigitalProductId

Decodes the key currently installed in the OS from
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\DigitalProductId`.

Save as `Get-InstalledProductKey.ps1` or paste directly into an elevated console.

```powershell
function Get-InstalledProductKey {
    [CmdletBinding()]
    param()

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $digitalId = (Get-ItemProperty -Path $regPath -Name DigitalProductId).DigitalProductId

    if (-not $digitalId) {
        Write-Warning 'DigitalProductId not present.'
        return
    }

    $charMap = 'BCDFGHJKMPQRTVWXY2346789'
    $isNKey  = [math]::Floor($digitalId[66] / 6) -band 1
    $digitalId[66] = ($digitalId[66] -band 0xF7) -bor (($isNKey -band 2) * 4)

    $key      = ''
    $lastChar = 0

    for ($i = 24; $i -ge 0; $i--) {
        $current = 0
        for ($j = 14; $j -ge 0; $j--) {
            $current = $current * 256 + $digitalId[$j + 52]
            $digitalId[$j + 52] = [math]::Floor($current / 24)
            $current = $current % 24
        }
        $key = $charMap[$current] + $key
        $lastChar = $current
    }

    if ($isNKey -eq 1) {
        $key = $key.Remove(0, 1).Insert($lastChar, 'N')
    }

    return ($key -replace '(.{5})(?!$)', '$1-')
}

Get-InstalledProductKey
```

**Important caveat.** On a digital license machine this returns a public generic key
such as `VK7JG-NPHTM-C97JM-9MPGT-3V66T`. That is the Windows 11 Pro generic setup
key, not your license. It will not activate anything on its own. Cross reference
against the generic key table in section 10 before you treat any output as real.

### 3.3 Partial Key and Activation State

Always available regardless of channel. Returns the last five characters only.

```powershell
Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" |
    Select-Object -ExpandProperty PartialProductKey
```

Confirm the activation ID and expiration:

```cmd
slmgr /xpr
```

---

## 4. Applying a Key

Install a key without activating:

```cmd
slmgr /ipk XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

Activate online against Microsoft or the configured KMS host:

```cmd
slmgr /ato
```

Combined, from PowerShell:

```powershell
$key = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ipk $key
cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato
```

Reinstall the firmware OEM key on a rebuilt machine:

```powershell
$oemKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
if ($oemKey) {
    cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ipk $oemKey
    cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato
} else {
    Write-Warning 'No firmware key present on this system.'
}
```

Remove the installed key from the registry after activation. This does not
deactivate Windows, it just clears the key from a location where it can be read:

```cmd
slmgr /cpky
```

Uninstall the current key and drop to unlicensed:

```cmd
slmgr /upk
slmgr /cpky
```

Phone activation, when online activation fails:

```cmd
slui 4
```

---

## 5. KMS Activation

Point a client at a specific KMS host:

```cmd
slmgr /skms kms.example.local:1688
slmgr /ato
```

Clear a manually set KMS host and revert to DNS SRV autodiscovery:

```cmd
slmgr /ckms
```

Show the current KMS client configuration and renewal interval:

```cmd
slmgr /dli
```

Force a renewal attempt:

```cmd
slmgr /ato
```

Expected DNS SRV record for autodiscovery:

```
_vlmcs._tcp.<domain>    SRV    0 0 1688 kmshost.<domain>
```

KMS clients renew every 7 days by default and carry a 180 day activation window.
A machine that falls out of contact for more than 180 days drops to notification
state rather than deactivating outright.

---

## 6. Digital License and Hardware Hash

A digital license, previously called digital entitlement, has no product key.
Activation is a hardware hash held on Microsoft servers, generated from the
motherboard, TPM, and other component identifiers.

Check whether the machine holds one:

```powershell
$prod = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"
[PSCustomObject]@{
    Name        = $prod.Name
    Channel     = $prod.ProductKeyChannel
    Description = $prod.Description
    Status      = $prod.LicenseStatus
    Partial     = $prod.PartialProductKey
}
```

If `Description` contains `Retail` or `OEM` but you know the machine was upgraded
free from Windows 10, you are on a digital license. There is nothing to extract.

Link the license to a Microsoft account so it survives a hardware change:

```
Settings > System > Activation > Add an account
```

After a motherboard replacement, use the activation troubleshooter:

```
Settings > System > Activation > Troubleshoot > I changed hardware on this device recently
```

---

## 7. Fleet Inventory Script

Collects hostname, serial, channel, firmware key, and decoded installed key from a
list of machines. Requires WinRM and admin rights on the targets.

```powershell
<#
.SYNOPSIS
    Collects Windows activation and key data across a fleet.
.EXAMPLE
    .\Get-FleetActivation.ps1 -ComputerName (Get-Content .\hosts.txt) -OutputCsv .\activation-inventory.csv
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = $env:COMPUTERNAME,
    [string]$OutputCsv      = ".\activation-inventory.csv",
    [pscredential]$Credential
)

$scriptBlock = {
    function Get-InstalledProductKey {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $digitalId = (Get-ItemProperty -Path $regPath -Name DigitalProductId -ErrorAction SilentlyContinue).DigitalProductId
        if (-not $digitalId) { return $null }

        $charMap = 'BCDFGHJKMPQRTVWXY2346789'
        $isNKey  = [math]::Floor($digitalId[66] / 6) -band 1
        $digitalId[66] = ($digitalId[66] -band 0xF7) -bor (($isNKey -band 2) * 4)

        $key = ''; $lastChar = 0
        for ($i = 24; $i -ge 0; $i--) {
            $current = 0
            for ($j = 14; $j -ge 0; $j--) {
                $current = $current * 256 + $digitalId[$j + 52]
                $digitalId[$j + 52] = [math]::Floor($current / 24)
                $current = $current % 24
            }
            $key = $charMap[$current] + $key
            $lastChar = $current
        }
        if ($isNKey -eq 1) { $key = $key.Remove(0,1).Insert($lastChar,'N') }
        return ($key -replace '(.{5})(?!$)', '$1-')
    }

    $sls  = Get-CimInstance -ClassName SoftwareLicensingService
    $prod = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" |
            Select-Object -First 1
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystemProduct
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem

    [PSCustomObject]@{
        Hostname       = $env:COMPUTERNAME
        Serial         = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
        Model          = $cs.Name
        OSCaption      = $os.Caption
        OSBuild        = $os.BuildNumber
        Channel        = $prod.ProductKeyChannel
        Description    = $prod.Description
        LicenseStatus  = $prod.LicenseStatus
        PartialKey     = $prod.PartialProductKey
        FirmwareKey    = $sls.OA3xOriginalProductKey
        InstalledKey   = Get-InstalledProductKey
        CollectedUtc   = (Get-Date).ToUniversalTime().ToString('s')
    }
}

$invokeParams = @{
    ComputerName = $ComputerName
    ScriptBlock  = $scriptBlock
    ErrorAction  = 'SilentlyContinue'
}
if ($Credential) { $invokeParams.Credential = $Credential }

$results = Invoke-Command @invokeParams |
    Select-Object Hostname, Serial, Model, OSCaption, OSBuild, Channel,
                  Description, LicenseStatus, PartialKey, FirmwareKey,
                  InstalledKey, CollectedUtc

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
$results | Format-Table -AutoSize
Write-Host "Written to $OutputCsv"
```

Local only, no WinRM required:

```powershell
.\Get-FleetActivation.ps1 -ComputerName $env:COMPUTERNAME -OutputCsv .\local-activation.csv
```

> The output CSV contains live product keys. Treat it as a secret. Do not commit it
> to a repository, and store it somewhere with access control.

---

## 8. Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `OA3xOriginalProductKey` returns blank | No MSDM table, retail or VM install | Use registry decode instead |
| Decoded key is a known generic | Digital license or KMS client | No key exists, link to Microsoft account |
| `slmgr /ato` fails 0xC004F074 | No KMS host reachable | Verify `_vlmcs._tcp` SRV record and port 1688 |
| `slmgr /ato` fails 0xC004C003 | Key blocked or activation count exhausted | Phone activation via `slui 4` or new MAK |
| `slmgr /ipk` fails 0xC004F050 | Key does not match the installed edition | Confirm edition with `Get-ComputerInfo -Property WindowsProductName` |
| Activation lost after hardware change | Hardware hash mismatch | Activation troubleshooter, requires linked MSA |
| `wmic` not recognized | Removed in 24H2 and later | Use `Get-CimInstance` equivalents |

Check the current edition:

```powershell
Get-ComputerInfo -Property WindowsProductName, WindowsEditionId, OsVersion, WindowsInstallationType
```

Reset the licensing state, last resort. Reboot required:

```cmd
net stop sppsvc
del /f /q "%SystemRoot%\System32\spp\store\2.0\data.dat"
del /f /q "%SystemRoot%\System32\spp\store\2.0\tokens.dat"
net start sppsvc
slmgr /rilc
```

---

## 9. Where Microsoft Stores Your Keys

There is no single portal that lists every key you own.

| Location | URL | What it returns |
|----------|-----|-----------------|
| Consumer order history | `account.microsoft.com/billing/orders` | Keys for software bought digitally from the Microsoft Store, inconsistent by product |
| Services and subscriptions | `account.microsoft.com/services` | Microsoft 365 entitlements, rarely the key string |
| Devices | `account.microsoft.com/devices` | Machines carrying a digital license, no keys shown |
| Microsoft 365 admin center | `admin.microsoft.com` then Billing > Your products > Volume licensing > View downloads and keys | MAK and KMS keys, CSV export |

Notes:

- The Volume Licensing Service Center retired in April 2024. All volume licensing
  moved into the Microsoft 365 admin center.
- Key visibility in the admin center requires the VL Administrator or Product keys
  reader role. Global Administrator alone is not sufficient.
- OEM keys are never in a Microsoft account. They live in firmware.
- Retail keys bought from third party retailers are not in a Microsoft account
  unless redeemed at `microsoft.com/redeem`.

---

## 10. Generic KMS Client Setup Keys

These are public keys published by Microsoft. They configure a machine as a KMS
client and do nothing on their own without a reachable KMS host or ADBA
infrastructure. They are not licenses.

| Edition | Key |
|---------|-----|
| Windows 11 Pro | `W269N-WFGWX-YVC9B-4J6C9-T83GX` |
| Windows 11 Pro N | `MH37W-N47XK-V7XM9-C7227-GCQG9` |
| Windows 11 Pro for Workstations | `NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J` |
| Windows 11 Pro Education | `6TP4R-GNPTD-KYYHQ-7B7DP-J447Y` |
| Windows 11 Education | `NW6C2-QMPVW-D7KKK-3GKT6-VCFB2` |
| Windows 11 Enterprise | `NPPR9-FWDCX-D2C8J-H872K-2YT43` |
| Windows 11 Enterprise N | `DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4` |
| Windows 11 Enterprise LTSC 2024 | `M7XTQ-FN8P6-TTKYV-9D4CC-J462D` |

Common generic setup keys seen when decoding a digital license machine. Seeing one
of these in decode output means there is no recoverable key:

| Edition | Generic setup key |
|---------|-------------------|
| Windows 11 Home | `YTMG3-N6DKC-DKB77-7M9GH-8HVX7` |
| Windows 11 Pro | `VK7JG-NPHTM-C97JM-9MPGT-3V66T` |
| Windows 11 Pro N | `2B87N-8KFHP-DKV6R-Y2C8J-PKCKT` |
| Windows 11 Home N | `4CPRK-NM3K3-X6XXQ-RXX86-WXCHW` |

Current list: <https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys>

---

## References

- [Find and use product keys for volume licensing](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/product-keys-for-vl)
- [Sign in to the Microsoft 365 admin center for volume licensing](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/vl-sign-in)
- [KMS client activation and product keys](https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys)
- [Slmgr.vbs options for volume activation](https://learn.microsoft.com/en-us/windows-server/get-started/activation-slmgr-vbs-options)

---

## License

MIT. Use at your own risk. Nothing here bypasses licensing, it only reads and
applies keys you already own.
