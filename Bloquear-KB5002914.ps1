param(
    [switch]$Guard
)

# ============================================================
# BLOQUEO KB5002914 - Excel 2016 x86 / x64
# - Desinstala KB5002914
# - Oculta KB5002914 en Microsoft Update
# - Instala tarea programada que revisa cada hora
# - Funciona con Office 2016 32-bit y 64-bit
# ============================================================

$ErrorActionPreference = "Continue"

$KBNumber = "5002914"
$KB       = "KB5002914"

$BasePath   = "C:\ProgramData\KB5002914-Blocker"
$ScriptDest = "$BasePath\Bloquear-KB5002914.ps1"
$LogFile    = "$BasePath\KB5002914.log"

$TaskName = "Bloquear KB5002914 Excel 2016"

# ------------------------------------------------------------
# CREAR CARPETA
# ------------------------------------------------------------

if (-not (Test-Path $BasePath)) {
    New-Item -Path $BasePath -ItemType Directory -Force | Out-Null
}

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message,
        [string]$Color = "White"
    )

    $Fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Linea = "[$Fecha] $Message"

    Add-Content -Path $LogFile -Value $Linea -Encoding UTF8

    if (-not $Guard) {
        Write-Host $Linea -ForegroundColor $Color
    }
}

# ------------------------------------------------------------
# VERIFICAR ADMINISTRADOR
# ------------------------------------------------------------

$Admin = (
    New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $Admin) {

    Write-Host ""
    Write-Host "ERROR: Ejecuta PowerShell como Administrador." -ForegroundColor Red
    Write-Host ""

    exit 1
}

# ------------------------------------------------------------
# TLS 1.2 PARA POWERSHELL GALLERY
# ------------------------------------------------------------

try {

    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor `
        [Net.SecurityProtocolType]::Tls12

}
catch {}

# ------------------------------------------------------------
# RUTAS DE REGISTRO OFFICE 32/64 BITS
# ------------------------------------------------------------

$RegPaths = @(

    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",

    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"

)

# ------------------------------------------------------------
# BUSCAR KB INSTALADA
# ------------------------------------------------------------

function Get-KB5002914Installed {

    Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue |
        Where-Object {

            $_.DisplayName -and
            $_.DisplayName -match "KB5002914"

        }
}

# ------------------------------------------------------------
# DESINSTALAR KB
# ------------------------------------------------------------

function Remove-KB5002914 {

    $Updates = @(Get-KB5002914Installed)

    if ($Updates.Count -eq 0) {

        Write-Log "$KB no aparece instalada." "Green"
        return

    }

    Write-Log "$KB ESTA INSTALADA." "Yellow"

    # En ejecucion automatica no cerrar Excel para evitar perdida
    $Excel = Get-Process EXCEL -ErrorAction SilentlyContinue

    if ($Guard -and $Excel) {

        Write-Log "Excel esta abierto. Se pospone la desinstalacion para evitar perdida de documentos." "Yellow"
        return

    }

    # Ejecucion manual: cerrar Excel
    if ((-not $Guard) -and $Excel) {

        Write-Log "Cerrando Excel antes de retirar la actualizacion..." "Yellow"

        Stop-Process -Name EXCEL -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2
    }

    # Evitar ejecutar UninstallString duplicados
    $Commands = $Updates |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.UninstallString)
        } |
        Select-Object -ExpandProperty UninstallString -Unique

    foreach ($Command in $Commands) {

        Write-Log "Ejecutando desinstalacion registrada por Office..." "Yellow"

        # UninstallString normalmente viene:
        # "C:\...\Oarpmany.exe" argumentos...

        if ($Command -match '^"([^"]+)"\s*(.*)$') {

            $Exe  = $Matches[1]
            $Args = $Matches[2]

        }
        elseif ($Command -match '^(\S+)\s*(.*)$') {

            $Exe  = $Matches[1]
            $Args = $Matches[2]

        }
        else {

            Write-Log "No se pudo interpretar: $Command" "Red"
            continue

        }

        if (-not (Test-Path $Exe)) {

            Write-Log "No existe el ejecutable: $Exe" "Red"
            continue

        }

        try {

            $Process = Start-Process `
                -FilePath $Exe `
                -ArgumentList $Args `
                -Wait `
                -PassThru `
                -ErrorAction Stop

            Write-Log "Resultado desinstalacion: ExitCode $($Process.ExitCode)" "Cyan"

        }
        catch {

            Write-Log "ERROR desinstalando: $($_.Exception.Message)" "Red"

        }
    }

    Start-Sleep -Seconds 3

    $Check = @(Get-KB5002914Installed)

    if ($Check.Count -eq 0) {

        Write-Log "$KB ya no aparece instalada." "Green"

    }
    else {

        Write-Log "$KB todavia aparece en el registro. Puede requerir reinicio." "Yellow"

    }
}

