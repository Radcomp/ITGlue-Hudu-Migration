# Main settings load
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Lite'

# Replace TestImage() with Invoke-ImageTest()
. $PSScriptRoot\Private\Invoke-ImageTest.ps1

# Staging Directory
$StagingRoot = (Get-Item $MigrationLogs).Parent.FullName

# Attachments Path
$AttachmentsPath = (Join-Path -Path $ITGLueExportPath -ChildPath "attachments")

###################### Initial Setup and Confirmations ###############################
Write-Host "#######################################################" -ForegroundColor Yellow
Write-Host "#                                                     #" -ForegroundColor Yellow
Write-Host "#          IT Glue to Hudu Migration Script           #" -ForegroundColor Yellow
Write-Host "#           - File Attachment Uploads                 #" -ForegroundColor Yellow
Write-Host "#          Version: 2.0  -Beta                        #" -ForegroundColor Yellow
Write-Host "#          Date: 01/08/2023                           #" -ForegroundColor Yellow
Write-Host "#                                                     #" -ForegroundColor Yellow
Write-Host "#                                                     #" -ForegroundColor Yellow
Write-Host "#                                                     #" -ForegroundColor Yellow
Write-Host "#         The script will attempt to upload your      #" -ForegroundColor Yellow
Write-Host "#         files directly to Hudu using the API.       #" -ForegroundColor Yellow
Write-Host "#         Performance will depend on the Hudu         #" -ForegroundColor Yellow
Write-Host "#           backend, such as API Limits and WAN       #" -ForegroundColor Yellow
Write-Host "#                                                     #" -ForegroundColor Yellow
Write-Host "#######################################################" -ForegroundColor Yellow
Write-Host "# Note: This is an unofficial script, please do not   #" -ForegroundColor Yellow
Write-Host "# contact Hudu support if you run into issues.        #" -ForegroundColor Yellow
Write-Host "# For support please visit the Hudu Sub-Reddit:       #" -ForegroundColor Yellow
Write-Host "# https://www.reddit.com/r/hudu/                      #" -ForegroundColor Yellow
Write-Host "# The #v-hudu channel on the MSPGeek Slack/Discord:   #" -ForegroundColor Yellow
Write-Host "# https://join.mspgeek.com/                           #" -ForegroundColor Yellow
Write-Host "# Or log an issue in the Github Respository:          #" -ForegroundColor Yellow
Write-Host "# https://github.com/lwhitelock/ITGlue-Hudu-Migration #" -ForegroundColor Yellow
Write-Host "#######################################################" -ForegroundColor Yellow

################### Supporting Functions ###############################
# Uses migration computer to determine file types (not required, but improved QOL)
function Get-MimeType {
    param($Extension = $null)
    $mimeType = $null
    if ( $null -ne $Extension ) {
        $drive = Get-PSDrive HKCR -ErrorAction SilentlyContinue
        if ( $null -eq $drive ) {
            $drive = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT
        }
        $mimeType = (Get-ItemProperty HKCR:$extension -ErrorAction SilentlyContinue).'Content Type'
    }
    $mimeType
}

# Upload to Hudu with S3 Storage
function New-HuduUpload {
    Param(
        $Connection,
        $FilePath,
        $ArticleId,
        $UploadType = 'Article'
    )

    if (! (Test-Path $FilePath)) {
        Write-Error "$FilePath does not exist"
        return
    }

    $File = Get-Item $FilePath
    try {
        $Magick = New-Object ImageMagick.MagickImage($FilePath)
        $Width = $Magick.Width
        $Height = $Magick.Height
    }
    catch {
        $Width = $null
        $Height = $null        
    }
    $MimeType = Get-MimeType -extension $File.Extension
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.ffffff'

    $UploadIndex = (Get-PSQLData -Connection $Connection -Query "INSERT INTO public.uploads (file_data,uploadable_type,uploadable_id,account_id,created_at,updated_at) VALUES ('{}','$UploadType',$ArticleId,1,'$Timestamp','$Timestamp') RETURNING id").id
    $StagingPath = "upload/$UploadIndex/file/"
    $Destination = (New-Item "$($StagingRoot)\$($StagingPath)" -ItemType Directory -Force).FullName
    $OriginalMetadata = [PSCustomObject]@{
        filename  = $File.Name
        size      = $File.Length
        width     = $Width
        height    = $Height
        mime_type = $MimeType
    }

    $OrigGuid = [guid]::newguid() -replace '-'
    $OriginalName = '{0}{1}' -f $OrigGuid, $File.Extension
    $OrigKey = ('{0}{1}' -f $StagingPath, $OriginalName)

    $CopyItem = @{
        Destination  = "$($Destination)\$($OriginalName)"
        Force = $true
        Path        = $FilePath
    }
    Copy-Item @CopyItem | Out-Null

    $UploadData = [PSCustomObject]@{
        id       = $OrigKey
        storage  = 'store'
        metadata = $OriginalMetadata 
    } 
    $Upload = $UploadData | ConvertTo-Json -Depth 10 -Compress
    $Query = "UPDATE public.uploads SET file_data = '$Upload' where id = $UploadIndex"
    
    try {
        Set-PSQLData -Connection $Connection -Query $Query | Out-Null

        [PSCustomObject]@{
            FileHref  = "/file/$UploadIndex"
            ArticleId = $ArticleId
            FileData  = $UploadData
            status  = "Staged Successfully"
        }
    }
    catch {
        Write-Error ('Insert exception: {0}' -f $_.Exception.Message)
        [PSCustomObject]@{
            FileHref  = "/file/$UploadIndex"
            ArticleId = $ArticleId
            FileData  = $UploadData
            status  = "FAILED: $($_.Exception.Message)"
        }
    }
}

