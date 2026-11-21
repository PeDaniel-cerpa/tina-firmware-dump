<#
.SYNOPSIS
    Escribe una imagen FAT32 superfloppy en una microSD usando Windows.

.DESCRIPTION
    Version parametrizada del metodo que funciono en la practica.
    Se eleva automaticamente a Administrador.

    Windows bloquea la escritura en crudo de discos extraibles mientras el
    volumen esta montado. Por eso se usa FSCTL_DISMOUNT_VOLUME antes de escribir.
    diskpart no sirve aqui: "No se admite la operacion en medios extraibles".

    AVISO: el disco elegido se BORRA COMPLETAMENTE.

.EXAMPLE
    .\write_sd_windows.ps1 -ImagePath .\firmware_dump.img -DiskNumber 1 -DriveLetter F
#>
param(
    [Parameter(Mandatory=$true)]  [string] $ImagePath,
    [Parameter(Mandatory=$true)]  [int]    $DiskNumber,
    [Parameter(Mandatory=$true)]  [string] $DriveLetter
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- elevacion ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando permisos de Administrador (UAC)..." -ForegroundColor Yellow
    $argsEsc = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"'),
        '-ImagePath', ('"' + $ImagePath + '"'),
        '-DiskNumber', $DiskNumber,
        '-DriveLetter', $DriveLetter
    )
    Start-Process powershell.exe -ArgumentList $argsEsc -Verb RunAs -Wait
    exit
}

# ------------------------------------------------------------------- helpers --
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class RawDisk {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess,
      uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
      uint dwFlagsAndAttributes, IntPtr hTemplateFile);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
      IntPtr lpInBuffer, uint nInBufferSize, IntPtr lpOutBuffer, uint nOutBufferSize,
      out uint lpBytesReturned, IntPtr lpOverlapped);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool WriteFile(IntPtr hFile, IntPtr lpBuffer,
      uint nNumberOfBytesToWrite, out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr hObject);

  public const uint GENERIC_READ  = 0x80000000;
  public const uint GENERIC_WRITE = 0x40000000;
  public const uint OPEN_EXISTING = 3;
  public const uint FILE_SHARE_READ  = 1;
  public const uint FILE_SHARE_WRITE = 2;
  public const uint FSCTL_DISMOUNT_VOLUME = 0x00090020;
}
'@

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'HH:mm:ss')  $msg"
    Write-Host $line
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
}

# ------------------------------------------------------------------ variables -
$logFile = Join-Path $env:TEMP 'write_sd_result.txt'
"=== INICIO $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding utf8

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "No existe la imagen: $ImagePath"
}
$ImageFull = (Resolve-Path -LiteralPath $ImagePath).Path
$ImageSize = (Get-Item -LiteralPath $ImageFull).Length
$devPath = "\\.\PhysicalDrive$DiskNumber"
$volPath = "\\.\$($DriveLetter.TrimEnd(':')):"

Write-Log "Imagen : $ImageFull ($ImageSize bytes)"
Write-Log "Disco  : $devPath"
Write-Log "Volumen: $volPath"

# Confirmacion de seguridad
$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
Write-Log "Disco detectado: $($disk.FriendlyName)  $($disk.PartitionStyle)  $([math]::Round($disk.Size/1GB,2)) GB"
$answer = Read-Host "Esto BORRARA todo el disco $DiskNumber. Escribe SI para continuar"
if ($answer -ne 'SI') { Write-Log "Cancelado por el usuario"; exit }

try {
    # Asegurar que el disco este online y no sea de solo lectura
    Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue

    # Si la particion no tiene letra, asignarla
    Get-Partition -DiskNumber $DiskNumber |
        Where-Object { -not $_.DriveLetter } |
        ForEach-Object {
            Set-Partition -DiskNumber $DiskNumber -PartitionNumber $_.PartitionNumber `
                          -NewDriveLetter $DriveLetter -ErrorAction SilentlyContinue
        }

    # Desmontar el volumen: sin esto Windows devuelve "Acceso denegado"
    $share = [RawDisk]::FILE_SHARE_READ -bor [RawDisk]::FILE_SHARE_WRITE
    $access = [RawDisk]::GENERIC_READ -bor [RawDisk]::GENERIC_WRITE
    $vol = [RawDisk]::CreateFile($volPath, $access, $share,
        [IntPtr]::Zero, [RawDisk]::OPEN_EXISTING, 0, [IntPtr]::Zero)
    if ($vol -eq [IntPtr]::Zero -or $vol -eq [IntPtr](-1)) {
        throw "No se pudo abrir el volumen $volPath"
    }
    Write-Log "Volumen abierto (handle $vol)"

    $br = [uint32]0
    $dis = [RawDisk]::DeviceIoControl($vol, [RawDisk]::FSCTL_DISMOUNT_VOLUME,
        [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$br, [IntPtr]::Zero)
    Write-Log "FSCTL_DISMOUNT_VOLUME: $dis"
    if (-not $dis) { throw "No se pudo desmontar el volumen" }

    # Abrir el disco fisico
    $dev = [RawDisk]::CreateFile($devPath, $access, $share,
        [IntPtr]::Zero, [RawDisk]::OPEN_EXISTING, 0, [IntPtr]::Zero)
    if ($dev -eq [IntPtr]::Zero -or $dev -eq [IntPtr](-1)) {
        throw "No se pudo abrir $devPath"
    }
    Write-Log "Disco abierto (handle $dev)"

    # Leer la imagen. Este metodo reserva ~el tamano de la imagen en RAM
    # (1 GB en la configuracion por defecto).
    Write-Log "Leyendo imagen en memoria..."
    $img = [IO.File]::OpenRead($ImageFull)
    $ms  = New-Object IO.MemoryStream
    $img.CopyTo($ms)
    $bytes = $ms.ToArray()
    $img.Close(); $ms.Close()
    Write-Log "Bytes leidos: $($bytes.Length)"

    $written = [uint32]0
    $hGlobal = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
    try {
        [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $hGlobal, $bytes.Length)
        $ok = [RawDisk]::WriteFile($dev, $hGlobal, [uint32]$bytes.Length,
                                   [ref]$written, [IntPtr]::Zero)
        Write-Log "WriteFile: $ok  escritos=$written"
        if (-not $ok -or $written -ne $bytes.Length) {
            throw "La escritura no se completo"
        }
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($hGlobal)
        [RawDisk]::CloseHandle($dev) | Out-Null
        [RawDisk]::CloseHandle($vol) | Out-Null
    }

    Write-Log "ESCRITURA COMPLETADA"
    Write-Log ""
    Write-Log "Comprueba con:"
    Write-Log "  Get-Volume -DriveLetter $DriveLetter | Select DriveLetter,FileSystem,Size"
    Write-Log "  Get-ChildItem ${DriveLetter}:\"
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
Write-Log "=== FIN $(Get-Date) ==="
