
<# For detailed information about the GitHub release related APIs, read https://developer.github.com/v3/repos/releases/#create-a-release #>
<# TODO: Maybe incorporate to https://github.com/PowerShell/PowerShellForGitHub in future #>
using NameSpace "System.Management.Automation"
using NameSpace "System.Collections.ObjectModel"

## The authentication header
$Script:Auth = $null

function Get-CommonParameters
{
    $ParamDict = [RuntimeDefinedParameterDictionary]::new()

    ## Add the '-User' parameter
    ## [Parameter(Mandatory)]
    ## [string]$User
    $UserAtts = [Collection[Attribute]]::new()
    $UserAtts.Add([Parameter]@{Mandatory = $true}) > $null
    $ParamDict.Add("User", [RuntimeDefinedParameter]::new("User", [string], $UserAtts)) > $null

    ## Add the '-Repository' parameter
    ## [Parameter(Mandatory)]
    ## [string]$Repository
    $RepositoryAtts = [Collection[Attribute]]::new()
    $RepositoryAtts.Add([Parameter]@{Mandatory = $true}) > $null
    $ParamDict.Add("Repository", [RuntimeDefinedParameter]::new("Repository", [string], $RepositoryAtts)) > $null

    ## Add the '-Token' parameter
    ## [Parameter(Mandatory, ParameterSetName="UseSpecifiedToken")]
    ## [string]$Token
    $TokenAtts = [Collection[Attribute]]::new()
    $TokenAtts.Add([Parameter]@{Mandatory = $true; ParameterSetName="UseSpecifiedToken"}) > $null
    $ParamDict.Add("Token", [RuntimeDefinedParameter]::new("Token", [string], $TokenAtts)) > $null

    return $ParamDict
}

function Get-CommonParamValues([PSCmdlet]$Cmdlet)
{
    $AuthHeader = $Script:Auth
    if ($Cmdlet.ParameterSetName -eq "UseSpecifiedToken") {
        $Token = $Cmdlet.MyInvocation.BoundParameters["Token"]
        $AuthHeader = @{"Authorization"="token $Token"}
    }
    if (-not $AuthHeader) {
        throw "Authentication token is not specified."
    }

    $User = $Cmdlet.MyInvocation.BoundParameters["User"]
    $Repository = $Cmdlet.MyInvocation.BoundParameters["Repository"]
    return $User, $Repository, $AuthHeader
}

##############################
#.SYNOPSIS
#Upload an asset to a release
#
#.PARAMETER ReleaseId
#The release ID
#
#.PARAMETER AssetPath
#The asset path
#
#.PARAMETER User
#The user that owns the target repository
#
#.PARAMETER Repository
#The target repository
#
#.PARAMETER Token
#The authentication token to use for the operation.
#The token needs to have 'public_repo' scope permission to upload release assets.
#
#.OUTPUTS
#Return the HTTP result of the upload operation
##############################
function Push-ReleaseAsset
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory)]
        [int]$ReleaseId,

        [Parameter(Mandatory)]
        [string]$AssetPath,

        [switch]$PassThru
    )

    DynamicParam {
        Get-CommonParameters
    }

    Begin {
        $User, $Repository, $AuthHeader = Get-CommonParamValues -Cmdlet $PSCmdlet
    }

    End {
        $type_7z  = "application/octet-stream"
        $type_exe = "application/x-msdownload"

        $AssetName = Split-Path $AssetPath -Leaf

        if ([System.IO.Path]::GetExtension($AssetName) -eq ".7z") {
            $content_type = $type_7z
        } else {
            $content_type = $type_exe
        }

        $Header = $AuthHeader + @{"Content-Type"=$content_type; "name"=$AssetName;}
        $Uri = "https://uploads.github.com/repos/$User/$Repository/releases/$ReleaseId/assets?name=$AssetName"

        $Body = [System.IO.File]::ReadAllBytes($AssetPath)
        $Result = Invoke-WebRequest -Headers $Header -Method Post -Body $Body -Uri $Uri -RetryIntervalSec 5 -MaximumRetryCount 10

        if ($Result.StatusCode -eq 201) {
            $Content = ConvertFrom-Json $Result.Content
            Write-Host "'$AssetName' -- Upload succeeded" -ForegroundColor Green
            Write-Verbose -Message "   Download URL: $($Content.browser_download_url)"
        } else {
            Write-Host "'$AssetName' -- Upload failed with StatusCode $($Result.StatusCode)" -ForegroundColor Red
        }

        ## Pass through the HTTP result if '-PassThru' is specified
        if ($PassThru) { return $Result }
    }
}

##############################
#.SYNOPSIS
#Find an asset from a release
#
#.PARAMETER ReleaseId
#The release ID
#
#.PARAMETER AssetName
#The asset to find
#
#.PARAMETER User
#The user that owns the target repository
#
#.PARAMETER Repository
#The target repository
#
#.PARAMETER Token
#The authentication token to use for the operation.
#The token needs to have at least 'repo:status' scope permission to read releases.
#
#.OUTPUTS
#Return the asset ID if it's found; or return nothing
##############################
function Find-ReleaseAsset
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory)]
        [int]$ReleaseId,

        [Parameter(Mandatory)]
        [string]$AssetName
    )

    DynamicParam { Get-CommonParameters }

    Begin {
        $User, $Repository, $AuthHeader = Get-CommonParamValues -Cmdlet $PSCmdlet
    }

    End {
        $Result = Invoke-WebRequest -Headers $AuthHeader -Uri "https://api.github.com/repos/$User/$Repository/releases/$ReleaseId/assets" -RetryIntervalSec 5 -MaximumRetryCount 10
        $Assets = ConvertFrom-Json $Result.Content
        foreach ($Item in $Assets) {
            if ($Item.name -eq $AssetName) {
                Write-Verbose "Asset $AssetName was already uploaded, id: $($Item.id)" -Verbose
                Write-Verbose ("  Asset is ready for download: " + $Item.browser_download_url) -Verbose
                return $Item.id
            }
        }
    }
}

