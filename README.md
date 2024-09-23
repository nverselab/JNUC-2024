# JNUC-2024
Resources related to my Lift Your Admin Up By The Bootstrap presentation at the JNUC Spotlight in 2024.

## The problems to be solved

&nbsp;

- Rotating a LAPS enabled PreStage Administrator account results in the cryptographic (FileVault) password falling out of sync with the login password.
  - The SetAutoAdminPassword Command is not able to rotate Secure Token passwords.  

- A PreStage Administrator account with the ability to unlock a FileVault encrypted volume is not desired.
  - It shows up on the FileVault screen for the world to see.  

- Deploying Software Updates with MDM Commands doesn't work.
  - The Bootstrap Token is not escrowed to Jamf Pro.  

- Multiple users access the workstation, but only one user is allowed to unlock the FileVault encrypted boot volume without manual intervention.
  - Only the first logged in user gets a Secure Token automatically unless the Bootstrap token is escrowed to the MDM.  

- Bootstrap Tokens are not being escrowed automatically to Jamf Pro.
  - Either because of a broken provisioning sequence or User-Initiated Enrollment

&nbsp;

## Things to understand

&nbsp;

### Secure Token  

#### What is a Secure Token?  

- A wrapped version of a "key encryption key" (KEK) protected by a user's password. In other words, it is a key used to protect other keys. An analogy would be the transponders embedded in the head of a car key that -- alongside the bare metal key -- authorizes the vehicle to start when both are present at the time of ignition.  

### Where is a Secure Token Used?  

- During authentication for enabling FileVault, unlocking a FileVault encrypted volume, managing Software Updates, or initiating the Erase All Contents and Settings Command.  

### When do I get a Secure Token?  

- When a user and password is created during Setup Assistant (with or without ADE) or when the first user logs in (if Account Creation is skipped during ADE) unless disabled with a command before the password is created (such as with a script).
- sudo dscl . -append /Users/&lt;user name&gt; AuthenticationAuthority ";DisabledTags;SecureToken"  

- If a user doesn’t have a SecureToken, MacOS will request the bootstrap token from the MDM for to issue a Secure Token to any new user logging in through the login window or Jamf Connect  

### What's the catch?  

- Secure Token enabled accounts require previous credentials to be provided for password changes. This is overridden by the SetAutoAdminPassword MDM Command for PreStage Administrator accounts, but does not change the cryptographic password used for FileVault when rotated by LAPS.  

- The only service Administrator account that can be rotated by LAPS without breaking the cryptographic password for FileVault is the Jamf Management account because it is changed through the Jamf Framework with known credentials.  

## Bootstrap Token  

### What is a Bootstrap Token?  

- A special token that enables an MDM to perform special actions. If we maintain the car analogy, the Bootstrap Token would be like having a special key you would provide to your local mechanic for performing specific tasks without letting them actually turn it on.  

### When is a Bootstrap Token used?  

- When an MDM provisions new Secure Tokens to additional users, installs Kernel Extensions without modifying Startup Security Settings, or installing updates via MDM Command.  

### When do I generate a Bootstrap Token?  

- When a Secure Token enabled user logs in for the first time.  

### When is the Bootstrap Token escrowed to Jamf Pro?  

- During Automated Device Enrollment when the first user is created during Setup Assistant (assuming Prevent Activation Lock is enabled)  

- When a Secure Token enabled user logs in on a PreStage enrolled workstation.  

- When the '/usr/bin/profiles install -type bootstraptoken' command is run as a Secure Token enabled Administrator.

&nbsp;

## Volume Owner  

### What is a Volume Owner?  

- A user permission claimed by the first user to configure the Mac as their own and allows them to make specific changes. In the context of a car, this would be similar to having your name on the title, enabling you to make specific decisions about the status of the car and who can do certain things to it.  

### When is Volume Ownership used?  

- When changing Startup Security Policies, installing Software Updates, and initiating an Erase All Contents and Settings command.  

### When do I get Volume Owner permissions?  

- The first user granted a Secure Token becomes the first Volume Owner. Likewise, the Bootstrap Token also receives Volume Owner permissions to be able to complete the tasks it is used for. Volume Ownership goes hand-in hand with Secure Token provisioning and is not required to be managed outside of that process.  

## Jamf Management Account  

- Creates a managed Administrator on both PreStage and User-Initiated Enrollment workstations when enabled.
- Required for workstation to be considered "Managed" in Jamf Pro.
- Automatically has "DisabledTags;SecureToken" applied and will not receive a Secure Token if no other user has one at the time of creation. However, logging in with this account as the first user (or subsiquent user after Bootstrap escrow) will result in it getting a Secure Token.
- This will not affect LAPS as the password rotation occurs through the Jamf Framework (Binary) with previous credentials and will rotate the cryptographic (FileVault) password.  

