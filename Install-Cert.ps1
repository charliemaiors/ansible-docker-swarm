#!ps1

$scriptPath = Get-Location

if (Get-Command docker -errorAction SilentlyContinue)
{
	if (!(Test-Path -Path $env:USERPROFILE\.docker))
	{
		New-Item -ItemType directory -Path $env:USERPROFILE\.docker
	}
	Write-Host "Installing certificates"
	$folder = Get-ChildItem -Path $scriptPath | Where-Object { $_.Name -match "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b" } | Select-Object Name
	
	if ([string]::isNullOrEmpty($folder))
	{
		$folder = Get-ChildItem -Path $scriptPath | Where-Object { $_.Name -match "(?=^.{1,254}$)(^(?:(?!\d+\.|-)[a-zA-Z0-9_\-]{1,63}(?<!-)\.)+(?:[a-zA-Z]{2,})$)" } | Select-Object Name
		Move-Item $folder.Name $env:USERPROFILE\.docker
	}
	else
	{
		Move-Item $folder.Name $env:USERPROFILE\.docker
	}
	
	Write-Host "Now please run docker_remote.bat | Invoke-Expression in order to have your local docker client configured and use remote swarm"
	exit 0
}
else 
{
	Write-Host "Unable to find docker command, please install Docker (https://www.docker.com/) and retry"
	exit 1
}