#!/usr/bin/perl -w

###############################################################################
#
# AndSync - Synchronize, Backup and Restore your Android device
#
# AndSync Copyright (C) 2012, Winny Mathew Kurian (WiZarD)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################
# ABOUT_END
#
# Prerequisites
#  OS           - Any OS
#  Android SDK  - ADB shell
#  Perl         - Class::Struct File::Path File::Basename Archive::Zip
#
# Revisions
###############################################################################
#   Date           Version    Author   Comments
###############################################################################
#   28.08.2012     1.0        WiZarD   Initial version
#   13.09.2012     1.1        WiZarD   New features and bug fixes
###############################################################################

use strict;

use Class::Struct;
use File::Path;
use File::Basename;
use Archive::Zip;

# 'Package' structure which holds APK details parsed from ADB report
struct Package => {
    name => '$',
    path => '$',
    version_code => '$',
    version_name => '$',
    data_path => '$',
};

struct Device => {
    serial => '$',
    manufacturer => '$',
    product_model => '$',
    android => '$',
    rooted => '$',
};

struct Settings => {
    BackupSystemApps => '$',
    BackupData => '$',
    RestoreSystemApps => '$',
    RestoreData => '$',
    RemoveData => '$',
    SyncMissing => '$',
    DeleteSyncData => '$',
    DeleteCompleted => '$',
    InstallSD => '$',
    ConfirmActions => '$',
};

# Android System Namespaces used by different manufacturers
# Update this array as required
my @SYSTEM_NAMESPACE = 
(
    "com.android", "com.google", "com.cyanogenmod", "com.sonyericsson",
    "com.motorola", "com.htc", "com.samsung", "com.lge", 
    "com.huawei", "com.zte", "com.sony"
);

my $settings = Settings->new();
my @ADB_DEVICES;
my $ADB_DEVICES_COUNT;

my $DEVICE;
my $SERIAL;

my $LOG_FILE = "./AndSync.log";
my $SETTINGS_FILE = "./Settings.ini";
my $SYNC_DIRECTORY = "./SyncData";
my $BACKUP_DIRECTORY = "./Backup";

my $SYNC_DEVICE_MASTER = "";
my $SYNC_DEVICE_SLAVE = "";

my $SERIAL_DEVICE_MASTER = "";
my $SERIAL_DEVICE_SLAVE = "";

my $choice = " ";

# Print out a banner for information
sub PrintBanner
{
    print "\nAndSync v1.1 - Sync your Andorid devices";
    print "\nCopyright (C) 2012, Winny Mathew Kurian (WiZarD)\n";
}

# Print one time banner
PrintBanner();

# Make sure an instance of ADB server is running before we start
system("adb start-server");

# Refresh the device list
RefreshDeviceList();

# Read settings file
ParseSettings();

# We need 'SyncData' directory for storing files
if (not -d $SYNC_DIRECTORY)
{
    mkdir $SYNC_DIRECTORY;
}

# We need 'Backup' directory for storing files
if (not -d $BACKUP_DIRECTORY)
{
    mkdir $BACKUP_DIRECTORY;
}

# Clear log file
if (-e $LOG_FILE)
{
    system ("echo \"\" > $LOG_FILE");
}

sub isNumber {
    $_[0] =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
}

