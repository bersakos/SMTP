# =========================
# CONFIG
# =========================

$FromAddress = "test@domain.com"
$HostName    = "mail.domain.com"
$Port        = 587          # 25 = plain, 587 = STARTTLS, 465 = implicit SSL/TLS

$Auth        = $true
$Username    = "test@domain.com"
$Password    = "pass" # üresen bekéri

$ToAddress   = @("rcpt.domain.com")

$Subject     = "SMTP teszt by akos"
$Body        = "ez egy teszt mail"

$BodyIsHtml  = $false

# =========================
# SMTP RAW CLIENT (logs to console)
# =========================

Test-NetConnection $HostName -Port $Port

function Get-PlainAuthB64([string]$user, [string]$pass) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes([char]0 + $user + [char]0 + $pass)
    return [Convert]::ToBase64String($bytes)
}

function Read-SmtpResponse([System.IO.StreamReader]$r) {
    # Multiline: "250-" ... "250 "
    $lines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = $r.ReadLine()
        if ($null -eq $line) { throw "Connection closed by server." }
        $lines.Add($line)
        Write-Host ("S: {0}" -f $line)
        if ($line.Length -ge 4 -and $line[3] -eq ' ') { break }
    }
    return $lines
}

function Send-SmtpLine([System.IO.StreamWriter]$w, [string]$line, [switch]$Hide) {
    if ($Hide) {
        Write-Host "C: (hidden)"
    } else {
        Write-Host ("C: {0}" -f $line)
    }
    $w.WriteLine($line)
    $w.Flush()
}

function Get-Capabilities($ehloLines) {
    $caps = @()
    foreach ($l in $ehloLines) {
        if ($l.Length -ge 4) {
            $caps += $l.Substring(4).Trim()
        }
    }
    return $caps
}

try {
    if ($Auth -and [string]::IsNullOrWhiteSpace($Password)) {
        $sec = Read-Host "SMTP password" -AsSecureString
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        )
    }

    Write-Host ("`n=== CONNECT {0}:{1} ===`n" -f $HostName, $Port) -ForegroundColor Cyan

    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($HostName, $Port)

    $stream = $tcp.GetStream()

    # 465 = implicit TLS from the beginning
    if ($Port -eq 465) {
        $ssl = New-Object System.Net.Security.SslStream($stream, $false, { $true })
        $ssl.AuthenticateAsClient($HostName)
        $stream = $ssl
    }

    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
    $writer.NewLine = "`r`n"

    # Banner
    Read-SmtpResponse $reader | Out-Null

    # EHLO
    $clientName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($clientName)) { $clientName = "powershell-client" }

    Send-SmtpLine $writer ("EHLO {0}" -f $clientName)
    $ehlo = Read-SmtpResponse $reader
    $caps = Get-Capabilities $ehlo

    # 587 = STARTTLS upgrade
    if ($Port -eq 587) {
        $hasStartTls = $false
        foreach ($c in $caps) { if ($c -match '^STARTTLS$') { $hasStartTls = $true } }

        if (-not $hasStartTls) {
            throw ("Server does not advertise STARTTLS on port 587. Capabilities: {0}" -f ($caps -join ", "))
        }

        Send-SmtpLine $writer "STARTTLS"
        Read-SmtpResponse $reader | Out-Null

        $ssl = New-Object System.Net.Security.SslStream($stream, $false, { $true })
        $ssl.AuthenticateAsClient($HostName)
        $stream = $ssl

        # re-wrap reader/writer on TLS stream
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
        $writer.NewLine = "`r`n"

        # EHLO again after STARTTLS
        Send-SmtpLine $writer ("EHLO {0}" -f $clientName)
        $ehlo = Read-SmtpResponse $reader
        $caps = Get-Capabilities $ehlo
    }

    # AUTH
    if ($Auth) {
        $authCaps = ($caps | Where-Object { $_ -like "AUTH*" }) -join " "

        if ($authCaps -match 'PLAIN') {
            $b64 = Get-PlainAuthB64 $Username $Password
            Send-SmtpLine $writer ("AUTH PLAIN {0}" -f $b64) -Hide
            Read-SmtpResponse $reader | Out-Null
        }
        elseif ($authCaps -match 'LOGIN') {
            Send-SmtpLine $writer "AUTH LOGIN"
            Read-SmtpResponse $reader | Out-Null

            $u = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Username))
            $p = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Password))

            Send-SmtpLine $writer $u -Hide
            Read-SmtpResponse $reader | Out-Null

            Send-SmtpLine $writer $p -Hide
            Read-SmtpResponse $reader | Out-Null
        }
        else {
            throw ("Server did not advertise AUTH PLAIN/LOGIN. Capabilities: {0}" -f ($caps -join ", "))
        }
    }

    # MAIL FROM / RCPT TO
    Send-SmtpLine $writer ("MAIL FROM:<{0}>" -f $FromAddress)
    Read-SmtpResponse $reader | Out-Null

    foreach ($rcpt in $ToAddress) {
        Send-SmtpLine $writer ("RCPT TO:<{0}>" -f $rcpt)
        Read-SmtpResponse $reader | Out-Null
    }

    # DATA
    Send-SmtpLine $writer "DATA"
    Read-SmtpResponse $reader | Out-Null

    $date = (Get-Date).ToString("ddd, dd MMM yyyy HH:mm:ss K")

    if ($BodyIsHtml) { $mimeType = "text/html" } else { $mimeType = "text/plain" }

    $dataLines = @(
        ("From: <{0}>" -f $FromAddress),
        ("To: {0}" -f ($ToAddress -join ", ")),
        ("Subject: {0}" -f $Subject),
        ("Date: {0}" -f $date),
        "MIME-Version: 1.0",
        ("Content-Type: {0}; charset=utf-8" -f $mimeType),
        "",
        $Body
    )

    foreach ($l in $dataLines) {
        $out = $l
        if ($out.StartsWith(".")) { $out = "." + $out }  # dot-stuffing
        Send-SmtpLine $writer $out
    }

    # End of DATA
    Send-SmtpLine $writer "."
    Read-SmtpResponse $reader | Out-Null

    Send-SmtpLine $writer "QUIT"
    Read-SmtpResponse $reader | Out-Null

    Write-Host "`n=== SMTP SEND OK ===`n" -ForegroundColor Green
}
catch {
    Write-Host "`n=== SMTP SEND FAILED ===" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host ("Tippek:")
    Write-Host (" - Port teszt: Test-NetConnection {0} -Port 587 / 465" -f $HostName)
    Write-Host (" - hMailServer: TCP/IP ports: 587=STARTTLS, 465=SSL/TLS + certificate beállítva")
}
finally {
    if ($writer) { $writer.Dispose() }
    if ($reader) { $reader.Dispose() }
    if ($tcp) { $tcp.Close() }
}
