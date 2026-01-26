# cwm-container-testing

I'll add stuff here later.

## Unit Testing

- Import ConnectWiseManageAPI from PSGallery
  ```PowerShell
  Install-Module ConnectWiseManageAPI
  ```
- Import ../shared/modules/CWMShared.psm1
- Authenticate to CWM REST API using
  ```PowerShell
  Connect-CWMAPIUnitTest
  ```
- Run portion of the app script which performs the primary job (each app's initialization .ps1 script is configured to run in the container with the correct environment configuration, but each job script and functions called therein are designed to run outside of this environment with the above requirements met)