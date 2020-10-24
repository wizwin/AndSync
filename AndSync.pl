#!/usr/bin/perl -w

###############################################################################
#
# AndSync - Synchronize, Backup and Restore your Android device
#
# AndSync Copyright (C) 2012-2020 Winny Mathew Kurian (WiZarD)
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
#                 $ sudo apt install adb (on 20.04)
#  Perl         - Class::Struct File::Path File::Basename File::Fetch 
#                 File::Copy Archive::Zip, (File::Fetch->Version)
#                 $ sudo perl -MCPAN -e shell
# Revisions
###############################################################################
#   Date           Version    Author   Comments
###############################################################################
#   28.08.2012     1.0        WiZarD   Initial version
#   13.09.2012     1.1        WiZarD   New features and bug fixes
#   18.09.2012     1.2        WiZarD   Added new backup and restore method
#   23.09.2012     1.3        WiZarD   Self updater, Prompt if backup exists
#   12.04.2014     1.4        WiZarD   Fixed bugs, Enhancements (Not released)
#   18.10.2020     1.5        WiZarD   Support Android Pie and above
###############################################################################

use strict;

use Class::Struct;
use File::Path;
use File::Basename;
use File::Fetch;
use File::Copy;
use Archive::Zip;
# use Version;

# 'Package' structure holds APK details parsed from ADB report
struct Package => {
    name => '$',
    path => '$',
    version_code => '$',
    version_name => '$',
    data_path => '$',
    system => '$',
};

# 'Device' structure holds device properties
struct Device => {
    serial => '$',
    manufacturer => '$',
    product_model => '$',
    android => '$',
    rooted => '$',
};

# 'Settings' structure contains various settings using by this script
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
    UseNewADBCmd => '$',
    ConfirmActions => '$',
    OnlyBaseAPK => '$',
};

# Android System Namespaces used by different manufacturers
# Update this array as required
my @SYSTEM_NAMESPACE = 
(
    #"com.google",
    "com.android", "com.sec",
    "com.cyanogenmod",
    "org.codeaurora", "com.qti", "com.qualcomm.qti",
    "com.sonyericsson", "com.motorola", "com.htc", "com.samsung",
    "com.lge", "com.huawei", "com.zte", "com.sony",
    "com.asus"
);

# Enable for debug prints
my $DEBUG = 0;
my $DEBUG_PACKAGES = 0;

my $settings = Settings->new();
my @ADB_DEVICES;
my $ADB_DEVICES_COUNT;

my $DEVICE;
my $SERIAL;

# Path to RAW file 'AndSync.pl' on GitHub
my $UPDATER_GIT_FILE = "http://raw.github.com/wizwin/AndSync/master/AndSync.pl";

# Temporary path used by self updater
my $UPDATER_TMP_DIR = "./Updater.tmp";

# Log file name (not used now)
my $LOG_FILE = "./AndSync.log";

# Settings file
my $SETTINGS_FILE = "./Settings.ini";

# Sync data directory
my $SYNC_DIRECTORY = "./SyncData";

# Backup directory
my $BACKUP_DIRECTORY = "./Backup";

# Android versions
# ICS
my $VERSION_ICS = version->declare("4.0.0");
# Pie
my $VERSION_PIE = version->declare("9.0.0");

my $SYNC_DEVICE_MASTER = "";
my $SYNC_DEVICE_SLAVE = "";

my $SERIAL_DEVICE_MASTER = "";
my $SERIAL_DEVICE_SLAVE = "";

my $choice = " ";

# Print debug messages
sub printD
{
    my $dbgMessage = shift;

    if ($DEBUG == 1) {
        print "DEBUG: " . $dbgMessage . "\n";
    }
}

# Print out a banner for information
sub PrintBanner
{
    print "\nAndSync v1.5 - Sync your Andorid devices";
    print "\nCopyright (C) 2012-2020, Winny Mathew Kurian (WiZarD)\n";
}

sub CheckExec
{
    my $check = `sh -c 'command -v $_[0]'`; 
    return $check;
}

# Print one time banner
PrintBanner();