# ------------------------------------------------------------
# INSTALAR / CARGAR PSWINDOWSUPDATE
# ------------------------------------------------------------

function Initialize-PSWindowsUpdate {

    try {

        Set-ExecutionPolicy `
            -Scope Process `
            -ExecutionPolicy Bypass `
            -Force `
            -ErrorAction SilentlyContinue

    }
    catch {}

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {

        Write-Log "PSWindowsUpdate no esta instalado. Instalando..." "Yellow"

        try {

            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion 2.8.5.201 `
                -Force `
                -ErrorAction SilentlyContinue |
                Out-Null

            Set-PSRepository `
                -Name PSGallery `
                -InstallationPolicy Trusted `
                -ErrorAction SilentlyContinue

            Install-Module `
                -Name PSWindowsUpdate `
                -Scope AllUsers `
                -Force `
                -AllowClobber `
                -Confirm:$false `
                -ErrorAction Stop

        }
        catch {

            Write-Log "ERROR instalando PSWindowsUpdate: $($_.Exception.Message)" "Red"
            return $false

        }
    }

    try {

        Import-Module PSWindowsUpdate -Force -ErrorAction Stop

        return $true

    }
    catch {

        Write-Log "ERROR cargando PSWindowsUpdate: $($_.Exception.Message)" "Red"
        return $false

    }
}

# ------------------------------------------------------------
# REGISTRAR MICROSOFT UPDATE
# ------------------------------------------------------------

function Enable-MicrosoftUpdate {

    try {

        Add-WUServiceManager `
            -MicrosoftUpdate `
            -Confirm:$false `
            -ErrorAction SilentlyContinue |
            Out-Null

    }
    catch {}
}

# ------------------------------------------------------------
# OCULTAR KB5002914
# ------------------------------------------------------------

function Hide-KB5002914 {

    if (-not (Initialize-PSWindowsUpdate)) {
        return
    }

    Enable-MicrosoftUpdate

    Write-Log "Consultando Microsoft Update por $KB..." "Cyan"

    try {

        $Available = @(
            Get-WindowsUpdate `
                -MicrosoftUpdate `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.KB -match $KBNumber
                }
        )

        if ($Available.Count -gt 0) {

            Write-Log "$KB esta disponible. Ocultando..." "Yellow"

            Hide-WindowsUpdate `
                -KBArticleID $KB `
                -MicrosoftUpdate `
                -Confirm:$false `
                -ErrorAction SilentlyContinue |
                Out-Null

            Start-Sleep -Seconds 2

        }
        else {

            Write-Log "$KB no esta siendo ofrecida actualmente." "Green"

        }

        $Hidden = @(
            Get-WindowsUpdate `
                -MicrosoftUpdate `
                -IsHidden `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.KB -match $KBNumber
                }
        )

        if ($Hidden.Count -gt 0) {

            Write-Log "$KB esta OCULTA / BLOQUEADA (Hidden)." "Green"

            if (-not $Guard) {

                $Hidden |
                    Select-Object ComputerName,Status,KB,Size,Title |
                    Format-Table -AutoSize

            }

        }
        else {

            Write-Log "$KB no aparece como Hidden. Se volvera a revisar en la siguiente ejecucion." "Yellow"

        }

    }
    catch {

        Write-Log "ERROR consultando Windows Update: $($_.Exception.Message)" "Red"

    }
}

# ------------------------------------------------------------
# MODO GUARD
# Ejecucion desde tarea programada
# ------------------------------------------------------------

if ($Guard) {

    Write-Log "===== Inicio comprobacion automatica ====="

    Remove-KB5002914

    Hide-KB5002914

    Write-Log "===== Fin comprobacion automatica ====="

    exit 0
}

# ============================================================
# EJECUCION MANUAL / INSTALACION DEL BLOQUEO
# ============================================================

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " KB5002914 - EXCEL 2016 x86/x64" -ForegroundColor Cyan
Write-Host " Desinstalacion + bloqueo persistente" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Inicio configuracion de proteccion KB5002914."

# ------------------------------------------------------------
# COPIAR ESTE SCRIPT A PROGRAMDATA
# ------------------------------------------------------------

if ($PSCommandPath) {

    try {

        Copy-Item `
            -Path $PSCommandPath `
            -Destination $ScriptDest `
            -Force

        Write-Log "Script copiado a $ScriptDest" "Green"

    }
    catch {

        Write-Log "ERROR copiando script: $($_.Exception.Message)" "Red"

    }

}
else {

    Write-Log "ERROR: Debes ejecutar el codigo desde un archivo .ps1." "Red"
    exit 1

}

# ------------------------------------------------------------
# RETIRAR KB AHORA
# ------------------------------------------------------------

Remove-KB5002914

# ------------------------------------------------------------
# BLOQUEAR KB AHORA
# ------------------------------------------------------------

Hide-KB5002914

# ------------------------------------------------------------
# CREAR TAREA PROGRAMADA
# ------------------------------------------------------------

Write-Log "Creando tarea programada persistente..." "Cyan"

try {

    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

}
catch {}

$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$Action = New-ScheduledTaskAction `
    -Execute $PowerShell `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptDest`" -Guard"

# Al iniciar Windows
$TriggerStartup = New-ScheduledTaskTrigger -AtStartup

# Revisar cada hora
$TriggerHourly = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Hours 1)

$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger @(
        $TriggerStartup,
        $TriggerHourly
    ) `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Evita la instalacion de KB5002914 de Excel 2016 y la oculta nuevamente si Microsoft Update vuelve a ofrecerla." `
    -Force |
    Out-Null

Write-Log "Tarea programada creada correctamente." "Green"

# ------------------------------------------------------------
# VERIFICACION
# ------------------------------------------------------------

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " RESULTADO" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

$InstalledFinal = @(Get-KB5002914Installed)

if ($InstalledFinal.Count -eq 0) {

    Write-Host "INSTALADA : NO" -ForegroundColor Green

}
else {

    Write-Host "INSTALADA : SI - Reinicia el equipo." -ForegroundColor Yellow

}

try {

    $HiddenFinal = @(
        Get-WindowsUpdate `
            -MicrosoftUpdate `
            -IsHidden `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.KB -match $KBNumber
            }
    )

    if ($HiddenFinal.Count -gt 0) {

        Write-Host "BLOQUEADA : SI (Hidden)" -ForegroundColor Green

        $HiddenFinal |
            Select-Object ComputerName,Status,KB,Size,Title |
            Format-Table -AutoSize

    }
    else {

        Write-Host "BLOQUEADA : Aun no aparece como Hidden." -ForegroundColor Yellow
        Write-Host "La tarea la ocultara cuando Microsoft Update vuelva a ofrecerla." -ForegroundColor Yellow

    }

}
catch {}

Write-Host ""
Write-Host "TAREA     : $TaskName" -ForegroundColor Green
Write-Host "REVISION  : Inicio de Windows + cada 1 hora" -ForegroundColor Green
Write-Host "LOG       : $LogFile" -ForegroundColor Green
Write-Host ""

Write-Host "Se recomienda reiniciar el equipo." -ForegroundColor Yellow
Write-Host ""