# This is the main loop for the MAIN menu
while(1) {
    DisplayDevices();

    print "\n==================== MENU =====================\n\n";
    print "0. Exit\n";
    print "1. Sync application between devices\n";
    print "2. Backup applications\n";
    print "3. Restore applications\n";
    print "4. Uninstall applications\n";
    print "5. Restart ADB server\n";
    print "6. Refresh device list\n";
    print "7. Settings\n";
    print "\n[0-7]> ";

    chomp($choice = <STDIN>);
    redo if not isNumber($choice);
    if ($choice < 0 || $choice > 7) {
        print "\nPlease enter a menu option (0-7)\n";
        redo;
    }

    # Exit after clearing sync data if settings say so
    if ($choice == 0) {
        if ($settings->DeleteSyncData) {
            rmtree("$SYNC_DIRECTORY");
        }

        exit;
    }
    elsif ($choice == 1) {
        if ($ADB_DEVICES_COUNT <= 1) {
            print "\nYou need to connect more than one device to perform sync\n";
            redo;
        }

        $SYNC_DEVICE_MASTER = SelectDevice("\nSelect a device to sync from");
        if ($SYNC_DEVICE_MASTER >= 0) {
            $SYNC_DEVICE_SLAVE  = SelectDevice("\nSelect a device to sync to");
            if ($SYNC_DEVICE_SLAVE >= 0) {
                SyncDevices($ADB_DEVICES[$SYNC_DEVICE_MASTER]->serial, $ADB_DEVICES[$SYNC_DEVICE_SLAVE]->serial);
            }
        }
    }
    elsif ($choice == 2) {
        if ($ADB_DEVICES_COUNT < 1) {
            print "\nPlease connect an Android device.\n";
            redo;
        }

        $DEVICE = SelectDevice("\nSelect a device to backup");
        if ($DEVICE >= 0) {
            BackupDevice($ADB_DEVICES[$DEVICE]->serial);
        }
    }
    elsif ($choice == 3) {
        if ($ADB_DEVICES_COUNT < 1) {
            print "\nPlease connect an Android device.\n";
            redo;
        }

        $DEVICE = SelectDevice("\nSelect a device to restore");
        if ($DEVICE >= 0) {
            RestoreDevice($ADB_DEVICES[$DEVICE]->serial);
        }
    }
    elsif ($choice == 4) {
        if ($ADB_DEVICES_COUNT < 1) {
            print "\nPlease connect an Android device.\n";
            redo;
        }

        $DEVICE = SelectDevice("\nSelect a device to uninstall applications");
        if ($DEVICE >= 0) {
            UninstallApps($ADB_DEVICES[$DEVICE]->serial);
        }
    }
    elsif ($choice == 5) {
        print "\n";
        system("adb kill-server");
        system("adb start-server");
    }
    elsif ($choice == 6) {
        undef @ADB_DEVICES;
        RefreshDeviceList();
    }
    elsif ($choice == 7) {
        SettingsMain();
    }
}

# This subroutine is used to save the settings file
sub WriteSettings
{
    open (hSettingsFile, ">$SETTINGS_FILE");

    print hSettingsFile "BackupSystemApps=" . $settings->BackupSystemApps . "\n";
    print hSettingsFile "BackupData=" . $settings->BackupData . "\n";
    print hSettingsFile "RestoreSystemApps=" . $settings->RestoreSystemApps . "\n";
    print hSettingsFile "RestoreData=" . $settings->RestoreData . "\n";
    print hSettingsFile "RemoveData=" . $settings->RemoveData . "\n";
    print hSettingsFile "SyncMissing=" . $settings->SyncMissing . "\n";
    print hSettingsFile "DeleteSyncData=" . $settings->DeleteSyncData . "\n";
    print hSettingsFile "DeleteCompleted=" . $settings->DeleteCompleted . "\n";
    print hSettingsFile "InstallSD=" . $settings->InstallSD . "\n";
    print hSettingsFile "ConfirmActions=" . $settings->ConfirmActions . "\n";

    close (hSettingsFile);
}