## Jamf PreStage Administrator  

- Requires Jamf Management Account to be enabled.
- Required when Account Creation during Setup Assistant needs to be skipped.
- Creates a managed Administrator on PreStage enrollments only using the SetAutoAdminPassword MDM Command.
- Also has the "DisabledTags;SecureToken" applied, but will receive a Secure Token if logged in as the first user (or subsiquent user after Bootstrap escrow).
- This WILL affect LAPS as the password rotation and break the cryptographic password sync.
- Enabling PreStage Administrator LAPS requires the account be created with a PreStage profile. Deleting the account and/or creating a new one using any other method will not function with LAPS.

## Enrollment Workflows  

### Zero/Limited Touch WITHOUT PreStage Admin

&nbsp;

1. Setup Assistant creates the first user as Administrator.
2. The created account gets a Secure Token and Volume Owner.
    1. Support staff can still elevate later using the Jamf Management Account with LAPS if enabled and absolutely necessary. Jamf Connect with Administrator Roles is preferred.
3. The Bootstrap Token is escrowed to Jamf Pro automatically and subsequent users will receive a Secure Token at first login.
4. (if touch required) create additional users or ensure Domain Binding or Jamf Connect is installed and configured.
5. FileVault is enabled with a Configuration Profile at login or logout (deferred).
6. The Personal Recovery Key is escrowed to Jamf Pro in case of emergency password reset.
7. (if touch required) clean-up of the original Setup Assistant created Administrator after another user with a Secure Token is created.

&nbsp;

### Zero Touch WITH PreStage Admin

&nbsp;

1. PreStage Enrollment with a PreStage Admin account now has the option to set the Setup Assistant created user as a Standard user or skip account creation entirely.
2. The first user to log in is the intended user of the device (created via Setup Assistant, Domain Bound Mobile Account, or Jamf Connect when account creation is skipped) and provisioned a Secure Token and Volume Owner.
3. The Bootstrap Token is escrowed to Jamf Pro automatically and subsequent users will receive a Secure Token at first login.
4. FileVault is enabled either with Jamf Connect or with a Configuration Profile at login or logout (deferred).
    1. Jamf Connect offers an option to enable FileVault automatically without prompting the user through a deferred configuration profile. However, this uses the depreciated fdesetup command and will not properly escrow the PRK, requiring an additional validation and rotation workflow through Policy.
5. The Personal Recovery Key is escrowed to Jamf Pro in case of emergency password reset.  

### Touch Required WITH PreStage Admin

&nbsp;

1. The ADE registered workstation enrolls through PreStage WITH a PreStage Administrator account and Account Creation in Setup Assistant is skipped.
2. The first user to log in is the PreStage Administrator to complete any necessary manual steps before deployment and is provisioned a Secure Token and Volume Owner.
    1. Results in a service account with ability to unlock the disk, but LAPS breaks cryptographic password sync (due to the SetAutoAdminPassword Command)
3. The Bootstrap Token is escrowed to Jamf Pro Automatically, but the Setup Technician must verify (and remediate if necessary) that the Bootstrap Token is escrowed to Jamf Pro before creating additional user accounts or handing the device off for Domain or Jamf Connect Authenticated users to receive a Secure Token at next login.
4. The next user account(s) are created manually or via Policy, Domain Authenticated Mobile Account, or Jamf Connect.
5. FileVault is enabled either with Jamf Connect or with a Configuration Profile at login or logout (deferred).
    1. Jamf Connect offers an option to enable FileVault automatically without prompting the user through a deferred configuration profile. However, this uses the depreciated fdesetup command and will not properly escrow the PRK requiring an additional validation and rotation workflow.
6. The Personal Recovery Key is escrowed to Jamf Pro in case of emergency password reset.  

### Manual Enrollment (BYOD-Style)

&nbsp;

1. Setup Assistant creates the first user as Administrator.
2. The created account gets a Secure Token and Volume Owner.
3. The user or Setup Technician manually enrolls the workstation into Jamf Pro using User Approved Enrollment.
4. If enabled, the Jamf Management Account is created with LAPS automatically.
5. The Bootstrap Token is NOT escrowed to Jamf Pro automatically and requires a terminal or policy driven script to be run.
    1. If the logged in user is a Standard user at the time of Policy/Script run, they will need to be temporarily elevated to Administrator to complete the Bootstrap escrow.