##############################
#.SYNOPSIS
#Find a release record based on the specified tag
#
#.PARAMETER Tag
#The tag associated with the release
#
#.PARAMETER User
#The user that owns the target repository
#
#.PARAMETER Repository
#The target repository
#
#.PARAMETER Token
#The authentication token to use for the operation.
#The token needs to have at least 'repo:status' scope permission to read releases.
#
#.OUTPUTS
#Return the release ID if it's found; or return nothing
##############################
function Find-Release
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory)]
        [string]$Tag
    )

    DynamicParam { Get-CommonParameters }

    Begin {
        $User, $Repository, $AuthHeader = Get-CommonParamValues -Cmdlet $PSCmdlet
    }

    End {
        $Result = Invoke-WebRequest -Headers $AuthHeader -Uri "https://api.github.com/repos/$User/$Repository/releases" -RetryIntervalSec 5 -MaximumRetryCount 10
        $Releases = ConvertFrom-Json $Result.Content
        foreach ($Item in $Releases) {
            if ($Item.tag_name -eq $Tag) {
                Write-Verbose ("Release $Tag is found, upload_url=" + $Item.upload_url) -Verbose
                return $Item.id
            }
        }
    }
}

##############################
#.SYNOPSIS
#Create a release record
#
#.PARAMETER Tag
#The tag associated with the release
#
#.PARAMETER Name
#The name of the release
#
#.PARAMETER Description
#The description of the release
#
#.PARAMETER User
#The user that owns the target repository
#
#.PARAMETER Repository
#The target repository
#
#.PARAMETER Token
#The authentication token to use for the operation.
#The token needs to have 'public_repo' scope permission to create new release draft.
#
#.OUTPUTS
#Return the release ID if it's created successfully; or return nothing
##############################
function New-Release
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description
    )

    DynamicParam { Get-CommonParameters }

    Begin {
        $User, $Repository, $AuthHeader = Get-CommonParamValues -Cmdlet $PSCmdlet
    }

    End {
        $Body = @{
            tag_name = $Tag
            name = $Name
            body = $Description
            draft = $true
            prerelease = $false
        }

        $BodyInJson = ConvertTo-Json $Body
        $Result = Invoke-WebRequest -Headers $AuthHeader -Method Post -Body $BodyInJson -Uri "https://api.github.com/repos/$User/$Repository/releases" -RetryIntervalSec 5 -MaximumRetryCount 10
        $Release = ConvertFrom-Json $Result.Content
        return $Release.id
    }
}

##############################
#.SYNOPSIS
#Publish a release draft
#
#.PARAMETER Tag
#The tag associated with the release
#
#.PARAMETER Name
#The name of the release
#
#.PARAMETER Description
#The description of the release
#
#.PARAMETER PackageFolder
#The folder that contains package files
#
#.PARAMETER User
#The user that owns the target repository
#
#.PARAMETER Repository
#The target repository
#
#.PARAMETER Token
#The authentication token to use for the operation.
#The token needs to have 'public_repo' scope permission to publish release draft.
#
#.EXAMPLE
# Publish-ReleaseDraft -Tag v6.0.0-rc.2 -Name "v6.0.0-rc.2 Release of PowerShell Core" -Description $description -PackageFolder C:\release\All -User PowerShell -Repository PowerShell -Token <token>
#
#.OUTPUTS
#Return the release ID if it's created successfully; or return nothing
##############################
function Publish-ReleaseDraft
{
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [string]$PackageFolder
    )

    DynamicParam { Get-CommonParameters }

    Begin {
        $User, $Repository, $AuthHeader = Get-CommonParamValues -Cmdlet $PSCmdlet
        $Script:Auth = $AuthHeader
        $CommonParams = @{User=$User; Repository=$Repository}
    }

    End {
        $ReleaseId = Find-Release -Tag $Tag @CommonParams
        if ($ReleaseId) {
            Write-Host "Release for $Tag already created, Release-Id: $ReleaseId" -ForegroundColor Green
        } else {
            $StringBuilder = [System.Text.StringBuilder]::new($Description, $Description.Length + 2kb)
            $StringBuilder.AppendLine().AppendLine() > $null
            $StringBuilder.AppendLine("### SHA256 Hashes of the release artifacts").AppendLine() > $null
            Get-ChildItem -Path $PackageFolder -File | ForEach-Object {
                $PackageName = $_.Name
                $SHA256 = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                $StringBuilder.AppendLine("- $PackageName").AppendLine("  - $SHA256") > $null
            }

            $Description = $StringBuilder.ToString()
            $ReleaseId = New-Release -Tag $Tag -Name $Name -Description $Description @CommonParams
            Write-Host "Release for $Tag created, Release-Id: $ReleaseId" -ForegroundColor Green
        }

        Get-ChildItem -Path $PackageFolder -File | ForEach-Object {
            $PackageName = $_.Name
            $PackageId = Find-ReleaseAsset -ReleaseId $ReleaseId -AssetName $PackageName @CommonParams
            if (-not $PackageId) {
                Push-ReleaseAsset -ReleaseId $ReleaseId -AssetPath $_.FullName @CommonParams
            }
        }
    }
}

Export-ModuleMember -Function Publish-ReleaseDraft, New-Release, Find-Release, Find-ReleaseAsset, Push-ReleaseAsset
