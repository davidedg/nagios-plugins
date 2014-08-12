#!/usr/bin/perl -w
# LANEWAN/Davide Del Grande 2014-07-31
use strict;
use warnings;
use Getopt::Long;
my ($opt_V, $opt_h, $opt_script) = "";



sub print_help ();
sub print_usage ();


my $PROGNAME = "check_selenium_perl";
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);



GetOptions(
         "V|version"   => \$opt_V,
         "h|help"   => \$opt_h,
         "s|script=s" => \$opt_script,
);


if ($opt_V) {
        print_help();
        exit $ERRORS{'OK'};
}

if ($opt_h) {
        print_help();
        exit $ERRORS{'OK'};
}

if ( ! $opt_script ) {
        print_help();
        exit $ERRORS{'DEPENDENT'};
}



# Execute SELENIUM PERL script, capturing output
my $output = `perl $opt_script 2>&1`;


my $state = "UNKNOWN";
my $answer = undef;
my $res = undef;
my $perfdata = "";



#
# This matches a SUCCESSFUL pattern:
# "ok 15 - wait_for_page_to_load...."  => /ok \d+.*/   ## can be also "ok 15", hence the "*".
# "PERF_PLUGINTOTAL:46.98"  => /(\n.+_(.+):(.+))/
# "VAR_SESSIONID:499e38a293d04650ace36473eb6a3004"  => /(\n.+_(.+):(.+))/
# "PERF_...."     => /(\n.+_(.+):(.+))*/ ## uses group matching to catch multiple PERF|VAR sections, which can also be empty ("*").
# "1..15"  ==> /\n\d+\.\.\d+$/ ## must end with this, with NO comment section (eg: "# Looks like ...").
#
# Backreferences are: $1: EXTRASECTION (PERF/VAR), to be later parsed.
#

if ( $output =~ m/ok \d+.*((\n.+_(.+):(.+))*)\n\d+\.\.\d+$/g ) { ## SUCCESS with timings and perfdata

    $state = 'OK';
    my $extrasection = $1 . "\n"; ## \n is to match values on last string with a simpler regex

    my (%perfvars, %extravars) = ();
    while($extrasection =~ /PERF_(.+):(.+)\n/g) {
        $perfvars{$1} = $2;
    }
    while ($extrasection =~ /VAR_(.+):(.+)\n/g) {
        $extravars{$1} = $2;
    }

    my $sessionid = "#NOT_RETRIEVED";
    $sessionid = $extravars{'SESSIONID'} if $extravars{'SESSIONID'};

    my $testcasetotal = "#NOT_RETRIEVED";
    $testcasetotal = $perfvars{'TESTCASETOTAL'} if $perfvars{'TESTCASETOTAL'};

    my $plugintotal = "#NOT_RETRIEVED";
    $plugintotal = $perfvars{'PLUGINTOTAL'} if $perfvars{'PLUGINTOTAL'};

    $answer = "OK - Session $sessionid completed in $testcasetotal secs; plugin execution time: $plugintotal secs";


    foreach my $key(keys %perfvars) {
        my $value = $perfvars{$key};
        $perfdata = $perfdata . $key . "=" . $value . " ";
    }
    $perfdata = trim ($perfdata);

} elsif ( $output =~ m/((\n.+_(.+):(.+))*)\n\d+\.\.\d+\n# (Looks like you failed \d+ test of \d+)\./  ) { ## ERROR with timings but no perfdata

    $state = 'CRITICAL';
    my $extrasection = $1 . "\n"; ## \n is to match values on last string with a simpler regex

    my (%perfvars, %extravars) = ();
    while($extrasection =~ /PERF_(.+):(.+)\n/g) {
        $perfvars{$1} = $2;
    }
    while ($extrasection =~ /VAR_(.+):(.+)\n/g) {
        $extravars{$1} = $2;
    }

    my $sessionid = "#NOT_RETRIEVED";
    $sessionid = $extravars{'SESSIONID'} if $extravars{'SESSIONID'};

    my $testcasetotal = "#NOT_RETRIEVED";
    $testcasetotal = $perfvars{'TESTCASETOTAL'} if $perfvars{'TESTCASETOTAL'};

    my $plugintotal = "#NOT_RETRIEVED";
    $plugintotal = $perfvars{'PLUGINTOTAL'} if $perfvars{'PLUGINTOTAL'};


    my $errstring = "#NOT_RETRIEVED";
    if ($output =~ m/\n\d+\.\.\d+\n# (Looks like you failed \d+ test of \d+)\./ ) {
    $errstring = $1;
    }

    $answer = "CRITICAL - Session $sessionid failed with <$errstring> after $testcasetotal secs; plugin execution time: $plugintotal secs" ;

} elsif ( $output =~ m/\n(\d+\.\.\d+)\n# (Looks like your test exited with.*)./ ) { ## ERROR without timings/perfdata

    $state = 'CRITICAL';

    my $errstring = $2;

    my $sessionid = "#NOT_RETRIEVED";
    if ( $output =~ m/VAR_SESSIONID:(.+)\n/ ) {
        $sessionid = $1;
    }

    $answer = "CRITICAL - Session $sessionid failed with <$errstring>";

} else { ## UNKNOWN

    $state = 'UNKNOWN';

    $answer = "UNKNOWN - Check your plugin environment!";

}




print $answer if ($answer);
print " | " . $perfdata if ($perfdata);
print "\n";
exit $ERRORS{$state};


############################################################################
############################################################################
############################################################################

# Some string functions
sub ltrim { my $s = shift; $s =~ s/^\s+//;       return $s };
sub rtrim { my $s = shift; $s =~ s/\s+$//;       return $s };
sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };


sub print_revision ($$) {
        my $commandName = shift;
        my $pluginRevision = shift;
        print "$commandName v$pluginRevision \n";
}

sub print_usage () {
        print "Usage: $PROGNAME -s selenium-script.pl -w <warn> -c <crit>\n";
}

sub print_help () {
        print_revision($PROGNAME,'1.0');
        print_usage();
        print "
-s, --script=SCRIPT

";
}

