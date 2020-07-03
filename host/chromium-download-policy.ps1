$ErrorActionPreference = "SilentlyContinue"

# Funktion zum Senden von JSON an Erweiterung
# https://docs.jabref.org/collect/jabref-browser-extension
function Respond($response) {
    $jsonResponse = $response | ConvertTo-Json

    try {
        $writer = New-Object System.IO.BinaryWriter([System.Console]::OpenStandardOutput())
        $writer.Write([int]$jsonResponse.Length)
        $writer.Write([System.Text.Encoding]::UTF8.GetBytes($jsonResponse))
        $writer.Close()
    } finally {
        $writer.Dispose()
    }
}

try {

    # Rückgabe
    $resultStatus = "ERROR"
    $resultError = "Unerwarteter Fehler beim Schreiben der Logdatei!"
    $logFile = "undefined"

    # StdIn von Erweiterung lesen
    $reader = New-Object System.IO.BinaryReader([System.Console]::OpenStandardInput())
    $length = $reader.ReadInt32()
    $messageRaw = [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($length))
    $message = $messageRaw | ConvertFrom-Json

    # Umbrüche für Add-Content vorbereiten
    $recievedMessageText = $message.text.Replace("\n", "`r")

    if ($recievedMessageText -eq "SCANFILE") {

        $resultStatus = "ERROR_SCANNING_FILE"
        $resultError = "Datei nicht gefunden"
        $scannedFiles = ""

        # GPO-Logpfad und Regex des Dateinamens einlesen
        $path = $message.path
        $fileregex = $message.fileregex

        # Datei in Download-Ordner entsprechend der übergebenen Regex finden
        Get-ChildItem -Path "$path" -Recurse | Where-Object { $_.FullName -match "$fileregex" } | % {
            $filePath = $_.FullName

            # TODO: Vollqualifizierten Dateipfad an Scan-Skript übergeben
            # scan.ps1 "$filePath"
            $scannedFiles += "$filePath;"

            $resultStatus = "SUCCESS"
            $resultError = ""
        }

        # Rückmeldung an Erweiterung senden
        return Respond @{
            status = "$resultStatus";
            lastError = "$resultError";
            scannedFiles = "$scannedFiles"
        }

    } else {

        # Logpfad aus Message auslesen oder Script-Root verwenden
        $messageLogPath = $message.logpath
        if (($messageLogPath -eq "undefined") -or ($messageLogPath -eq "")) {
            $messageLogPath = "$PSScriptRoot\logs"
        }
    
        # Message in Logdatei pro User schreiben
        $user = $env:UserName
        $logFile = [System.IO.Path]::Combine($messageLogPath, $user + "_download.log")
        if (!(Test-Path $logFile)) {

            # Add-Content legt Ordner-Struktur nicht an --> mit New-Item anlegen
            New-Item -Path $logFile -Force | Out-Null
            if($error) {
                $resultStatus = "ERROR_CREATING_LOGFILE"
                $resultError = $error
            } else {
                $resultStatus = "SUCCESS"
                $resultError = ""
            }

        }
    
        # Sofern nur Verbindungstest keine neuen Inhalte in Datei schreiben
        if($recievedMessageText -like "*TEST_HOST_COMMUNICATION*") {
            
            # Datei im Schreibmodus öffnen (keine Inhalte schreiben)
            try {
                [io.file]::OpenWrite($logFile).close()
                $resultStatus = "SUCCESS"
                $resultError = ""
            } catch {
                $resultStatus = "ERROR_WRITING_TO_LOGFILE"
                $resultError = "No write access for file $logfile"
            }
    
        } else {
    
            # Ereignis in Protokolldatei schreiben (anhängen)
            Add-Content $logFile "$recievedMessageText" | Out-Null
            if($error) {
                $resultStatus = "ERROR_WRITING_TO_LOGFILE"
                $resultError = $error
            } else {
                $resultStatus = "SUCCESS"
                $resultError = ""
            }
    
        }

        # Rückmeldung an Erweiterung senden
        return Respond @{
            status = "$resultStatus";
            lastError = "$resultError";
            recievedMessageText = "$recievedMessageText"
            logFile = "$logfile"
        }

    }

} finally {

    $reader.Dispose()

}