# Check if we have pre-requisites installed
CheckExec('adb') or die "\nPre-requisite missing: adb\n";

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
                SyncDevices(
                    $ADB_DEVICES[$SYNC_DEVICE_MASTER]->serial, 
                    $ADB_DEVICES[$SYNC_DEVICE_SLAVE]->serial);
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
    print hSettingsFile "UseNewADBCmd=" . $settings->UseNewADBCmd . "\n";
    print hSettingsFile "OnlyBaseAPK=" . $settings->OnlyBaseAPK . "\n";
    print hSettingsFile "ConfirmActions=" . $settings->ConfirmActions . "\n";

    close (hSettingsFile);
}

# This is the main loop for SETTINGS menu
sub SettingsMain
{
    while(1) {
        printf "\n================== SETTINGS ===================\n\n";
        printf " 0. Back\n";
        printf " 1. Backup system applications          [%4s ]\n", 
            $settings->BackupSystemApps ? "Yes" : "No";
        printf " 2. Backup data on rooted devices       [%4s ]\n",
            $settings->BackupData ? "Yes" : "No";
        printf " 3. Restore system applications         [%4s ]\n",
            $settings->RestoreSystemApps ? "Yes" : "No";
        printf " 4. Restore data on rooted devices      [%4s ]\n",
            $settings->RestoreData ? "Yes" : "No";
        printf " 5. Remove data while un-installing     [%4s ]\n",
            $settings->RemoveData ? "Yes" : "No";
        printf " 6. Sync missing applications           [%4s ]\n",
            $settings->SyncMissing ? "Yes" : "No";
        printf " 7. Delete sync data on exit            [%4s ]\n",
            $settings->DeleteSyncData ? "Yes" : "No";
        printf " 8. Delete package once installed       [%4s ]\n",
            $settings->DeleteCompleted ? "Yes" : "No";
        printf " 9. Install apps on SD Card             [%4s ]\n",
            $settings->InstallSD ? "Yes" : "No";
        printf "10. Use new backup-restore (above GB)   [%4s ]\n",
            $settings->UseNewADBCmd ? "Yes" : "No";
        printf "11. Backup only Base APK (above Oreo)   [%4s ]\n",
            $settings->OnlyBaseAPK ? "Yes" : "No";
        printf "12. Confirm all actions                 [%4s ]\n",
            $settings->ConfirmActions ? "Yes" : "No";
        printf "13. Update this script\n";
        printf "14. About AndSync\n";
        printf "\n[0-14]> ";

        chomp($choice = <STDIN>);
        redo if not isNumber($choice);
        if ($choice < 0 || $choice > 14) {
            print "\nPlease enter a menu option (0-14)\n";
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
            $settings->UseNewADBCmd($settings->UseNewADBCmd ? 0 : 1);
        }
        elsif ($choice == 11) {
            $settings->OnlyBaseAPK($settings->OnlyBaseAPK ? 0 : 1);
        }
        elsif ($choice == 12) {
            $settings->ConfirmActions($settings->ConfirmActions ? 0 : 1);
        }
        elsif ($choice == 13) {
            PerformSelfUpdate();
        }
        elsif ($choice == 14) {
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

sub PerformSelfUpdate
{
    $File::Fetch::WARN = 0;
    my $Updater;
    my $Path;

    if (ConfirmPrompt("\nProceed with script update")) {

        print "\nDownloading script from server...\n";
        $Updater = File::Fetch->new(uri => $UPDATER_GIT_FILE);
        if ($Updater) {
            $Path = $Updater->fetch(to => $UPDATER_TMP_DIR);

            if ($Path) {
                copy("$UPDATER_TMP_DIR/AndSync.pl", "AndSync.pl");
                rmtree($UPDATER_TMP_DIR);
                if (ConfirmPrompt("\nUpdated. Restart script")) {
                    exec($^X, $0, @ARGV);
                } else {
                    return;
                }
            }
        }

        # We will get here only only if the update fails
        rmtree($UPDATER_TMP_DIR);
        print "\nUpdate failed! Please make sure you are connected to internet.\n"
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

        # FIXME: We need to check device autherization here so that script won't abort
        # for a device that is connected for the first time
        $PROP_MANUFACTURER      = `adb -s $SERIAL shell getprop ro.product.manufacturer`;
        $PROP_PROD_MODEL        = `adb -s $SERIAL shell getprop ro.product.model`;
        $PROP_ANDROID_VERSION   = `adb -s $SERIAL shell getprop ro.build.version.release`;
        $IS_ROOTED              = `adb -s $SERIAL shell ls /system/xbin/su 2>/dev/null`;

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

        $PROP_ANDROID_VERSION = version->parse($PROP_ANDROID_VERSION);

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
        printf "%2d: %-14s [ %10s ] - %-16s%s\n", $nDevice, 
            $ADB_DEVICES[$nDevice-1]->manufacturer,
            $ADB_DEVICES[$nDevice-1]->product_model,
            $ADB_DEVICES[$nDevice-1]->serial,
            $ADB_DEVICES[$nDevice-1]->rooted ? " [:)]" : "";
    }
}

# Checks if the given app is a system app (Not very amazing, but no other way now)
#
# The package is marked as system if we find this is a system application
#
sub MarkSystemApp
{
    my $package = shift;
    my $packageName = $package->name;
    my $packagePath = $package->path;
    my $bSys = 0;

    # Mark framework-res apk as a system app
    if (($packageName =~ /^android/) || ($packagePath =~ /^\/system\/app|priv-app/)) {
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

    $package->system($bSys);
    return $bSys;
}

sub BackupDevice
{
    $SERIAL = shift;
    my $nPackages = 0;
    my $nPackagesDone = 0;
    my $VersionDev;
    my $BackupSystemApps;
    my @apk_files;

    return if ($ADB_DEVICES_COUNT < 1);

    # On newer devices use 'adb backup' if user has configured so else
    # proceed with normal backup method.
    $VersionDev = GetDeviceProperty($SERIAL, "android");
    if ($settings->UseNewADBCmd && ($VersionDev > $VERSION_ICS)) {
        if (ConfirmPrompt("\nProceed with backup")) {
            $BackupSystemApps = $settings->BackupSystemApps ? "-system" : "-nosystem";

            if (-e "$BACKUP_DIRECTORY/$SERIAL/$SERIAL.ab") {
                if (not ConfirmPrompt("\nOverwrite existing backup")) {
                    return;
                }
            }

            print "\nPlease confirm backup operation on your device [$SERIAL]...\n";
            system("adb -s $SERIAL backup -f $BACKUP_DIRECTORY/$SERIAL/$SERIAL.ab -apk $BackupSystemApps -all");
            if ($? < 0) {
                print "\nBackup failed!\n";
            } elsif ($? == 0) {
                print "\nBackup complete!\n";
            }
        }
    }
    else {
        RetriveDeviceReport($SERIAL);

        my %phashMaster = ParseADBReport($SERIAL);
        $nPackages = scalar(keys(%phashMaster));

        print "\nFound $nPackages applications in $SERIAL\n";
        if (ConfirmPrompt("\nProceed with backup")) {
            @apk_files = glob "$BACKUP_DIRECTORY/$SERIAL/*.apk";

            if (-e "$BACKUP_DIRECTORY/$SERIAL" && (scalar(@apk_files) > 1)) {
                if (not ConfirmPrompt("\nOverwrite existing backups")) {
                    return;
                }
            }

            $nPackagesDone = PullPackages(\%phashMaster, $SERIAL, $BACKUP_DIRECTORY);
        }

        print "\nTotal $nPackages packages. $nPackagesDone packages were backed up. " . 
              ($nPackages - $nPackagesDone) . " packages were ignored.\n";
    }
}

sub RestoreDevice
{
    $SERIAL = shift;
    my $DIR = $SERIAL;

    my $nPackages = 0;
    my $nPackagesDone = 0;
    my $packageBaseName;
    my $VersionDev;
    my @apk_files;
    my $package = Package->new();

    return if ($ADB_DEVICES_COUNT < 1);

    # On newer devices use 'adb restore' if user has configured so else
    # proceed with normal restore method.
    $VersionDev = GetDeviceProperty($SERIAL, "android");
    if ($settings->UseNewADBCmd && ($VersionDev > $VERSION_ICS)) {
        if (not -e "$BACKUP_DIRECTORY/$DIR/$DIR.ab") {
            print "No data found to restore for $SERIAL...\n";
            return;
        }

        if (ConfirmPrompt("\nProceed with restore")) {
            print "\nPlease confirm restore operation on your device [$SERIAL]...\n";
            system("adb -s $SERIAL restore $BACKUP_DIRECTORY/$DIR/$DIR.ab");
        }

        if ($? < 0) {
            print "\nRestore failed!\n";
        } elsif ($? == 0) {
            print "\nRestore complete!\n";
        }

        return;
    }

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
            else {
                last;
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
                $package->name($packageName);
                $package->path(""); # FIXME
                MarkSystemApp($package);
                next if $package->system;
            }

            $packageBaseName = basename("$packageName");
            $packageBaseName =~ s/\.[^.]+$//;

            print "\nRestoring $packageBaseName\n";
            system("adb -s $SERIAL install $installSD $packageName");
            if ($? < 0) {
                print "\n[Error] While installing package: $packageName. Continuing...\n";
                next;
            }

            next if (($? >> 8) & 127);

            if (($? == 0) && $rooted && $settings->RestoreData) {
                print "\nRestoring data for $packageBaseName\n";

                # Remove the extension from the name
                $packageName =~ s/\.[^.]+$//;

                # Extract the package data
                print "\nExtracting data...\n";
                my $zip = Archive::Zip->new("$packageName.zip");
                $zip->extractTree("", "$BACKUP_DIRECTORY/$DIR/");

                # FIXME: We have not preserved any metadata for restore, 
                # hence data path is hardcoded for now
                system("adb -s $SERIAL push $packageName /data/data/$packageBaseName");
                if ($? < 0) {
                    print "\n[Error] While installing data for: $packageName. Continuing...\n";
                }

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
    my $VersionDev;

    if (-e "$SYNC_DIRECTORY/$SERIAL.txt") {
        $UPDATE = not ConfirmPrompt("\nSync data found for $SERIAL. Use this?");
    }

    if ($UPDATE) {
        print "\nRetriving device and application details from $SERIAL...\n";

        $VersionDev = GetDeviceProperty($SERIAL, "android");
	if ($VersionDev < $VERSION_PIE) {
            system("adb -s $SERIAL bugreport > $SYNC_DIRECTORY/$SERIAL.txt");
        } else {
            # Newer bugreports are packaged as zip file and we need to
	    # unzip them to get the txt version of bug report
            if (not -d "$SYNC_DIRECTORY/$SERIAL") {
                mkdir "$SYNC_DIRECTORY/$SERIAL";
            }

            if (not -e "$SYNC_DIRECTORY/$SERIAL/$SERIAL.zip") {
                system("adb -s $SERIAL bugreport $SYNC_DIRECTORY/$SERIAL/$SERIAL.zip");
            }

            system("unzip -q -o $SYNC_DIRECTORY/$SERIAL/$SERIAL.zip -d $SYNC_DIRECTORY/$SERIAL");
            system("mv `find $SYNC_DIRECTORY/$SERIAL -name bugreport-*.txt` $SYNC_DIRECTORY/$SERIAL.txt");
        }
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
        $nPackagesPushed = PushPackages(\%phashUpdate, $SERIAL_DEVICE_MASTER, 
                                                       $SERIAL_DEVICE_SLAVE, $SYNC_DIRECTORY);
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
        if (ConfirmPrompt("\nUpdate $packageName")) {

            if (not $settings->RestoreSystemApps) {
                next if $packageUpdate->system;
            }

            print "\nUpdating $packageName\n";
            system("adb -s $SERIAL_DEVICE_SLAVE install -r $installSD $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.apk");
            if ($? < 0) {
                print "\n[Error] While installing package: $packageName. Continuing...\n";
                next;
            }

            next if (($? >> 8) & 127);

            # Now restore data if the device is rooted
            if (($? == 0) && $rooted && $settings->RestoreData) {
                print "\nUpdating data for $packageName\n";

                # Extract the package data
                print "\nExtracting data...\n";
                my $zip = Archive::Zip->new("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.zip");
                $zip->extractTree("", "$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");

                system("adb -s $SERIAL_DEVICE_SLAVE push $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName $dataPath");
                if ($? < 0) {
                    print "\n[Error] While installing data for: $packageName. Continuing...\n";
                }

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
    my $VersionDev;
    my $cmdPull;

    $VersionDev = GetDeviceProperty($SERIAL, "android");

    # Pie and above keeps application and libraries in its own directories
    # So create a directory per device serial
    if ($VersionDev >= $VERSION_PIE) {
        if (not -d "$DIRECTORY/$SERIAL_DEVICE_MASTER") {
            mkdir "$DIRECTORY/$SERIAL_DEVICE_MASTER"; 
        }
    }

    while(my ($packageName, $packageUpdate) = each(%phashUpdate)) {
        $apkPath = $packageUpdate->path;

        if (not $settings->BackupSystemApps) {
            next if $packageUpdate->system;
        }

        if ($VersionDev >= $VERSION_PIE) {
            if ($settings->OnlyBaseAPK) {
                if ($packageUpdate->system) {
                    $apkPath = $apkPath . "/" . basename("$apkPath") . ".apk";
                } else {
                    $apkPath = $apkPath . "/base.apk";
                }
            }
        }

        $cmdPull = "adb -s $SERIAL_DEVICE_MASTER pull $apkPath $DIRECTORY/$SERIAL_DEVICE_MASTER/";

        print "\nRetriving package $apkPath\n";
        if ($VersionDev < $VERSION_PIE) {
            $cmdPull = $cmdPull . "$packageName.apk";
        } else {
            if ($settings->OnlyBaseAPK) {
                $cmdPull = $cmdPull . "$packageName.apk";
            } else {
                $cmdPull = $cmdPull . "$packageName";
            }
        }

        printD("ADB Pull Command: $cmdPull");
        system($cmdPull);

        if ($? < 0) {
            print "\n[Error] While retriving package: $packageName. Continuing...\n";
            next;
        }

        next if (($? >> 8) & 127);

        if (($? == 0) && $rooted && $settings->BackupData) {
            $dataPath = $packageUpdate->data_path;
            if ($dataPath eq "null") {
                print "\nNo data to backup for $packageName\n";
                next;
            }

            print "\nRetriving data and settings for $packageName\n";
            system("adb -s $SERIAL_DEVICE_MASTER pull $dataPath $DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");
            if ($? < 0) {
                print "\n[Error] While retriving data for: $packageName. Continuing...\n";
            } elsif ($? == 0) {
                # Create and archive (zip)
                print "\nCreating zip archive...\n";
                my $zip = Archive::Zip->new();
                $zip->addTree("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName", "$packageName");
                $zip->writeToFileNamed("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName.zip");

                # Remove data directory
                rmtree("$DIRECTORY/$SERIAL_DEVICE_MASTER/$packageName");
            }
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
            next if $packageUninstall->system;

            print "\nUn-installing $packageName\n";
            system("adb -s $SERIAL uninstall $KeepData $packageName");
            if ($? < 0) {
                print "\n[Error] While uninstalling package: $packageName. Continuing...\n";
                next;
            }

            next if (($? >> 8) & 127);

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

        # Ignore system apps when syncing
        next if $packageMaster->system;

        if ($packageSlave)
        {
            if ($packageMaster->version_code > $packageSlave->version_code)
            {
                print "[^] Package '$key' needs to be updated\n";

                # Add packages to be updated to hash
                $phash{ $packageMaster->name } = $packageMaster;

                if ($DEBUG_PACKAGES == 1) {
                    DbgPrintPackage($packageSlave);
                    DbgPrintPackage($packageMaster);
                }

                # Uncomment for debugging
                # Reset package contents
                #ResetPackageStruct($packageSlave);
                #ResetPackageStruct($packageMaster);
            }
        }
        else
        {
            if ($settings->SyncMissing) {
                print "[+] Package '$key' needs to be installed\n";

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
        $settings->UseNewADBCmd(1);
        $settings->OnlyBaseAPK(0);
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
        if (/UseNewADBCmd=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->UseNewADBCmd($value);
            next;
        }
        if (/OnlyBaseAPK=/) {
            $value = $_;
            chomp($value);
            ($key, $value) = split(/=/, $value);
            $settings->OnlyBaseAPK($value);
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
    my $VersionDev;
    my $LenParsePkgHex;
    my $LenParsePkgName;
    my $pkgParserCode = 0;
    my $pkgNextParserCode = 1;
    my $parseSuccess = 1;

    $VersionDev = GetDeviceProperty($SERIAL, "android");
    if ($VersionDev < $VERSION_PIE) {
        $LenParsePkgHex = 8;
        $LenParsePkgName = -13
    } else {
        $LenParsePkgHex = 6;    #FIXME: Hard coded
        $LenParsePkgName = -12
    }

    open(hReportFile, "$SYNC_DIRECTORY/$SERIAL.txt") or die "Could not open $SERIAL.txt!\n";

    my %phash = ();
    my $package = Package->new();

    while (<hReportFile>)
    {
        # If parsing went off track then reset progress
        if (($parseSuccess == 1) && ($pkgParserCode != $pkgNextParserCode)) {
            $pkgParserCode = 0;
            $pkgNextParserCode = 0;
            ResetPackageStruct($package);
        }

	# Parser code will be 5 if all entries are parsed in order
        # This means we have all data needed for the package and we can update 
        if ($pkgParserCode == 5) {
            # Update package properties like system application or other stuff we need
            MarkSystemApp($package);

            if ($DEBUG_PACKAGES == 1) {
                DbgPrintPackage($package);
            }

            # Add package structure to hash
            $phash{ $package->name } = $package;

            # Create a new package instance and reset progress
            $package = Package->new();
            $pkgNextParserCode = 0;
            next;
        }

        if ($parseSuccess == 1) {
            $pkgNextParserCode += 1;
            $parseSuccess = 0;
        }

        if (/  Package \[[\d\S]+\] \(*[a-f0-9]{6,}\):/i) {
            $STRING_KV = $_;
            # Remove CR-LF to make substr work same on all systems
            $STRING_KV =~ s/\R//g;
            chomp($STRING_KV);
	    $STRING_KV = substr($STRING_KV, 11, $LenParsePkgName);
            $package->name($STRING_KV);
            $pkgParserCode = 1;
            $parseSuccess = 1;

            printD($package->name);
            next;
        }
        if (/    codePath=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 13);
            $package->path($STRING_KV);
            $pkgParserCode = 2;
            $parseSuccess = 1;

            printD($package->path);
            next;
        }
        if (/    versionCode=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 16);
            # Some ADB report also includes targetSdk=X on the same line
            # if so strip it off (get only first element)
            $STRING_KV = (split / /, $STRING_KV)[0];
            $package->version_code($STRING_KV);
            $pkgParserCode = 3;
            $parseSuccess = 1;

            printD($package->version_code);
            next;
        }
        if (/    versionName=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 16);
            $package->version_name($STRING_KV);
            $pkgParserCode = 4;
            $parseSuccess = 1;

            printD($package->version_name);
            next;
        }
        if (/    dataDir=/) {
            $STRING_KV = $_;
            chomp($STRING_KV);
            $STRING_KV = substr($STRING_KV, 12);
            $package->data_path($STRING_KV);
            $pkgParserCode = 5;
            $parseSuccess = 1;

            printD($package->data_path);
            next;
        }

        $parseSuccess = 0;
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
    print "--System: " . $package->system . "\n";
    print "--Path: " . $package->path . "\n";
    print "--Version Code: " . $package->version_code . "\n";
    print "--Version Name: " . $package->version_name . "\n";
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
