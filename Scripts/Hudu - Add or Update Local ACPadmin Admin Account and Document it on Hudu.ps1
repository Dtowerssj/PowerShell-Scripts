<#
.SYNOPSIS
    This PowerShell script is designed to manage administrator accounts by adding new accounts or updating existing ones. 
    Additionally, it documents these changes in Hudu for proper tracking and auditing.

.DESCRIPTION
    The script performs the following tasks:

    1. Takes the company nickname (AKA) as an input parameter.
    2. Checks whether the specified administrator account already exists.
    3. Generates a random Password.
    3. If the account exists, updates the account password.
    4. If the account doesn't exist, creates a new administrator account.
    5. Documents the changes in Hudu by adding or updating the password.

.PARAMETER CompanyAKA
    The company nickname provides a quick, easy way to organize and manage companies in Hudu.

.PARAMETER huduApiKey
    Hudu API key for documentation

.EXAMPLE
    .\Hudu - Add or Update Local ACPadmin Admin Account and Document it on Hudu.ps1 -CompanyAKA "ACP"


.NOTES
    File Name      : Hudu - Add or Update Local ACPadmin Admin Account and Document it on Hudu.ps1
    Prerequisites  : 
        - Hudu API key for documentation
        - Proper authentication and authorization for admin account management

#>
param (
    [string]
    $CompanyAKA
)

# Variables
$Username = "ACPadmin" # Local user username
$HuduPwName='gs-' + $env:COMPUTERNAME # password name that will be created in Hudu
$Password = $null # Password will be generated later
$group = "Administrators"
$KeyPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
$adsi = [ADSI]"WinNT://$env:COMPUTERNAME"

# Syncro variables
#$CompanyAka = "acp"
#$huduApiKey = ""

if ($CompanyAka -eq $null) {
Write-Host "Company AKA was not provided"
} else {
$CompanyAka = $CompanyAka.ToLower()
Write-Host "CompanyAka: $CompanyAka"
}

# Hash table, with key-values of companies and their id's, will be filled later
$CompaniesIds = @{}

# Parameters for HTTP Requests
$headers = @{
        "Content-Type" = 'application/json'
        "x-api-key" = $huduApiKey
        }

# Getting all the customers in Hudu and filling the Hash Table
$URI = 'https://huduacp.atlantacomputerpros.com/api/v1/companies?id_number=1'

$resCompanies = Invoke-RestMethod -Uri $URI -Method Get -Headers $headers

foreach ($i in $resCompanies.companies){ 
    $CompaniesIds[$i.nickname] = $i.id
}

# Functions that we are going to need 
function Get-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length
    )
    #$charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{]+-[*=@:)}$^%;(_!&amp;#?>/|.'.ToCharArray()
    $charSet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ123456789{}[]()+-*=@:;$%_!&#?/.'.ToCharArray()
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)
 
    $rng.GetBytes($bytes)
 
    $result = New-Object char[]($length)
 
    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i]%$charSet.Length]
    }
 
    return (-join $result)
}

$Password = Get-RandomPassword 14 # Generating the password
Write-Host "New Password will be: "$Password `n`

# HTTP Hudu CRUD functions
function Get-PasswordInHudu {
    param (
        [Parameter(Mandatory)]
        [String] $name
    )

    try {
        $Uri = 'https://huduacp.atlantacomputerpros.com/api/v1/asset_passwords?name='+$name

        $res = Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers 

    } catch {
        Write-Host "Password could not be found in Hudu. An error occurred:"
        Write-Host $_
        Write-Host "Proceeding to create password in Hudu"
    }
 
    return ($res)
}

function Create-PasswordInHudu {
    param (
        [String] $name = $HuduPwName,
        [String] $company_id = $CompaniesIds.$CompanyAka,
        [String] $username = $Username,
        [String] $password = $Password
    )

    # POST request to create password in Hudu
    try {
        $uri = 'https://huduacp.atlantacomputerpros.com/api/v1/asset_passwords'

        $body = @{
        asset_password=@{
        company_id=$CompaniesIds.$CompanyAka
        name=$name
        username=$username
        password=$Password
        password_folder_id=11
        }
        } | ConvertTo-Json

        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        Write-Host "Password update successful in Hudu"
        
    } catch {
        Write-Host "An error occurred while creating the password in Hudu:"
        Write-Host $_
    }
 
    return ($result)
}

function Update-PasswordInHudu {
    param (
        [Parameter(Mandatory)]
        [String] $id,
        [String] $name = $HuduPwName,
        [String] $company_id = $CompaniesIds.$CompanyAka,
        [String] $username = $Username,
        [String] $password = $Password
    )

    # PUT request to create password in Hudu
    try {
            $Uri = 'https://huduacp.atlantacomputerpros.com/api/v1/asset_passwords/'+$id
            
            $Body = @{
            asset_password=@{
            company_id=$company_id
            name=$name
            username=$username
            password=$password
            password_folder_id=11
            }
        } | ConvertTo-Json 

        Invoke-RestMethod -Uri $Uri -Method Put -Headers $headers -Body $body
        
        Write-Host "Password update successful in Hudu"
        } catch {
        Write-Host "An error occurred while updating the password in Hudu:"
        Write-Host $_
        }
 
    return ($result)
}


$existing = $adsi.Children | where {$_.SchemaClassName -eq 'user' -and $_.Name -eq $Username }

if ($existing -eq $null) {

    Write-Host "Creating new local user $Username."
    & NET USER $Username $Password /add /y /expires:never
    
    Write-Host "Adding local user $Username to $group."
    & NET LOCALGROUP $group $Username /add

    # POST request to create password in Hudu
    Create-PasswordInHudu
    
}
else {
    Write-Host "Setting password for existing local user $Username " `n`
    $existing.SetPassword($Password)

    # Trying to find gs- password in Hudu & obtaining password info
    $PasswordExists = $null
    Write-Host "Trying to find gs- password in Hudu" `n`
    $res = Get-PasswordInHudu -name $HuduPwName
    $res

    if ($res.asset_passwords.id -is [int]) {
          $PasswordExists = $true
          Write-Host "Password exists! proceeding to update it in Hudu"  `n`
        } else {
          Write-Host "Password could not be found in Hudu, proceeding to create it" `n`
        }

    if($PasswordExists -eq $true) {

        # PUT Request to update password in Hudu
        if ($CompanyAka -eq $null) {
            Update-PasswordInHudu -id $res.asset_passwords.id -company_id $res.asset_passwords.company_id
        } else {
            Update-PasswordInHudu -id $res.asset_passwords.id -company_id $CompaniesIds.$CompanyAka
        }
        
        
    } else {
        
        # POST Request to create password in Hudu
        Create-PasswordInHudu
    }

    
}

Write-Host "Ensuring password for $Username never expires."
& 'WMIC USERACCOUNT WHERE "Name='$Username'" AND "LocalAccount=True" SET PasswordExpires=FALSE'

Clear-Variable -Name "Password"