# Pad naar je JSON-configuratiebestand
$configPath = "C:\Users\Administrator\Documents\config.json"

# Laad de configuratie uit het JSON-bestand
try {
    # Lees de volledige inhoud van het bestand en converteer naar een PowerShell object
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} catch {
    # Foutmelding als het laden mislukt
    Write-Warning "Fout bij het lezen van het configuratiebestand: $_"
    exit
}

# Definieer een eenvoudige logfunctie om berichten in het logbestand te schrijven
function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "$timestamp - $message"
    Add-Content -Path $logFile -Value $logLine
}

# Laad de instellingen uit de configuratie
$logFile = $config.logFile
$sourcePath = $config.sourcePath
$destinationPath = $config.destinationPath
$useRobocopy = $config.useRobocopy
$excludePatterns = $config.excludePatterns
$dryRun = $config.dryRun
$robocopyRetries = $config.robocopyRetries
$robocopyWait = $config.robocopyWait

# Zorg dat de bron- en doelpaden eindigen op een backslash voor consistente paden
if (-not $sourcePath.EndsWith("\")) {
    $sourcePath += "\"
}
if (-not $destinationPath.EndsWith("\")) {
    $destinationPath += "\"
}

# Log de start en belangrijke parameters
Write-Log "Script gestart."
Write-Log "Bron: $sourcePath"
Write-Log "Doel: $destinationPath"
Write-Log "Gebruik Robocopy: $useRobocopy"

# Main kopieerproces
if ($useRobocopy) {
    # Als Robocopy wordt gebruikt, bouw dan de argumenten als een array
    $robocopyArgs = @(
        $sourcePath
        $destinationPath
        "/E" # Kopieer submappen, inclusief lege
        "/Z" # Herstartbare modus
        "/COPYALL" # Kopieer alle eigenschappen
        "/R:$robocopyRetries" # Aantal retries bij falen
        "/W:$robocopyWait" # Wachtduur tussen retries
        "/LOG+:$logFile" # Voeg logregels toe aan bestaand logbestand
    )

    if ($dryRun) {
        # In dry-run mode, toon wat er zou gebeuren zonder uit te voeren
        Write-Log "Dry run: robocopy met argumenten: $($robocopyArgs -join ' ')"
    } else {
        # Voer Robocopy uit binnen try-catch voor foutafhandeling
        try {
            robocopy @robocopyArgs
            Write-Log "Robocopy voltooid."
        } catch {
            # Log eventuele fouten
            Write-Warning "Fout tijdens Robocopy: $_"
            Write-Log "Fout tijdens Robocopy: $_"
        }
    }
} else {
    # Alternatief: gebruik PowerShell om bestanden en mappen te kopiëren

    # Controleer of de bronmap bestaat
    if (!(Test-Path $sourcePath)) {
        Write-Warning "Bronmap bestaat niet: $sourcePath"
        Write-Log "Bronmap bestaat niet: $sourcePath"
    } else {
        # Maak de doelmap indien deze niet bestaat
        if (!(Test-Path $destinationPath)) {
            if ($dryRun) {
                Write-Log "Dry run: doelmap $destinationPath zou worden aangemaakt."
            } else {
                try {
                    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
                    Write-Log "Doelmap aangemaakt: $destinationPath"
                } catch {
                    Write-Warning "Kan doelmap niet aanmaken: $destinationPath. $_"
                    Write-Log "Kan doelmap niet aanmaken: $destinationPath. $_"
                }
            }
        }

        # Haal alle items (bestanden en mappen) op uit de bronmap, inclusief verborgen en systeem bestanden
        try {
            $items = Get-ChildItem -Path $sourcePath -Recurse -Force
        } catch {
            # Fout bij ophalen van items
            Write-Warning "Fout bij ophalen items: $_"
            Write-Log "Fout bij ophalen items: $_"
            $items = @()
        }

        # Filter items op basis van exclude patronen indien aanwezig
        if ($excludePatterns -and $excludePatterns.Count -gt 0) {
            $originalCount = $items.Count
            $items = $items | Where-Object {
                $exclude = $false
                foreach ($pattern in $excludePatterns) {
                    if ($_.Name -match $pattern) {
                        $exclude = $true
                        break
                    }
                }
                -not $exclude
            }
            $excludedCount = $originalCount - $items.Count
            Write-Log "Gevonden $originalCount items, $excludedCount uitgesloten."
        } else {
            Write-Log "Gevonden $(($items | Measure-Object).Count) items om te kopiëren."
        }

        # Loop door alle items en kopieer ze naar de doelmap
        foreach ($item in $items) {
            try {
                # Bepaal het relative pad van het item ten opzichte van de bronmap
                $relativePath = $item.FullName.Substring($sourcePath.Length)
                # Combineer met doelmap om het bestemmingspad te krijgen
                $destItemPath = Join-Path $destinationPath $relativePath

                if ($item.PSIsContainer) {
                    # Map aanmaken indien nodig
                    if (!(Test-Path $destItemPath)) {
                        if ($dryRun) {
                            Write-Log "Dry run: map $destItemPath zou worden aangemaakt."
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destItemPath -Force | Out-Null
                                Write-Log "Map aangemaakt: $destItemPath"
                            } catch {
                                Write-Warning "Kan map niet aanmaken: $destItemPath. $_"
                                Write-Log "Kan map niet aanmaken: $destItemPath. $_"
                            }
                        }
                    }
                } else {
                    # Bestand kopiëren
                    $destDir = Split-Path -Path $destItemPath -Parent
                    # Map voor het bestand aanmaken indien nodig
                    if (!(Test-Path $destDir)) {
                        if ($dryRun) {
                            Write-Log "Dry run: doelmap $destDir zou worden aangemaakt voor bestand."
                        } else {
                            try {
                                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                                Write-Log "Doelmap aangemaakt voor bestand: $destDir"
                            } catch {
                                Write-Warning "Kan doelmap niet aanmaken: $destDir. $_"
                                Write-Log "Kan doelmap niet aanmaken: $destDir. $_"
                                continue
                            }
                        }
                    }
                    # Bestand kopiëren
                    if ($dryRun) {
                        Write-Log "Dry run: bestand $($item.FullName) zou worden gekopieerd naar $destItemPath."
                    } else {
                        try {
                            Copy-Item -Path $item.FullName -Destination $destItemPath -Force
                            Write-Log "Bestand gekopieerd: $($item.FullName) naar $destItemPath"
                        } catch {
                            Write-Warning "Fout bij kopiëren: $($item.FullName). $_"
                            Write-Log "Fout bij kopiëren: $($item.FullName). $_"
                        }
                    }
                }
            } catch {
                # Fout bij verwerken van een item
                Write-Warning "Fout bij verwerken item: $($_.FullName). $_"
                Write-Log "Fout bij verwerken item: $($_.FullName). $_"
            }
        }
        Write-Host "Kopiëren voltooid (met fouten indien aanwezig)."
        Write-Log "Kopiëren voltooid."
    }
}

# Log het einde van het script
Write-Log "Script voltooid."