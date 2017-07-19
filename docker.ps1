Install-PackageProvider -Name "NuGet" -MinimumVersion "2.8.5.201" -Force
Install-Module -Name "DockerMsftProvider" -Repository "PSGallery" -Force
Find-Package "Docker" –ProviderName "DockerMsftProvider"  | Install-Package -Force
