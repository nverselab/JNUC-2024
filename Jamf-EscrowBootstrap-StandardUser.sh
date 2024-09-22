#!/bin/bash

##################################################################################################################
# This script will elevate the current user to administrator temporarily to escrow bootstrap token to Jamf Pro.  # 
# User will need to provide credentials as SecureToken enabled to complete                                       #
# User will be removed from admin after each attempt                                                             #
##################################################################################################################

#######################
# Check Pre-requisits #
#######################

# Exit successfully if Bootstrap token is already escrowed
verify=$(profiles status -type bootstraptoken | awk '/escrowed/ {print $7}')
if [[ $verify == "YES" ]]; then
    echo "Bootstrap already escrowed. Exiting successfully"
    exit 0
fi

# Get the logged in user's name
LoggedinUser=$(/usr/bin/stat -f%Su /dev/console)

# Check to see if a user is logged in and exit unsuccessfully if they are not

if [ -z "$LoggedinUser" -o "$LoggedinUser" = "loginwindow" ]; then
    echo "no user logged in, cannot proceed"
    exit 1
fi

## Check to see if logged in user has a SecureToken and exit unsuccessfully if they do not
secureToken=$(sysadminctl -secureTokenStatus $LoggedinUser 2>&1 | awk '{print$7}')
if [[ $secureToken != "ENABLED" ]]; then
    echo "$LoggedinUser is not SecureToken enabled, cannot proceed"
    exit 1
fi

######################################
# Begin Elevation and Escrow Process #
######################################

## Ask User for Credientials

# Prompt for Password until entered
userPass=""
until [[ $userPass != "" ]]
do
userPass=$(/usr/bin/osascript<<END
application "System Events"
activate
set the answer to text returned of (display dialog "IT needs to set some things up for you.  Please Enter your Password:" default answer "" with hidden answer buttons {"Continue"} default button 1)
END
)
done
    
# Loop until successful
result=""

until [[ $result == "success" ]]
do
    
## Temorarily Elevate User if they aren't already an Admin
    
if groups $LoggedinUser | grep -q -w admin; then 
    admin="yes"
else 
    /usr/sbin/dseditgroup -o edit -a $LoggedinUser -t user admin
fi
    
/usr/sbin/dseditgroup -o edit -a $LoggedinUser -t user admin
    
## Create and Escrow BootStrap Token
    
    #Create an EXPECT file to deal with interactive portion of bootstrap tokens
    /bin/cat << EOP > /Library/Application\ Support/JAMF/tmp/escrowToken
#! /usr/bin/expect
set adminName "[lindex \$argv 0]"
set adminPass "[lindex \$argv 1]"
#This will create and escrow the bootstraptoken on the Jamf Pro Server
spawn /usr/bin/profiles install -type bootstraptoken
expect "Enter the admin user name:" 
send "\$adminName\r"
expect "Enter the password for user '\$adminName':" 
send "\$adminPass\r"
expect eof
exit 0
EOP
    
    # Give script execute permissions
    chmod +x /Library/Application\ Support/JAMF/tmp/escrowToken
    
    # Pass arguments to EXPECT script
    /Library/Application\ Support/JAMF/tmp/escrowToken "$LoggedinUser" "$userPass"
    
    # Remove script after completion
    rm -rf /Library/Application\ Support/JAMF/tmp/escrowToken
    
## Remove User from Admin if they were not already an admin

if [[ $admin != "yes" ]]; then
dseditgroup -o edit -d $LoggedinUser -t user admin
fi

## Check that token as been escrowed
    
verify=$(profiles status -type bootstraptoken | awk '/escrowed/ {print $7}')
if [[ $verify == "YES" ]]; then
    result="success"
else
    # Prompt for Password AGAIN until entered
    userPass=""
    until [[ $userPass != "" ]]
    do
        userPass=$(/usr/bin/osascript<<END
application "System Events"
activate
set the answer to text returned of (display dialog "That did not work.  Please try entering your Password again:" default answer "" with hidden answer buttons {"Continue"} default button 1)
END
)
            done
fi
    
done

exit 0

