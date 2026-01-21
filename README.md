# PowerShell Raw SMTP Test Client

A portable, installation-free **raw SMTP test client** written in PowerShell.
It sends an email using **direct SMTP protocol commands** and prints the **entire SMTP conversation to the console**.

This tool is intended for **SMTP troubleshooting, authentication testing, and TLS diagnostics**, similar to tools like `swaks`, but without external dependencies.

---

## Features

- ✅ No installation required
- ✅ Works with **Windows PowerShell 5.1** and **PowerShell 7+**
- ✅ Full SMTP protocol transcript printed to console
- ✅ Supports SMTP ports:
  - **25** – plain SMTP
  - **587** – STARTTLS
  - **465** – implicit SSL/TLS
- ✅ SMTP authentication:
  - `AUTH PLAIN`
  - `AUTH LOGIN`
- ✅ STARTTLS capability detection
- ✅ Proper SMTP multiline response handling
- ✅ RFC-compliant dot-stuffing
- ✅ Secure password prompt if password is omitted

---

## Configuration

Edit the **CONFIG** section at the top of the script:

```powershell
$FromAddress = "test@domain.com"
$HostName    = "mail.domain.com"
$Port        = 587          # 25 = plain, 587 = STARTTLS, 465 = implicit SSL/TLS

$Auth        = $true
$Username    = "test@domain.com"
$Password    = "pass"       # leave empty to prompt securely

$ToAddress   = @("rcpt@domain.com")

$Subject     = "SMTP test"
$Body        = "This is a test email"

$BodyIsHtml  = $false       # $true for HTML body
```

## **Notes**
If $Password is empty, the script will prompt for it securely.
$BodyIsHtml = $true sends Content-Type: text/html.
Multiple recipients can be added to $ToAddress.

## **Example Output**
```
S: 220 mail.domain.com ESMTP
C: EHLO CLIENT
S: 250-STARTTLS
C: STARTTLS
S: 220 Ready to start TLS
C: AUTH PLAIN (hidden)
S: 235 Authentication successful
C: MAIL FROM:<test@domain.com>
S: 250 OK
```

## **Security Warning**

⚠️ This script is intended for testing and diagnostics only
SMTP credentials are Base64-encoded during authentication
Credentials may be visible in memory or logs
Use only in trusted environments
Do not use in production automation without additional safeguards

## **Requirements**

PowerShell 5.1 or newer
Network access to the SMTP server
Valid SMTP credentials (if authentication is enabled)

## **Troubleshooting**

If the script fails:
1. Verify port connectivity:
      Test-NetConnection mail.domain.com -Port 587
2. Check SMTP server configuration:
   STARTTLS enabled on port 587
   SSL/TLS enabled on port 465
   Valid TLS certificate installed
3. Ensure SMTP AUTH is enabled for the mailbox

The console output will show exactly where the SMTP conversation fails.


## **Use Cases**

- SMTP server validation
- Authentication troubleshooting
- TLS / STARTTLS verification
- Firewall and port testing
- Replacement for legacy SMTP test utilities

## **License**

Free to use for testing and troubleshooting purposes.