6. FileVault is enabled either with Jamf Connect or with a Configuration Profile at login or logout (deferred).
    1. If FileVault was already enabled or if Jamf Connect enabled FileVault at login, the PRK is not escrowed properly requiring an additional validation and rotation workflow.
7. The Personal Recovery Key is escrowed to Jamf Pro in case of emergency password reset.

&nbsp;

# Remediations

&nbsp;

## Wait for Bootstrap Token to escrow before enabling FileVault  

### Smart Group

- Computers with Escrowed Bootstrap Token
  - Bootstrap Token Escrowed - is - Yes  

### Configuration Profile

- Enable and Escrow FileVault with PRK

&nbsp;

## Force Bootstrap Token generation and escrow  

### Smart Group

- Computers without Escrowed Bootstrap Token
  - Bootstrap Token Allowed - is - Yes
  - Bootstrap Token Escrowed - is - No  

### Policy

- Script
  - [JNUC-2024/Jamf-EscrowBootstrap-StandardUser.sh at main · nverselab/JNUC-2024 (github.com)](https://github.com/nverselab/JNUC-2024/blob/main/Jamf-EscrowBootstrap-StandardUser.sh)
- Maintenance
  - Update Inventory  

## Validate and Reissue Personal Recovery Key when Invalid  

### Smart Group

- Computers with Invalid Personal Recovery Key
  - Bootstrap Token Escrowed - is - Yes
  - ( FileVault 2 Status - is - All Partitions Encrypted - or - FileVault 2 Status - is - Boot Partitions Encrypted )
  - Filevault Individual Key Validation - is - Invalid  

### Policy

- Script
  - [FileVault2_Scripts/reissueKey.sh at master · jamf/FileVault2_Scripts (github.com)](https://github.com/jamf/FileVault2_Scripts/blob/master/reissueKey.sh)
- Maintenance
  - Update Inventory

&nbsp;

## Clean up Setup Assistant Administrator account after another Secure Token enabled Account is detected  

### Extension Attribute

- Secure Token Users
  - [JNUC-2024/Jamf-ExtensionAttribute-SecureToken_Users.sh at main · nverselab/JNUC-2024 (github.com)](https://github.com/nverselab/JNUC-2024/blob/main/Jamf-ExtensionAttribute-SecureToken_Users.sh)  

### Smart Group

- Computers with Temp Setup Administrator
  - Bootstrap Token Escrowed - is - Yes
  - EA: Secure Token Users - is not - setup_admin_username
    - Extension Attribute collects all Secure Token users as a single string, this line ensures setup_admin_username is not the only one.
  - EA: Secure Token Users - like - setup_admin_username  

### Policy

- Local Accounts
  - Disable User for FileVault 2: setup_admin_username
  - Delete Account: setup_admin_username
- Maintenance
  - Update Inventory

&nbsp;

# Enrollment Workflows

| **\* indicates optional** | **LAPS Admins** | **Account  <br>Creation Types** | **First  <br>SecureToken User** | **FV  <br>Sync** | **Bootstrap  <br>Escrow** | **PRK Escrow** | **Remediations** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Zero/Limited Touch Without PreStage Admin | jamfManage | Setup Assistant (Admin) | Assigned/Temp User (Admin) | Yes | Automatic | Profile (Automatic) | FV Wait for Bootstrap\*  <br>Setup Admin Cleanup\* |
| Zero Touch With PreStage Admin | jamfManage  <br>jamfPreStage | Setup Assistant (Admin/Standard)  <br>Directory Mobile (Admin/Standard)<br><br>Jamf Connect (Admin/Standard) | Assigned User<br><br>Shared Lab Account | Yes | Automatic | Profile (Automatic)<br><br>&nbsp; | FV Wait for Bootstrap\* |
| Touch Required With PreStage Admin | jamfManage  <br>jamfPreStage | Directory Mobile (Admin/Standard)<br><br>Jamf Connect (Admin/Standard) | jamfManage<br><br>jamfPrestage | Yes<br><br>No | Automatic | Profile (Automatic) | FV Wait for Bootstrap\* |
| User-Initiated Enrollment (BYOD-Style) | jamfManage | Setup Assistant (Admin) | Assigned/Temp User (Admin) | yes | Policy Script | Profile (Automatic)<br><br>Policy Script (if enabled) | Bootstrap Escrow Script<br><br>FV Wait for Bootstrap<br><br>PRK Invalid - Reissue Script<br><br>Setup Admin Cleanup\* |