# Function for looping over found assets and attachments. Requires PSQL Connection
function Add-HuduAttachment {
param(
    $FoundAssetsToAttach,
    $UploadType
)
    $HuduUpload = @()

    # Grab existing attachments.
    ##### Commenting out, no database access
    # $Query = "select uploadable_id, file_data from uploads where uploadable_type = '$UploadType'"
    # $ExistingAttachments = $ExistingAttachments = Get-PSQLData -Query $Query -Connection $Conn
    # $UploadedAttachments = $ExistingAttachments | Select-Object @{n='id'; e={ $_.uploadable_id}},@{n='file';e={($_.file_data|Convertfrom-json).metadata.filename}},@{n='url';e={($_.file_data|Convertfrom-json).id}}
    ##### Replace above lines with new method that doesn't require database. Also commenting lines 149 and 150, 155-158
    
    $Results = foreach ($FoundAsset in $FoundAssetsToAttach) {
        Write-Host "Finding attachments for $($FoundAsset.name) with ITGlueID $($FoundAsset.itgid) to Hudu $($UploadType) $($FoundAsset.HuduID)" -ForegroundColor Cyan
        # Write-Host "Checking existing attachments from database"
        # $CurrentAssetAttachments = $UploadedAttachments | Where-Object {$_.id -eq $FoundAsset.HuduID}
        
        $FilesToUpload = Get-ChildItem -path "$AttachmentsPath\*\$($FoundAsset.ITGID)\*" -Recurse
        foreach ($FoundFile in $FilesToUpload) {
            if ($FoundFile.PSIsContainer -ne $True) {
                <# if ($FoundFile.name -in $CurrentAssetAttachments.file) {
                    Write-Host "Skipping $($FoundFile.name) because its already uploaded as an attachment" -ForegroundColor Yellow
                    continue
                } #>
                Write-Host "Pushing $($FoundFile.name) to Hudu $($UploadType) $($FoundAsset.name) - $($FoundAsset.HuduID)" -ForegroundColor Blue
                try {
                    $HuduUpload = New-HuduUpload -FilePath $FoundFile.fullname -uploadable_id $FoundAsset.HuduID -uploadable_type $UploadType
                    [PSCustomObject]@{
                        FileHref  = "/file/$UploadIndex"
                        Uploadable_ID = $FoundAsset.HuduID
                        Uploadable_Type = $UploadType
                        FilePath  = $FoundFile.fullname
                        status  = "Uploaded Successfully"
                    }
                }
                catch {
                Write-Error ('Insert exception: {0}' -f $_.Exception.Message)
                [PSCustomObject]@{
                    FileHref  = "/file/$UploadIndex"
                    ArticleId = $ArticleId
                    FileData  = $UploadData
                    status  = "FAILED: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    
    $Results |ConvertTo-Json -Compress -Depth 10 |Out-File "$($MigrationLogs)\$($UploadType)-attachments-upload.json"

}

# Used for Creating the CSV Mapping for FA Custom Upload fields
function Build-CSVMapping {
    $Folders = Get-ChildItem -Attributes Directory -Filter *-* -Path $ITGlueExportPath

    $CSVMapping = foreach ($folder in $Folders) {
        Write-Host "We need to map the embedded attachments to the right CSV file. Please enter the name of the csv file for $($folder.name)";
        $FileName = Read-Host "CSV Name";
        
        Write-Host "We need to specify the header where the file path is located for this folder. Please specify the header name for $($folder.name)";
        $HeaderName = Read-Host "Header"; 
        
        [pscustomobject]@{
            foldername=$Folder.name;
            csv_file=$FileName;
            csv_header=$HeaderName
        }
    }
    $CSVMapping | ConvertTo-Json -Depth 50 -Compress |Out-File "$MigrationLogs\AttachmentFields-CSVMap.json"
    return $CSVMapping
}
################ END FUNCTIONS REGION #################

# Check if we have a logs folder. Logs are required to match attachments to entity
if (Test-Path -Path "$MigrationLogs") {
        Write-Host "Migration Logs successfully found" -ForegroundColor Green
    }
else {
    Write-Host "No previous runs found creating log directory. Unable to proceed"
    exit 1
}

## Starting main script
Write-Host "Starting script. Files will be saved into $StagingRoot Press CTRL+C to cancel" -ForegroundColor Yellow
Pause

Write-host "Loading Asset Log"
$ITGlueAssets = Get-Content "$MigrationLogs\Assets.json" | ConvertFrom-json
Write-host "Loading Articles Log"
$ITGlueDocuments = Get-Content "$MigrationLogs\Articles.json" | ConvertFrom-json
Write-host "Loading Configuration Log"
$ITGlueConfigurations = Get-Content "$MigrationLogs\Configurations.json" | ConvertFrom-json
Write-Host "Loading Locations Log"
$ITGlueLocations = Get-Content "$MigrationLogs\Locations.json" | ConvertFrom-json
Write-Host "Loading Websites Log"
$ITGlueWebsites = Get-Content "$MigrationLogs\Websites.json" | ConvertFrom-json
Write-Host "Loading Passwords Log"
$ITGluePasswords = Get-Content "$MigrationLogs\Passwords.json" | ConvertFrom-json

$AttachmentsToUpload = Get-ChildItem $AttachmentsPath -Recurse
$FoundAssetsToAttach = $ITGlueAssets |Where-Object {$_.itgid -in $AttachmentsToUpload.name -and $_.HuduID -eq $null}
$FoundDocumentsToAttach = $ITGlueDocuments |Where-Object {$_.itgid -in $AttachmentsToUpload.name}
$FoundConfigurationsToAttach = $ITGlueConfigurations | Where-Object {$_.itgid -in $AttachmentsToUpload.name}
$FoundLocationsToAttach = $ITGlueLocations | Where-Object {$_.itgid -in $AttachmentsToUpload.name}
$FoundWebsitesToAttach = $ITGlueWebsites | Where-Object {$_.itgid -in $AttachmentsToUpload.name}
$FoundPasswordsToAttach = $ITGluePasswords | Where-Object {$_.itgid -in $AttachmentsToUpload.name}

if ($FoundAssetsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundAssetsToAttach -UploadType "Asset"}
if ($FoundConfigurationsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundConfigurationsToAttach -UploadType "Asset"}
if ($FoundDocumentsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundDocumentsToAttach -UploadType "Article"}
if ($FoundLocationsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundAssetsToAttach -UploadType "Asset"}
if ($FoundWebsitesToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundAssetsToAttach -UploadType "Website"}
if ($FoundPasswordsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundAssetsToAttach -UploadType "AssetPassword"}

if (!($CSVMapping = Get-Content "$MigrationLogs\AttachmentFields-CSVMap.json"|ConvertFrom-Json -Depth 10)) {
    $CSVMapping = Build-CSVMapping
}

if ($CSVMapping) {
    foreach ($n in $CSVMapping) { 
        $CSVPath = Join-Path -Path $ITGLueExportPath -ChildPath $n.csv_file
        $CSV = Import-Csv -Path $CSVPath
        $CSVHeader = $n.csv_header 
    
        $CSVAttachmentsToUpload = $CSV | Where-Object {$_.$CSVHeader}
        foreach ($record in $CSVAttachmentsToUpload) {
            $FileReferences = $record.$CSVHeader.split(',').trim()
            foreach ($fr in $FileReferences) {
                $FileToUpload = Get-Item -path (Join-Path -Path $ITGlueExportPath -ChildPath "$($n.foldername)\$($fr)")
                $HuduAssetID = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty HuduID
                $HuduAssetName = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty Name
                Write-Host "Uploading $($FileToUpload.fullname) to Hudu Asset $($HuduAssetName) - $($HuduAssetID)" -ForegroundColor Blue
                $HuduUpload = New-HuduUpload -Connection $Conn -FilePath $FileToUpload.fullname -ArticleId $HuduAssetID -UploadType 'Asset'
            }
        }
    }
}

# Write-Host "You will need to take $StagingRoot and sync it to the appropriate backend storage"
Write-Host "All attachments have been processed."
Pause