# This is the main loop for SETTINGS menu
sub SettingsMain
{
    while(1) {
        printf "\n================== SETTINGS ===================\n\n";
        printf " 0. Back\n";
        printf " 1. Backup system applications       [%4s ]\n", $settings->BackupSystemApps ? "Yes" : "No";
        printf " 2. Backup data on rooted devices    [%4s ]\n", $settings->BackupData ? "Yes" : "No";
        printf " 3. Restore system applications      [%4s ]\n", $settings->RestoreSystemApps ? "Yes" : "No";
        printf " 4. Restore data on rooted devices   [%4s ]\n", $settings->RestoreData ? "Yes" : "No";
        printf " 5. Remove data while un-installing  [%4s ]\n", $settings->RemoveData ? "Yes" : "No";
        printf " 6. Sync missing applications        [%4s ]\n", $settings->SyncMissing ? "Yes" : "No";
        printf " 7. Delete sync data on exit         [%4s ]\n", $settings->DeleteSyncData ? "Yes" : "No";
        printf " 8. Delete package once installed    [%4s ]\n", $settings->DeleteCompleted ? "Yes" : "No";
        printf " 9. Install apps on SD Card          [%4s ]\n", $settings->InstallSD ? "Yes" : "No";
        printf "10. Confirm all actions              [%4s ]\n", $settings->ConfirmActions ? "Yes" : "No";
        printf "11. About AndSync\n";
        printf "\n[0-11]> ";

        chomp($choice = <STDIN>);
        redo if not isNumber($choice);
        if ($choice < 0 || $choice > 11) {
            print "\nPlease enter a menu option (0-11)\n";
            redo;
        }

        if ($choice == 0) {
            # Save settings and return
            WriteSettings();
            return;
        }
        elsif ($choice == 1) {
            $settings->BackupSystemApps($settings->BackupSystemApps ? 0 : 1);
        }
        elsif ($choice == 2) {
            $settings->BackupData($settings->BackupData ? 0 : 1);
        }
        elsif ($choice == 3) {
            $settings->RestoreSystemApps($settings->RestoreSystemApps ? 0 : 1);
        }
        elsif ($choice == 4) {
            $settings->RestoreData($settings->RestoreData ? 0 : 1);
        }
        elsif ($choice == 5) {
            $settings->RemoveData($settings->RemoveData ? 0 : 1);
        }
        elsif ($choice == 6) {
            $settings->SyncMissing($settings->SyncMissing ? 0 : 1);
        }
        elsif ($choice == 7) {
            $settings->DeleteSyncData($settings->DeleteSyncData ? 0 : 1);
        }
        elsif ($choice == 8) {
            $settings->DeleteCompleted($settings->DeleteCompleted ? 0 : 1);
        }
        elsif ($choice == 9) {
            $settings->InstallSD($settings->InstallSD ? 0 : 1);
        }
        elsif ($choice == 10) {
            $settings->ConfirmActions($settings->ConfirmActions ? 0 : 1);
        }
        elsif ($choice == 11) {
            # Open self and print out GNU Copyright notice
            open SELF, __FILE__ or redo;
            while (<SELF>) {
                next if (/#!\//);
                last if (/# ABOUT_END/);
                print $_;
            }
            close(SELF);

            print "\nIf you see a smiley [:)] your device is rooted!\n";
        }
    }
}

# Using ADB update the list of devices attached
sub RefreshDeviceList
{
    my $ADB_DEVICES_CMD;
    my @DEVICES;
    my $PROP_MANUFACTURER;
    my $PROP_PROD_MODEL;
    my $PROP_ANDROID_VERSION;
    my $IS_ROOTED;

    # Get a list of devices, strip off extra details and split it
    # into an array of serial numbers. No more Cygwin deps :p
    $ADB_DEVICES_CMD = `adb devices`;
    $ADB_DEVICES_CMD =~ s/List of devices attached//g;
    $ADB_DEVICES_CMD =~ s/device//g;
    $ADB_DEVICES_CMD =~ s/\R//g;
    $ADB_DEVICES_CMD =~ s/ //g;

    @DEVICES = split /\t/, $ADB_DEVICES_CMD;

    # Get number of devices connected
    $ADB_DEVICES_COUNT = scalar(@DEVICES);

    foreach $SERIAL (@DEVICES) {
        $SERIAL =~ s/\R//g;

        $PROP_MANUFACTURER      = `adb -s $SERIAL shell getprop ro.product.manufacturer`;
        $PROP_PROD_MODEL        = `adb -s $SERIAL shell getprop ro.product.model`;
        $PROP_ANDROID_VERSION   = `adb -s $SERIAL shell getprop ro.build.version.release`;
        $IS_ROOTED              = `adb -s $SERIAL shell ls /system/xbin/su`;

        # Remove all newlines
        $PROP_MANUFACTURER =~ s/\R//g;
        $PROP_PROD_MODEL =~ s/\R//g;
        $PROP_ANDROID_VERSION =~ s/\R//g;
        $IS_ROOTED =~ s/\R//g;

        # Check if we are rooted (Is there a better way?)
        if ($IS_ROOTED =~ /\/system\/xbin\/su$/) {
            $IS_ROOTED = 1;
        } else {
            $IS_ROOTED = 0;
        }

        push @ADB_DEVICES, Device->new(
            serial => $SERIAL,
            manufacturer => $PROP_MANUFACTURER,
            product_model => $PROP_PROD_MODEL,
            android => $PROP_ANDROID_VERSION,
            rooted => $IS_ROOTED);
    }
}

# Smiley face means your device is rooted :)
sub DisplayDevices
{
    my $nDevice = 0;

    if ($ADB_DEVICES_COUNT > 0) {
        print "\n============ Connected Devices [$ADB_DEVICES_COUNT] ============\n\n";
    } else {
        print "\nNo Android device connected!\n";
    }

    while ($nDevice < $ADB_DEVICES_COUNT) {
        $nDevice++;
        printf "%2d: %-14s [ %5s ] - %-16s%s\n", $nDevice, 
            $ADB_DEVICES[$nDevice-1]->manufacturer,
            $ADB_DEVICES[$nDevice-1]->product_model,
            $ADB_DEVICES[$nDevice-1]->serial,
            $ADB_DEVICES[$nDevice-1]->rooted ? " [:)]" : "";
    }
}

# Checks if the given app in a system app (Not very amazing, but no other go now)
#
# The array here needs to be updated as required or this sub-routine has to be
# replaced with a better one.
#
sub isSystemApp
{
    my $packageName = shift;
    my $bSys = 0;

    # Mark framework-res apk as a system app
    if ($packageName =~ /^android/) {
        $bSys = 1;
    }
    else {
        foreach my $namespace (@SYSTEM_NAMESPACE) {
            if ($packageName =~ /^$namespace.[\d\S]+/) {
                $bSys = 1;
                last;
            }
        }
    }

    return $bSys;
}

sub BackupDevice
{
    $SERIAL = shift;
    my $nPackages = 0;
    my $nPackagesDone = 0;

    return if ($ADB_DEVICES_COUNT < 1);

    RetriveDeviceReport($SERIAL);

    my %phashMaster = ParseADBReport($SERIAL);
    $nPackages = scalar(keys(%phashMaster));

    print "\nFound $nPackages applications in $SERIAL\n";
    if (ConfirmPrompt("\nProceed with backup")) {
        $nPackagesDone = PullPackages(\%phashMaster, $SERIAL, $BACKUP_DIRECTORY);
    }

    print "\nTotal $nPackages packages. $nPackagesDone packages were backed up. " . 
          ($nPackages - $nPackagesDone) . " packages were ignored.\n";
}

sub RestoreDevice
{
    $SERIAL = shift;
    my $DIR = $SERIAL;

    my $nPackages = 0;
    my $nPackagesDone = 0;
    my $packageBaseName;
    my @apk_files;

    return if ($ADB_DEVICES_COUNT < 1);

    while (1) {
        while (1) {
            if (not -d "$BACKUP_DIRECTORY/$DIR/") {
                print "\nNo backup data found for $DIR\n";

                if (ConfirmPrompt("\nWould you like to restore from another device")) {
                    print "\nEnter serial number of the device: ";
                    chomp($DIR = <STDIN>);

                    return if (not $DIR);
                    redo;
                } else {
                    return;
                }
            }
        }

        # This will get us file names with path
        @apk_files = glob "$BACKUP_DIRECTORY/$DIR/*.apk";
        $nPackages = scalar(@apk_files);

        if ($nPackages < 1) {
            print "\nThere are no packages to restore.\n";
            redo;
        } else {
            last;
        }
    }

    my $rooted = isDeviceRooted($SERIAL);
    my $installSD = $settings->InstallSD ? "-s" : "";

    print "\nFound $nPackages packages to restore\n";
    if (ConfirmPrompt("\nProceed with restore")) {
        foreach my $packageName (@apk_files) {
            if (not $settings->RestoreSystemApps) {
                next if isSystemApp($packageName);
            }

            $packageBaseName = basename("$packageName");
            $packageBaseName =~ s/\.[^.]+$//;

            print "\nRestoring $packageBaseName\n";
            system("adb -s $SERIAL install $installSD $packageName");

            if ($rooted && $settings->RestoreData) {
                print "\nRestoring data for $packageBaseName\n";

                # Remove the extension from the name
                $packageName =~ s/\.[^.]+$//;

                # Extract the package data
                print "\nExtracting data...\n";
                my $zip = Archive::Zip->new("$packageName.zip");
                $zip->extractTree("", "$BACKUP_DIRECTORY/$DIR/");

                # FIXME: We have not preserved any metadata for restore, hence data path is hardcoded for now
                system("adb -s $SERIAL push $packageName /data/data/$packageBaseName");

                # Remove data directory
                rmtree("$packageName");
            }

            $nPackagesDone++;
        }

        print "\nTotal $nPackages packages. $nPackagesDone packages were restored. " . 
              ($nPackages - $nPackagesDone) . " packages were ignored.\n";
    }
}

sub UninstallApps
{
    $SERIAL = shift;

    my $nPackages = 0;
    my $nPackagesDone = 0;

    return if ($ADB_DEVICES_COUNT < 1);

    RetriveDeviceReport($SERIAL);

    my %phashUninstall = ParseADBReport($SERIAL);
    $nPackages = scalar(keys(%phashUninstall));

    print "\nFound $nPackages applications in $SERIAL to uninstall\n";
    if (ConfirmPrompt("\nProceed with Uninstall")) {
        $nPackagesDone = UninstallPackages(\%phashUninstall, $SERIAL);
    }

    print "\nTotal $nPackages packages. $nPackagesDone packages were unistalled. " . 
          ($nPackages - $nPackagesDone) . " packages were ignored.\n";
}

sub ConfirmPrompt
{
    my $PROMPT = $_[0];
    my $choice;

    if (not $settings->ConfirmActions) {
        return 1;
    }

    while (1) {
        print "$PROMPT (Yes/No): ";
        $choice = <STDIN>;
        chomp ($choice);

        if (not $choice =~ /^YN/i) {
            return ($choice =~ /^Y/i) ? 1 : 0;
        } else {
            next;
        }
    }
}

sub SelectDevice
{
    my $PROMPT = $_[0];

    while (1) {
        print "$PROMPT ('0' to Go Back): ";
        $DEVICE = <STDIN>;
        chomp ($DEVICE);

        $DEVICE--;
        if (($DEVICE >= $ADB_DEVICES_COUNT) || ($DEVICE < 0)) {
            if ($DEVICE < 0) {
                return $DEVICE;
            } else {
                next;
            }
        } else {
            last;
        }
    }

    return $DEVICE;
}

sub RetriveDeviceReport
{
    $SERIAL = $_[0];
    my $UPDATE = 1;

    if (-e "$SYNC_DIRECTORY/$SERIAL.txt") {
        $UPDATE = not ConfirmPrompt("\nSync data found for $SERIAL. Use this?");
    }

    if ($UPDATE) {
        print "\nRetriving device and application details from $SERIAL...\n";
        system ("adb -s $SERIAL bugreport > $SYNC_DIRECTORY/$SERIAL.txt");
    }
}

# Perform device sync
sub SyncDevices
{
    my $nPackagesPulled = 0;
    my $nPackagesPushed = 0;

    $SERIAL_DEVICE_MASTER = $_[0];
    $SERIAL_DEVICE_SLAVE  = $_[1];

    return if ($ADB_DEVICES_COUNT <= 1);

    print "\nYou have selected to sync $SERIAL_DEVICE_SLAVE with $SERIAL_DEVICE_MASTER\n";
    RetriveDeviceReport($SERIAL_DEVICE_MASTER);
    RetriveDeviceReport($SERIAL_DEVICE_SLAVE);

    my %phashMaster = ParseADBReport($SERIAL_DEVICE_MASTER);
    print "\nFound " . scalar(keys(%phashMaster)) . " applications in $SERIAL_DEVICE_MASTER\n";

    my %phashSlave = ParseADBReport($SERIAL_DEVICE_SLAVE);
    print "Found " . scalar(keys(%phashSlave)) . " applications in $SERIAL_DEVICE_SLAVE\n\n";

    my %phashUpdate = ResolvePackageSync(\%phashMaster, \%phashSlave);
    print "\nFound " . scalar(keys(%phashUpdate)) . " applications to be updated\n";

    if (ConfirmPrompt("\nDo you wish to proceed with sync?")) {
        $nPackagesPulled = PullPackages(\%phashUpdate, $SERIAL_DEVICE_MASTER, $SYNC_DIRECTORY);
        print "\n";
        $nPackagesPushed = PushPackages(\%phashUpdate, $SERIAL_DEVICE_MASTER, $SERIAL_DEVICE_SLAVE, $SYNC_DIRECTORY);
    }

    print "\nSynced " . $nPackagesPushed . " packages\n";
}

# Install packages and push appliction data downloaded from a
# MASTER sync device to a SLAVE sync device
sub PushPackages
{
    my $params = shift;
    my %phashUpdate = %$params;
    $SERIAL_DEVICE_MASTER = shift;
    $SERIAL_DEVICE_SLAVE = shift;
    my $DIRECTORY = shift;

    my $nPackagesDone = 0;
    my $dataPath;
    my $rooted = isDeviceRooted($SERIAL_DEVICE_MASTER);
    my $installSD = $settings->InstallSD ? "-s" : "";

    while(my ($packageName, $packageUpdate) = each(%phashUpdate)) {
        if (ConfirmPrompt("Update $packageName")) {

            if (not $settings->RestoreSystemApps) {
                next if isSystemApp($packageName);
            }

            print "\nUpdating $packageName\n";
            system("adb -s $SERIAL_DEVICE_SLAVE install -r $installSD $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.apk");

            # Now restore data if the device is rooted
            if ($rooted && $settings->RestoreData) {
                print "\nUpdating data for $packageName\n";

                # Extract the package data
                print "\nExtracting data...\n";
                my $zip = Archive::Zip->new("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.zip");
                $zip->extractTree("", "$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");

                $dataPath = $packageUpdate->data_path;
                system("adb -s $SERIAL_DEVICE_SLAVE push $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName $dataPath");

                # Remove data directory
                rmtree("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");

                if ($settings->DeleteCompleted) {
                    unlink("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.zip");
                }
            }

            # TODO: Check for return code and delete the package if successful
            if ($settings->DeleteCompleted) {
                unlink("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.apk");
            }

            $nPackagesDone++;
        }
    }

    return $nPackagesDone;
}

# Retrive packages and data from a device
sub PullPackages
{
    my $params = shift;
    my %phashUpdate = %$params;
    $SERIAL_DEVICE_MASTER = shift;
    my $DIRECTORY = shift;

    my $apkPath;
    my $dataPath;
    my $nPackages = 0;
    my $rooted = isDeviceRooted($SERIAL_DEVICE_MASTER);

    while(my ($packageName, $packageUpdate) = each(%phashUpdate)) {
        $apkPath = $packageUpdate->path;

        if (not $settings->BackupSystemApps) {
            next if isSystemApp($packageName);
        }

        print "\nRetriving package $apkPath\n";
        system("adb -s $SERIAL_DEVICE_MASTER pull $apkPath $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.apk");

        if ($rooted && $settings->BackupData) {
            $dataPath = $packageUpdate->data_path;
            print "\nRetriving data and settings for $packageName\n";
            system("adb -s $SERIAL_DEVICE_MASTER pull $dataPath $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");

            # Create and archive (zip)
            print "\nCreating zip archive...\n";
            my $zip = Archive::Zip->new();
            $zip->addTree("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName", "$packageName");
            $zip->writeToFileNamed("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.zip");

            # Remove data directory
            rmtree("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");
        }

        $nPackages++;
    }

    return $nPackages;
}

sub UninstallPackages
{
    my $params = shift;
    my %phashUninstall = %$params;
    $SERIAL = shift;

    my $nPackagesDone = 0;

    # Delete data if the user wishes so
    my $KeepData = ($settings->RemoveData) ? "" : "-k";

    while(my ($packageName, $packageUninstall) = each(%phashUninstall)) {
        if (ConfirmPrompt("Uninstall $packageName")) {
            # We do not un-install system apps!
            next if isSystemApp($packageName);

            print "\nUn-installing $packageName\n";
            system("adb -s $SERIAL uninstall $KeepData $packageName");

            $nPackagesDone++;
        }
    }

    return $nPackagesDone;
}

#
# All main subroutines are written so that it accepts a serial number as
# input. This is done to support command line features and automation in
# future versions.
#
# This sub routine can be removed if we convert device structure to a hash
# but then we need to map UI to device hash, so leaving this as is for now.
#
sub GetDeviceProperty
{
    $SERIAL = shift;
    my $KEY = shift;

    foreach my $device (@ADB_DEVICES) {
        next if ($device->serial ne $SERIAL);
        return $device->$KEY;
    }
}

# Check if the device is rooted
sub isDeviceRooted
{
    $SERIAL = shift;
    return GetDeviceProperty($SERIAL, "rooted");
}

sub ResolvePackageSync
{
    my $params = shift;
    my %phashMaster = %$params;
    $params = shift;
    my %phashSlave = %$params;

    my %phash = ();
    my $packageSlave;

    while(my ($key, $packageMaster) = each(%phashMaster)) {
        $packageSlave = $phashSlave {$packageMaster->name};
        if ($packageSlave)
        {
            next if isSystemApp($packageMaster->name);

            if ($packageMaster->version_code > $packageSlave->version_code)
            {
                print "+++ '$key' needs to be updated +++\n";

                # Add packages to be updated to hash
                $phash{ $packageMaster->name } = $packageMaster;

                # Uncomment for debugging
                #DbgPrintPackage($packageSlave);
                #DbgPrintPackage($packageMaster);

                # Reset package contents
                #ResetPackageStruct($packageSlave);
                #ResetPackageStruct($packageMaster);
            }
        }
        else
        {
            if ($settings->SyncMissing) {
                print "+++ '$key' needs to be installed +++\n";

                # Add missing packages to be installed
                $phash{ $packageMaster->name } = $packageMaster;
            }
        }
    }

    return %phash;
}

# Parse settings file and convert it to Settings struct
sub ParseSettings
{
    my $key;
    my $value;

    if (not -e $SETTINGS_FILE) {
        # No settings file found, so create one with default SAFE settings
        $settings->BackupSystemApps(0);
        $settings->BackupData(1);
        $settings->RestoreSystemApps(0);
        $settings->RestoreData(0);
        $settings->RemoveData(0);
        $settings->SyncMissing(0);
        $settings->DeleteSyncData(0);
        $settings->DeleteCompleted(0);
        $settings->InstallSD(0);
        $settings->ConfirmActions(1);

        WriteSettings();
    }

    open(hSettingsFile, $SETTINGS_FILE) or die "Could not open $SETTINGS_FILE!\n";

    while (<hSettingsFile>)
    {
        if (/BackupSystemApps=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->BackupSystemApps($value);
            next;
        }
        if (/BackupData=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->BackupData($value);
            next;
        }
        if (/RestoreSystemApps=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->RestoreSystemApps($value);
            next;
        }
        if (/RestoreData=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->RestoreData($value);
            next;
        }
        if (/RemoveData=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->RemoveData($value);
            next;
        }
        if (/SyncMissing=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->SyncMissing($value);
            next;
        }
        if (/DeleteSyncData=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->DeleteSyncData($value);
            next;
        }
        if (/ConfirmActions=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->ConfirmActions($value);
            next;
        }
        if (/InstallSD=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->InstallSD($value);
            next;
        }
        if (/DeleteCompleted=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->DeleteCompleted($value);
            next;
        }
    }

    close(hSettingsFile);
}

# Parse ADB bugreport file and build a list of applications installed
# This function returns a hash of Package structure
sub ParseADBReport
{
    my $SERIAL = $_[0];
    my $STRING_KV;

    open(hReportFile, "$SYNC_DIRECTORY/$SERIAL.txt") or die "Could not open $SERIAL.txt!\n";

    my %phash = ();
    my $package = Package->new();

    while (<hReportFile>)
    {
        if (/  Package \[[\d\S]+\] \(*[a-f0-9]{8,}\):/i) {
            $STRING_KV = $_;
            # Remove CR-LF to make substr work same on all systems
            $STRING_KV =~ s/\R//g;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 11, -13);
            $package->name($STRING_KV);
            next;
        }
        if (/    codePath=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 13);
            $package->path($STRING_KV);
            next;
        }
        if (/    versionCode=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 16);
            $package->version_code($STRING_KV);
            next;
        }
        if (/    versionName=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 16);
            $package->version_name($STRING_KV);
            next;
        }
        if (/    dataDir=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 13);
            $package->data_path($STRING_KV);
            next;
        }

        if ($package->name && $package->path && $package->version_code && $package->version_name) {
            # Uncomment the following code for debugging
            # DbgPrintPackage($package);

            # Add package structure to hash
            $phash{ $package->name } = $package;

            # Create a new package instance;
            $package = Package->new();
            ResetPackageStruct($package);
        }
    }

    # Close the ADB report file and return the package hash created
    close(hReportFile);
    return %phash;
}

# Clear/Reset package structure fields
sub ResetPackageStruct
{
    my $package = $_[0];

    $package->name("");
    $package->path("");
    $package->version_code("");
    $package->version_name("");
    $package->data_path("");
}

# Debug subroutine to print the contents of a package
sub DbgPrintPackage
{
    my $package = $_[0];

    print "Package\n";
    print "--Name: " . $package->name . "\n";
    print "--Path: " . $package->path . "\n";
    print "--Version Code: " . $package->version_code . "\n";
    print "--Version Name: " . $package->version_name . "\n\n";
    print "--Data Path: " . $package->data_path . "\n\n";
}

# Debug subroutine to print the hash of packages
sub DbgPrintPackageHash
{
    my (%phash) = @_;

    while(my ($key, $package) = each(%phash)) {
        print "$key => $package\n";
        DbgPrintPackage($package);
    }
}