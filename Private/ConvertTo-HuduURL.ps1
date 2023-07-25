# This will be used to remake the ITGlue Links to Hudu, and relies on the articles logs existing.


$EscapedITGURL = [regex]::Escape($ITGURL)

# Gather all the Hudu Migration logs
# This should create $MatchedArticleBase, $MatchedAssetts, $MatchedCompanies, $MatchedConfigurations, $MatchedPasswords etc.
<# 
Disabling this block to merge this file under the main migration.
foreach ($File in (Get-ChildItem  "$ITGlueExportPath\..\MigrationLogs\*.json")) {
    try {
        New-Variable -Name "Matched$($file.name.replace('.json',''))" -Value (Get-Content $File.FullName -raw |ConvertFrom-Json -Depth 100) -ErrorAction Stop
    }
    catch {
        "Variable clobbering is occurring. Please clear the variables"
    }
    
} #>

# Disabling this line, since we'll have article content already.
# $AllArticles = Get-HuduArticles
# Disabling this line as we'll have the article content already
# $ArticlesWithITGlueLinks = $AllArticles | Where-Object {$_.content -like "*$ITGlueURL*"}


# We want to grab all assets, passwords, websites, and companies, filter to fields and notes that have ITGlue URLs in them and prime for replacement.
# Following capture Groups
# 0 = Entire match found
# 1,5 = A/a (not important)
# 2 = ITGlue Company ID (Important for LOCATOR)
# 3 = type of Entity (Important for location)
# 4 = ITGlue Entity ID

$RichRegexPatternToMatchSansAssets = "<(A|a) href=.*$EscapedITGURL/([0-9]{1,10})/(docs|passwords|configurations)/([0-9]{1,10})\S.*</(A|a)>"
$RichRegexPatternToMatchWithAssets = "<(A|a) href=.*$EscapedITGURL/([0-9]{1,10})/(assets)/.*/([0-9]{1,10})\S.*</(A|a)>"
$TextRegexPatternToMatchSansAssets = "$EscapedITGURL/([0-9]{1,10})/(docs|passwords|configurations)/([0-9]{1,10})"
$TextRegexPatternToMatchWithAssets = "$EscapedITGURL/([0-9]{1,10})/(assets)/.*/([0-9]{1,10})"

function Update-StringWithCaptureGroups {
    [cmdletbinding()]
    param (
      [Parameter(Mandatory=$true, Position=0)]
      [string]$inputString,
      [Parameter(Mandatory=$true, Position=1)]
      [string]$pattern,
      [Parameter(Mandatory=$true, Position=2)]
      [string]$type
    )
  
    $regex = [regex]::new($pattern)
    
    $matchesPattern = $regex.Matches($inputString)

    Write-Host "Found $($matchesPattern.count) matches to replace"
  
    foreach ($match in $matchesPattern) {

        # Compare the 3rd Group to identify where to find the new content

        switch ($match.groups[3].value) {

            "articles" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
               $HuduUrl = ($MatchedArticleBase |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
               $HuduName = ($MatchedArticleBase |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
               Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
               
            }

            "passwords" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }

            "configurations" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }

            "assets" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }



        }
    
        if ($HuduUrl) {
            $HuduUrl = $HuduUrl.replace("http://","https://")
            if ($type -eq 'rich') {
            $ReplacementString = @"
            <A HREF="$HuduUrl">$HuduName</A>
"@
            }
            else {
                $ReplacementString = @"
                $HuduUrl
"@
            }
            $inputString = $inputString -replace [string]$match.Value,[string]$ReplacementString
        }

      

    }
  
    return $inputString
  }
  

function ConvertTo-HuduURL {
    param(
        $Content
    )
    $NewContent = Update-StringWithCaptureGroups -inputString $Content -pattern $RegexPatternToMatchSansAssets
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RegexPatternToMatchWithAssets

    return $NewContent

}



<# Disabled block for merging into main conversion module
Write-Warning "Found $($ArticlesWithITGlueLinks.count) Articles with ITGlue Links. Cancel now if you don't want to replace them!"
Pause

$articlesUpdated = @()
foreach ($articleFound in $ArticlesWithITGlueLinks) {
    $NewContent = Update-StringWithCaptureGroups -inputString $articleFound.content -pattern $RegexPatternToMatchSansAssets
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RegexPatternToMatchWithAssets
    Write-Host "Updating Article $($articleFound.name) with replaced Content" -ForegroundColor 'Green'
    $articlesUpdated += @{"original_article" = $articleFound; "updated_article" = Set-HuduArticle -Name $articleFound.name -id $articleFound.id -Content $NewContent}

}

$articlesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedArticlesURL.json"
#>